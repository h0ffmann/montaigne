import logging
import time
from pathlib import Path
import sys
import abc
# Import torch for CUDA check
import torch
from datetime import datetime
import numpy as np
from typing import Optional # Added Optional import

# Need soundfile for saving chunks
try:
    import soundfile as sf
    SOUNDFILE_AVAILABLE = True
except ImportError:
    sf = None # type: ignore
    SOUNDFILE_AVAILABLE = False

# Piper TTS library
try:
    from piper import PiperVoice
    PIPER_AVAILABLE = True
except ImportError:
    PiperVoice = None # type: ignore
    PIPER_AVAILABLE = False

# Assume sounddevice is installed
try:
    import sounddevice as sd
    SOUNDDEVICE_AVAILABLE = True
except ImportError:
    print("⚠️ Sounddevice library not found. Audio playback might not work. (`pip install sounddevice`)", file=sys.stderr)
    sd = None # type: ignore
    SOUNDDEVICE_AVAILABLE = False


logger = logging.getLogger(__name__)

class PiperStreamingEngine:
    """Streaming TTS implementation using the piper-tts library directly."""
    def __init__(self, model_path: str | Path, use_cuda: bool = True):
        if not PIPER_AVAILABLE:
            raise RuntimeError("piper-tts library is not available. Install with `pip install piper-tts`")
        if not SOUNDDEVICE_AVAILABLE:
            logger.warning("Sounddevice library not available. Playback will likely fail.")

        self.use_cuda = use_cuda
        self.device = self._check_device(use_cuda) # Check CUDA but Piper might handle device internally
        self.model_path = Path(model_path)
        self.voice = self._load_model()
        self.output_dir: Path | None = None # For saving chunks
        self.chunk_counter = 0 # Counter for saved chunks

        logger.info(f"--- Initializing Piper Streaming Engine ---")
        logger.info(f"Using model: {self.model_path.name}")

    def _check_device(self, use_cuda_flag: bool) -> str:
        # Check CUDA availability for logging, Piper/onnxruntime handles actual device use
        is_available = torch.cuda.is_available() if use_cuda_flag else False
        selected_device = "cuda" if is_available else "cpu"
        logger.info(f"CUDA available according to PyTorch: {is_available} (Requested: {use_cuda_flag})")
        logger.info(f"Piper/onnxruntime will attempt to use {'GPU' if selected_device == 'cuda' else 'CPU'}.")
        return selected_device

    def _load_model(self):
        """Loads the Piper TTS model."""
        if not self.model_path.exists() or not self.model_path.is_file():
            raise FileNotFoundError(f"Piper model file not found: {self.model_path}")
        try:
            logger.info(f"Loading Piper model from: {self.model_path}")
            # Pass use_cuda preference to PiperVoice.load
            voice = PiperVoice.load(str(self.model_path), use_cuda=self.use_cuda)
            logger.info("Piper model loaded successfully.")
            return voice
        except Exception as e:
            logger.exception(f"Failed to load Piper model: {self.model_path}")
            raise RuntimeError(f"Could not initialize Piper model '{self.model_path.name}'. Check model file and dependencies.") from e

    def set_output_dir(self, output_dir: Path | None):
        """Sets the directory for saving audio chunks."""
        if output_dir and not SOUNDFILE_AVAILABLE:
             logger.error("SoundFile library is required for saving audio but not found. Install with `pip install soundfile`.")
             self.output_dir = None # Disable saving
             return

        self.output_dir = output_dir
        self.chunk_counter = 0 # Reset counter when dir is set/changed
        if self.output_dir:
            self.output_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Audio chunk saving enabled to: {self.output_dir}")
        else:
            logger.info("Audio chunk saving disabled.")


    def speak(self, text: str):
        """Synthesizes text using Piper and plays it using sounddevice."""
        if not self.voice:
            logger.error("Piper voice model not loaded. Cannot speak.")
            return
        if not sd:
            logger.error("Sounddevice not available. Cannot play audio.")
            return

        logger.debug(f"Synthesizing text with Piper: '{text[:50]}...'")
        start_time = time.time()
        try:
            # Synthesize audio into a buffer (list of int16 samples)
            audio_buffer = []
            # PiperVoice.synthesize_stream returns an iterator yielding bytes
            # We need to collect these bytes and convert them to a numpy array
            # Assuming the output is raw int16 PCM data
            raw_audio_bytes = b"".join(self.voice.synthesize_stream(text))

            # Convert bytes to numpy array (int16)
            # Ensure the byte count is even for int16 conversion
            if len(raw_audio_bytes) % 2 != 0:
                logger.warning("Received odd number of bytes from Piper, discarding last byte.")
                raw_audio_bytes = raw_audio_bytes[:-1]

            if not raw_audio_bytes:
                 logger.warning("Piper synthesis resulted in empty audio.")
                 return

            audio_array = np.frombuffer(raw_audio_bytes, dtype=np.int16)

            # Convert to float32 for sounddevice and saving
            # Normalize int16 range [-32768, 32767] to float32 [-1.0, 1.0]
            audio_float32 = audio_array.astype(np.float32) / 32768.0

            synth_end_time = time.time()
            logger.debug(f"Piper synthesis took {synth_end_time - start_time:.2f}s")

            # --- Saving Chunk (Optional) ---
            if self.output_dir and sf:
                self._save_chunk(audio_float32, self.voice.config.sample_rate)

            # --- Playback ---
            logger.debug(f"Playing audio ({len(audio_float32)/self.voice.config.sample_rate:.2f}s) via sounddevice...")
            sd.play(audio_float32, self.voice.config.sample_rate)
            sd.wait() # Wait for playback to finish
            play_end_time = time.time()
            logger.debug(f"Playback finished (duration: {play_end_time - synth_end_time:.2f}s)")

        except Exception as e:
            logger.exception(f"Error during Piper speak/play")
            print(f"❌ Error generating or playing speech: {e}", file=sys.stderr)

    def _save_chunk(self, chunk_float32: np.ndarray, sample_rate: int):
        """Saves the synthesized audio chunk if output_dir is set."""
        if not self.output_dir or not sf: return # Should be checked before calling

        try:
            self.chunk_counter += 1
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            filename = self.output_dir / f"live_chunk_{self.chunk_counter:04d}_{timestamp}.wav"
            logger.debug(f"Saving audio chunk {self.chunk_counter} to {filename.name}")

            # Soundfile expects float32 or int16. We have float32.
            sf.write(str(filename), chunk_float32, sample_rate)

        except Exception as e:
            logger.error(f"Error saving audio chunk {self.chunk_counter}: {e}", exc_info=True)

    def stop(self):
        """Stops any ongoing audio playback via sounddevice."""
        if sd:
            logger.info("Stopping sounddevice playback...")
            try:
                sd.stop()
            except Exception as e:
                logger.error(f"Error stopping sounddevice: {e}")
        logger.info("Piper streaming engine stopped.")


# --- Interactive Prompt Functionality ---
# (Remains largely the same, but uses PiperStreamingEngine)

def run_interactive_prompt(engine: PiperStreamingEngine, output_dir: Optional[Path] = None):
    """Run an interactive prompt that converts text to speech using Piper."""
    print("🎙️ Montaigne Real-time TTS (Piper Engine)")
    print(f"   Model: {engine.model_path.name}")
    print("Type text and press Enter to hear it spoken.")
    print("Type ':quit' to exit.")

    engine.set_output_dir(output_dir) # Configure saving

    while True:
        try:
            text = input("> ")
            if not text.strip():
                continue
            if text.lower() == ':quit':
                break

            # Simple preprocessing for the REPL (can be expanded later)
            processed_text = text.strip() # Basic strip for now

            engine.speak(processed_text) # Let the engine handle synthesis and playback

        except KeyboardInterrupt:
            print("\nExiting...")
            break
        except EOFError: # Handle Ctrl+D
            print("\nExiting...")
            break

    engine.stop() # Clean up sounddevice
