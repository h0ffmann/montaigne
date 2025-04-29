import logging
import time
from pathlib import Path
import sys
import abc
import torch

# Assume RealtimeTTS and necessary engines are installed via pyproject.toml
try:
    from realtimetts import TextToAudioStream, CoquiEngine, SystemEngine, BaseEngine
    REALTINETTS_AVAILABLE = True
except ImportError:
    print("❌ RealtimeTTS library not found. Please install it (`pip install realtimetts`)", file=sys.stderr)
    # Define dummy classes to avoid import errors elsewhere if initialization fails later
    class BaseEngine: pass
    class TextToAudioStream: pass
    class CoquiEngine: pass
    class SystemEngine: pass
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

    def initialize_engine(self, speaker_wav: str | Path | None = None, language: str = "en"):
        """Initializes the CoquiEngine backend and TextToAudioStream."""
        logger.info("Initializing RealtimeTTS Engine...")

        # --- Backend Selection (MVP: Prioritize Coqui if speaker_wav is given, else System) ---
        if speaker_wav:
            speaker_wav_path = Path(speaker_wav)
            if speaker_wav_path.exists() and speaker_wav_path.is_file():
                try:
                    logger.info(f"Attempting to initialize RealtimeTTS with CoquiEngine (Speaker: {speaker_wav_path.name}, Lang: {language})...")
                    # CoquiEngine requires speaker_wav and language if not using default.
                    self.engine_backend = CoquiEngine(
                        model_name="tts_models/multilingual/multi-dataset/xtts_v2",
                        language=language,
                        speaker_wav=str(speaker_wav_path),
                        # Note: RealtimeTTS might manage device selection internally,
                        # but providing `device=self.device` can be explicit.
                        device=self.device
                    )
                    logger.info(f"Using CoquiEngine with speaker {speaker_wav_path.name}.")
                except Exception as e:
                    logger.error(f"Failed to initialize CoquiEngine: {e}. Falling back...", exc_info=True)
                    self.engine_backend = None
            else:
                logger.warning(f"Provided speaker_wav '{speaker_wav}' not found or invalid. Falling back.")
                self.engine_backend = None
        else:
             logger.info("No speaker_wav provided. Initializing without CoquiEngine.")
             self.engine_backend = None


        # Fallback if Coqui wasn't initialized
        if self.engine_backend is None:
             logger.info("Falling back to SystemEngine (uses OS default TTS).")
             try:
                 # Check if system engine is actually available (e.g., on headless systems)
                 if SystemEngine.is_engine_available():
                      self.engine_backend = SystemEngine()
                      logger.info("Using SystemEngine.")
                 else:
                     logger.error("System TTS engine is not available on this system.")
                     raise RuntimeError("No suitable RealtimeTTS backend could be initialized (Coqui failed/not requested, System unavailable).")
             except Exception as e:
                 logger.error(f"Failed to initialize SystemEngine: {e}", exc_info=True)
                 raise RuntimeError("Could not initialize any TTS backend for RealtimeTTS.") from e


        if not isinstance(self.engine_backend, BaseEngine):
             raise RuntimeError("Failed to set a valid engine_backend.")

        # --- Initialize the Stream ---
        logger.info("Initializing TextToAudioStream...")
        try:
            self.stream = TextToAudioStream(self.engine_backend)
            # You can add callbacks here later for lag analysis etc.
            # on_audio_chunk=self._on_audio_chunk
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
