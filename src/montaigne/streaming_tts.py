import logging
import time
from pathlib import Path
import sys
import abc
import torch
from datetime import datetime
import numpy as np

# Need soundfile for saving chunks
try:
    import soundfile as sf
    SOUNDFILE_AVAILABLE = True
except ImportError:
    sf = None # type: ignore
    SOUNDFILE_AVAILABLE = False

# Assume RealtimeTTS and necessary engines are installed via pyproject.toml
try:
    from realtimetts import TextToAudioStream, CoquiEngine, SystemEngine, PiperEngine, BaseEngine
    REALTINETTS_AVAILABLE = True
except ImportError:
    print("❌ RealtimeTTS library not found. Please install it (`pip install realtimetts` and potentially `piper-tts`)", file=sys.stderr)
    # Define dummy classes to avoid import errors elsewhere if initialization fails later
    class BaseEngine: pass
    class TextToAudioStream: pass
    class CoquiEngine: pass
    class SystemEngine: pass
    class PiperEngine: pass # Add dummy PiperEngine
    REALTINETTS_AVAILABLE = False

# Assume sounddevice is installed
try:
    import sounddevice as sd
    SOUNDDEVICE_AVAILABLE = True
except ImportError:
    print("⚠️ Sounddevice library not found. Audio playback might not work. (`pip install sounddevice`)", file=sys.stderr)
    SOUNDDEVICE_AVAILABLE = False


logger = logging.getLogger(__name__)

class BaseStreamingEngine(abc.ABC):
    """Abstract Base Class for Streaming Text-to-Speech Engines."""
    def __init__(self, use_cuda: bool = True):
        self.use_cuda = use_cuda
        self.device = self._check_device(use_cuda)
        self.engine_backend = None # The actual backend instance (e.g., CoquiEngine)
        self.stream = None # The TextToAudioStream instance
        self.output_dir: Path | None = None # Added to store output directory
        self.chunk_counter = 0 # Counter for saved chunks

        if not REALTINETTS_AVAILABLE:
             raise RuntimeError("RealtimeTTS library is not available.")
        if not SOUNDDEVICE_AVAILABLE:
             logger.warning("Sounddevice library not available. Playback will likely fail.")

        logger.info(f"--- Initializing Streaming Engine ({self.__class__.__name__}) ---")

    def _check_device(self, use_cuda_flag: bool) -> str:
        # Simplified check for streaming engine
        is_available = torch.cuda.is_available() if use_cuda_flag else False
        selected_device = "cuda" if is_available else "cpu"
        logger.info(f"Streaming engine selected device: {selected_device}")
        if selected_device == "cpu":
             logger.warning(f"Streaming Engine ({self.__class__.__name__}) will run on CPU.")
        return selected_device

    @abc.abstractmethod
    def initialize_engine(self, **kwargs):
        """Initializes the backend engine and the TextToAudioStream."""
        pass

    @abc.abstractmethod
    def speak(self, text: str, **kwargs):
        """Synthesizes and plays back the given text immediately."""
        pass

    def stop(self):
        """Stops any ongoing audio stream."""
        if self.stream:
            logger.info("Stopping audio stream...")
            try:
                self.stream.stop()
            except Exception as e:
                logger.error(f"Error stopping stream: {e}")
        logger.info("Streaming engine stopped.")

# --- RealtimeTTS Implementation ---

class RealtimeTTSEngine(BaseStreamingEngine):
    """Streaming TTS implementation using the RealtimeTTS library."""

    def initialize_engine(
        self,
        backend_engine: str, # Added: 'coqui', 'system', 'piper'
        speaker_wav: str | Path | None = None, # Used by Coqui
        language: str = "en", # Used by Coqui/Piper
        piper_model_path: Path | None = None, # Used by Piper
        output_dir: Path | None = None # Used for saving
    ):
        """Initializes the selected backend engine and TextToAudioStream."""
        logger.info(f"Initializing RealtimeTTS with backend: {backend_engine}...")
        self.output_dir = output_dir # Store for use in callback
        self.chunk_counter = 0 # Reset counter on init

        if self.output_dir and not SOUNDFILE_AVAILABLE:
             logger.error("SoundFile library is required for saving audio but not found. Install with `pip install soundfile`.")
             raise RuntimeError("SoundFile not available for audio saving.")

        # --- Backend Selection ---
        self.engine_backend = None # Reset before selection

        if backend_engine == 'coqui':
            if speaker_wav:
                speaker_wav_path = Path(speaker_wav)
                if speaker_wav_path.exists() and speaker_wav_path.is_file():
                    try:
                        logger.info(f"Attempting to initialize CoquiEngine (Speaker: {speaker_wav_path.name}, Lang: {language})...")
                        self.engine_backend = CoquiEngine(
                            model_name="tts_models/multilingual/multi-dataset/xtts_v2",
                            language=language,
                            speaker_wav=str(speaker_wav_path),
                            device=self.device # Pass explicit device
                        )
                        logger.info(f"Using CoquiEngine with speaker {speaker_wav_path.name}.")
                    except Exception as e:
                        logger.error(f"Failed to initialize CoquiEngine: {e}. Check speaker file format/TTS install.", exc_info=True)
                        # Fallback handled by main CLI logic if Coqui fails init
                else:
                    logger.warning(f"Provided speaker_wav '{speaker_wav}' not found or invalid for Coqui.")
            else:
                 logger.warning("Coqui backend selected, but no valid speaker_wav provided.")
                 # Fallback should be handled by CLI logic before calling initialize_engine

        elif backend_engine == 'piper':
            if piper_model_path and piper_model_path.exists():
                try:
                    logger.info(f"Attempting to initialize PiperEngine (Model: {piper_model_path.name}, Lang: {language})...")
                    # PiperEngine needs the model path. Language might be inferred or used internally.
                    # Device selection might be handled internally by Piper/onnxruntime.
                    # Check RealtimeTTS PiperEngine docs for explicit device passing if needed.
                    self.engine_backend = PiperEngine(
                        model_path=str(piper_model_path),
                        # language=language # Pass language if PiperEngine supports it directly
                        use_cuda=(self.device == 'cuda') # Pass cuda preference
                    )
                    logger.info(f"Using PiperEngine with model {piper_model_path.name}.")
                except Exception as e:
                    logger.error(f"Failed to initialize PiperEngine: {e}. Check model path/piper install.", exc_info=True)
            else:
                logger.error(f"Piper backend selected, but required model path '{piper_model_path}' is invalid or missing.")

        elif backend_engine == 'system':
            logger.info("Attempting to initialize SystemEngine...")
            try:
                if SystemEngine.is_engine_available():
                    self.engine_backend = SystemEngine()
                    logger.info("Using SystemEngine.")
                else:
                    logger.error("System TTS engine is not available on this system.")
            except Exception as e:
                logger.error(f"Failed to initialize SystemEngine: {e}", exc_info=True)

        else:
             logger.error(f"Unknown backend engine specified: {backend_engine}")


        # Check if any backend was successfully initialized
        if self.engine_backend is None:
             raise RuntimeError(f"Could not initialize the selected backend engine '{backend_engine}'. Check logs for details.")

        if not isinstance(self.engine_backend, BaseEngine):
             # This case should ideally be caught by the check above, but safety first.
             raise RuntimeError("Initialization resulted in an invalid engine_backend type.")

        # --- Initialize the Stream ---
        logger.info("Initializing TextToAudioStream...")
        try:
            # Add callback if output_dir is set
            callback = self._on_audio_chunk if self.output_dir else None
            if callback:
                 logger.info(f"Audio chunk saving enabled to: {self.output_dir}")

            self.stream = TextToAudioStream(
                self.engine_backend,
                on_audio_chunk=callback,
                # Add other callbacks later if needed for monitoring
                # on_stream_start=...,
                # on_stream_stop=...,
            )
            logger.info("TextToAudioStream initialized successfully.")
        except Exception as e:
            logger.exception("Failed to initialize TextToAudioStream")
            raise RuntimeError("Could not initialize RealtimeTTS TextToAudioStream.") from e


    def speak(self, text: str):
        """Feeds text to the stream and plays it."""
        if not self.stream:
            logger.error("RealtimeTTS stream not initialized. Cannot speak.")
            return

        logger.debug(f"Feeding text to RealtimeTTS: '{text[:50]}...'")
        start_time = time.time()
        try:
            self.stream.feed(text)
            self.stream.play_async() # Use async playback
            # In a full implementation, you might wait or manage the playback differently
            # For MVP REPL, playing async allows quick response. We might need `stream.wait()` or better control later.
            # Let's add a short pause to allow playback to start, hacky for MVP.
            # A better solution involves monitoring playback state via callbacks.
            # time.sleep(0.1) # Avoid this if possible, rely on async nature for MVP.
            end_time = time.time()
            logger.debug(f"Feeding and starting playback took {end_time - start_time:.2f}s")
        except Exception as e:
            logger.exception(f"Error during RealtimeTTS speak/play")
            print(f"❌ Error generating or playing speech: {e}", file=sys.stderr)

    def _on_audio_chunk(self, chunk: np.ndarray, sample_rate: int):
        """Callback function to save audio chunks when output_dir is set."""
        if not self.output_dir or not SOUNDFILE_AVAILABLE or sf is None:
            return # Should not happen if check in init passed, but safety first

        try:
            self.chunk_counter += 1
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            filename = self.output_dir / f"live_chunk_{self.chunk_counter:04d}_{timestamp}.wav"
            logger.debug(f"Saving audio chunk {self.chunk_counter} to {filename.name}")

            # Ensure chunk is float32 for soundfile if it's not already
            if chunk.dtype != np.float32:
                 chunk = chunk.astype(np.float32)

            # Normalize if needed? RealtimeTTS chunks seem reasonably scaled.
            # max_val = np.max(np.abs(chunk))
            # if max_val > 1.0:
            #     chunk = chunk / max_val

            sf.write(str(filename), chunk, sample_rate)

        except Exception as e:
            logger.error(f"Error saving audio chunk {self.chunk_counter}: {e}", exc_info=True)
"""
Streaming TTS module for real-time text-to-speech capabilities.
"""
import logging
import time
import numpy as np
from pathlib import Path
from typing import Optional, Callable, Dict, Any, List

# Audio playback libraries
try:
    import sounddevice as sd
    SOUNDDEVICE_AVAILABLE = True
except ImportError:
    SOUNDDEVICE_AVAILABLE = False

# RealtimeTTS library
try:
    from realtimetts import TextToAudioStream, PiperEngine, EdgeTTSEngine
    REALTIMETTS_AVAILABLE = True
except ImportError:
    TextToAudioStream = None  # type: ignore
    PiperEngine = None  # type: ignore
    EdgeTTSEngine = None  # type: ignore
    REALTIMETTS_AVAILABLE = False

# Check for torch separately
try:
    import torch
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False

logger = logging.getLogger(__name__)

class TTSMonitor:
    """Monitors and displays TTS performance metrics."""

    def __init__(self):
        self.words_received = 0
        self.words_processed = 0
        self.words_played = 0
        self.lag_measurements = []
        self.start_time = None

    def start(self):
        """Start monitoring."""
        self.start_time = time.time()

    def update(self, words_received: int, words_processed: int, words_played: int):
        """Update metrics."""
        self.words_received = words_received
        self.words_processed = words_processed
        self.words_played = words_played

        # Calculate lag
        current_lag = words_received - words_played
        self.lag_measurements.append(current_lag)

    def display(self):
        """Display current metrics."""
        if not self.start_time:
            return

        elapsed = time.time() - self.start_time
        avg_lag = sum(self.lag_measurements) / len(self.lag_measurements) if self.lag_measurements else 0

        print(f"\rWords in queue: {self.words_received - self.words_played} | "
              f"Avg lag: {avg_lag:.2f} words | "
              f"Processing rate: {self.words_processed / elapsed:.2f} words/sec",
              end="")


class AudioRecorder:
    """Records and saves audio chunks to a file."""

    def __init__(self, output_path: Path, sample_rate: int = 22050):
        self.output_path = output_path
        self.sample_rate = sample_rate
        self.chunks = []

    def add_chunk(self, audio_chunk: np.ndarray):
        """Add an audio chunk to the recording."""
        self.chunks.append(audio_chunk)

    def save(self):
        """Save the complete audio to file."""
        if not self.chunks:
            return False

        try:
            # Combine chunks
            full_audio = np.concatenate(self.chunks)

            # Import here to avoid dependency issues if not needed
            import soundfile as sf

            # Create parent directory if it doesn't exist
            self.output_path.parent.mkdir(parents=True, exist_ok=True)

            # Save to file
            sf.write(str(self.output_path), full_audio, self.sample_rate)
            logger.info(f"✅ Audio saved to: {self.output_path}")
            return True
        except Exception as e:
            logger.error(f"Error saving audio to {self.output_path}: {e}")
            return False


class StreamingTTSEngine:
    """Base class for streaming TTS functionality."""

    def __init__(self, engine_name: str, use_cuda: bool = True):
        self.engine_name = engine_name
        self.use_cuda = use_cuda
        self.streaming_engine = None
        self.active = False
        self.monitor = TTSMonitor()
        self.recorder = None
        self.device = self._check_device(use_cuda)
        self.init_streaming_engine()

    def _check_device(self, use_cuda_flag: bool) -> str:
        """Checks CUDA availability and returns the appropriate device."""
        logger.info(f"Checking CUDA availability (use_cuda={use_cuda_flag})")
        is_available = False

        if not use_cuda_flag:
            logger.info("CUDA usage explicitly disabled via --cpu flag.")
        else:
            if TORCH_AVAILABLE:
                is_available = torch.cuda.is_available()
                logger.info(f"torch.cuda.is_available() check returned: {is_available}")
                if is_available:
                    count = torch.cuda.device_count()
                    logger.info(f"Detected {count} CUDA device(s).")
            else:
                logger.warning("PyTorch not available. CUDA support will be limited.")

        selected_device = "cuda" if use_cuda_flag and is_available else "cpu"
        logger.info(f"Selected device: {selected_device}")
        if selected_device == "cpu":
            logger.warning(f"{self.__class__.__name__} will run on CPU. Inference may be slow.")
        return selected_device

    def init_streaming_engine(self):
        """Initialize the specific streaming engine implementation."""
        pass

    def stream_text(self, text: str, output_path: Optional[Path] = None, **kwargs) -> bool:
        """Stream text to audio with optional saving to output_path."""
        pass

    def stop_streaming(self):
        """Stop any ongoing streaming."""
        self.active = False
        if self.recorder:
            self.recorder.save()
        self.recorder = None

    def _on_audio_chunk(self, audio_chunk: np.ndarray):
        """Process and play audio chunk. Override in subclasses."""
        # If we have a recorder, add the chunk to it
        if self.recorder:
            self.recorder.add_chunk(audio_chunk)

        # Play the audio if sounddevice is available
        if SOUNDDEVICE_AVAILABLE:
            self._play_audio_chunk(audio_chunk)

    def _on_stream_start(self):
        """Called when streaming starts."""
        self.active = True
        self.monitor.start()

    def _on_stream_stop(self):
        """Called when streaming stops."""
        self.active = False
        print("\n✅ Streaming complete.")

    def _play_audio_chunk(self, audio_chunk: np.ndarray, sample_rate: int = 22050):
        """Play an audio chunk through system speakers."""
        if not SOUNDDEVICE_AVAILABLE:
            return

        # Convert audio to float32 if needed
        if audio_chunk.dtype != np.float32:
            audio_chunk = audio_chunk.astype(np.float32)

        try:
            # Play audio
            sd.play(audio_chunk, sample_rate)
            sd.wait()  # Wait until audio is finished playing
        except Exception as e:
            logger.error(f"Error playing audio chunk: {e}")


class RealtimeTTSEngine(StreamingTTSEngine):
    """Implementation using RealtimeTTS library."""

    def __init__(self, use_cuda: bool = True):
        if not REALTIMETTS_AVAILABLE:
            raise RuntimeError("RealtimeTTS library not found. Please install it (`pip install realtimetts`)")
        super().__init__("realtimetts", use_cuda)

    def init_streaming_engine(self):
        """Initialize the RealtimeTTS engine."""
        if not REALTIMETTS_AVAILABLE:
            logger.error("RealtimeTTS not available. Cannot initialize engine.")
            return

        logger.info("Initializing RealtimeTTS streaming engine...")
        try:
            # Choose appropriate engine based on availability
            if self.use_cuda and TORCH_AVAILABLE and torch.cuda.is_available():
                # Use GPU-accelerated engine (Piper) if available
                logger.info("Initializing Piper TTS engine (GPU-accelerated)")
                engine = PiperEngine()
            else:
                # Fallback to CPU-friendly engine (EdgeTTS)
                logger.info("Initializing EdgeTTS engine (CPU-friendly)")
                engine = EdgeTTSEngine()

            self.streaming_engine = TextToAudioStream(
                engine=engine,
                on_audio_chunk=self._on_audio_chunk,
                on_stream_start=self._on_stream_start,
                on_stream_stop=self._on_stream_stop
            )
            logger.info("RealtimeTTS engine initialized successfully")
        except Exception as e:
            logger.exception("Failed to initialize RealtimeTTS engine")
            raise RuntimeError(f"Could not initialize RealtimeTTS engine: {e}")

    def _update_monitor(self, words_received, words_processed, words_played):
        """Update the monitor with current metrics."""
        if self.monitor:
            self.monitor.update(words_received, words_processed, words_played)
            self.monitor.display()

    def stream_text(self, text: str, output_path: Optional[Path] = None, **kwargs) -> bool:
        """Stream text to audio with RealtimeTTS."""
        if not self.streaming_engine:
            logger.error("RealtimeTTS engine not initialized.")
            return False

        # Setup recorder if output_path is provided
        if output_path:
            self.recorder = AudioRecorder(output_path)
            logger.info(f"Audio will be saved to: {output_path}")

        try:
            # Track word metrics manually
            words_total = len(text.split())
            words_current = 0

            # Define a callback for tracking progress
            def progress_callback(num_chars_processed):
                nonlocal words_current
                # Estimate words processed based on character ratio
                ratio = num_chars_processed / max(len(text), 1)
                words_processed = int(words_total * ratio)
                if words_processed != words_current:
                    words_current = words_processed
                    # Assuming words_played lags slightly behind words_processed
                    words_played = max(0, words_processed - 2)
                    self._update_monitor(words_total, words_processed, words_played)

            # Stream the text
            logger.info(f"Streaming text ({len(text)} characters, ~{words_total} words)...")
            print("🎙️ Streaming audio... (Press Ctrl+C to stop)")

            # Start streaming
            self.active = True
            self.streaming_engine.tts_stream(
                text,
                progress_callback=progress_callback,
                **kwargs
            )

            # Wait for streaming to complete naturally
            while self.active:
                time.sleep(0.1)

            # Final update
            self._update_monitor(words_total, words_total, words_total)
            print()  # Add newline after progress display

            # Save recording if needed
            if self.recorder and output_path:
                success = self.recorder.save()
                if success:
                    print(f"✅ Audio saved to: {output_path}")

            return True
        except KeyboardInterrupt:
            print("\n⏹️ Streaming stopped by user.")
            self.stop_streaming()
            return False
        except Exception as e:
            logger.exception("Error during RealtimeTTS streaming")
            print(f"❌ Error during streaming: {e}")
            self.stop_streaming()
            return False


def run_interactive_prompt(engine: StreamingTTSEngine, output_dir: Optional[Path] = None):
    """Run an interactive prompt that converts text to speech in real-time."""
    print("🎙️ Montaigne Real-time TTS")
    print("Type text and press Enter to hear it spoken.")
    print("Type ':quit' to exit, ':help' for commands.")

    session_num = int(time.time())

    while True:
        try:
            text = input("> ")
            if text.lower() == ':quit':
                break
            elif text.lower() == ':help':
                print_help()
            elif text.startswith(':'):
                handle_command(text, engine)
            else:
                # Create output path for this prompt if output_dir is provided
                output_path = None
                if output_dir:
                    output_path = output_dir / f"tts_live_{session_num}_{int(time.time())}.wav"

                # Stream text to audio in real-time
                engine.stream_text(
                    text,
                    output_path=output_path
                )
        except KeyboardInterrupt:
            print("\nExiting...")
            break


def print_help():
    """Print help information for interactive mode."""
    print("Available commands:")
    print("  :help       - Show this help message")
    print("  :quit       - Exit the interactive prompt")
    # Future commands could include voice selection, language selection, etc.


def handle_command(command: str, engine: StreamingTTSEngine):
    """Handle special commands in interactive mode."""
    # Simple command handling for now
    print(f"Unknown command: {command}")
    print("Type ':help' for available commands.")


def map_montaigne_voice_to_streaming(voice_profile: str):
    """Map Montaigne voice profile to streaming engine voice."""
    # Basic voice profile mapping
    VOICE_PROFILE_MAPPING = {
        "trump": "en_US/trump",
        "obama": "en_US/obama",
        "biden": "en_US/biden",
    }

    # For RealtimeTTS with Piper engine
    if voice_profile in ["trump", "obama", "biden"]:
        return f"en_US/{voice_profile}"

    # For other profiles, use default mapping
    return VOICE_PROFILE_MAPPING.get(voice_profile, "en_US/cmu-arctic_low#rms")
