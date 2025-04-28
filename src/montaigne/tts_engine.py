import logging
import torch
from pathlib import Path
import time
import warnings
import abc
import os
import numpy as np

# Attempt to import necessary libraries, provide clear errors if missing
try:
    from TTS.api import TTS
    TTS_AVAILABLE = True
except ImportError:
    TTS = None # type: ignore
    TTS_AVAILABLE = False

try:
    from bark import SAMPLE_RATE as BARK_SAMPLE_RATE
    from bark import generate_audio, preload_models
    from bark.generation import SUPPORTED_LANGS as BARK_SUPPORTED_LANGS
    # Use soundfile for saving Bark output reliably
    import soundfile as sf
    SOUNDFILE_AVAILABLE = True
    BARK_AVAILABLE = True
except ImportError:
    BARK_SAMPLE_RATE = 24000 # Default Bark sample rate
    generate_audio = None # type: ignore
    preload_models = None # type: ignore
    BARK_SUPPORTED_LANGS = []
    sf = None # type: ignore
    SOUNDFILE_AVAILABLE = False
    BARK_AVAILABLE = False


logger = logging.getLogger(__name__)
XTTS_MODEL_NAME = "tts_models/multilingual/multi-dataset/xtts_v2"

# --- Base Class Definition ---
class BaseTTSEngine(abc.ABC):
    """Abstract Base Class for Text-to-Speech Engines."""
    def __init__(self, use_cuda: bool = True):
        self.use_cuda = use_cuda
        self.device = self._check_device(use_cuda)
        self.model = None
        logger.info(f"--- Initializing {self.__class__.__name__} ---")
        logger.info(f"PyTorch version: {torch.__version__}")

    def _check_device(self, use_cuda_flag: bool) -> str:
        """Checks CUDA availability and returns the appropriate device."""
        logger.info(f"Checking CUDA availability (use_cuda={use_cuda_flag})")
        is_available = False
        if not use_cuda_flag:
            logger.info("CUDA usage explicitly disabled via --cpu flag.")
        else:
            # Simple check first
            is_available = torch.cuda.is_available()
            logger.info(f"torch.cuda.is_available() check returned: {is_available}")
            if is_available:
                 try:
                    # Try to load driver library as an extra check
                    import ctypes
                    ctypes.CDLL("libcuda.so.1")
                    logger.info("libcuda.so.1 found and loaded (basic check).")
                    count = torch.cuda.device_count()
                    logger.info(f"Detected {count} CUDA device(s).")
                 except Exception as e:
                     logger.warning(f"CUDA reported available, but driver check failed: {e}", exc_info=False)
                     # Proceed assuming PyTorch check is sufficient, but log warning
            else:
                logger.warning("torch.cuda.is_available() returned False.")

        selected_device = "cuda" if use_cuda_flag and is_available else "cpu"
        logger.info(f"Selected device: {selected_device}")
        if selected_device == "cpu":
             logger.warning(f"{self.__class__.__name__} will run on CPU. Inference may be slow.")
        return selected_device

    @abc.abstractmethod
    def _load_model(self):
        """Loads the specific TTS model."""
        pass

    @abc.abstractmethod
    def synthesize(self, text: str, language: str, output_path: Path, **kwargs) -> bool:
        """
        Synthesizes speech from text and saves it to output_path.

        Args:
            text: The text to synthesize.
            language: Language code (engine-specific handling).
            output_path: Path to save the output audio file.
            **kwargs: Engine-specific parameters (e.g., speaker_wav, speed).

        Returns:
            True if synthesis was successful, False otherwise.
        """
        pass


# --- XTTS Engine Implementation ---
class XTTSv2Engine(BaseTTSEngine):
    """TTS Engine using Coqui XTTSv2."""
    def __init__(self, use_cuda: bool = True):
        if not TTS_AVAILABLE:
             raise RuntimeError("Coqui TTS library not found. Please install it (`pip install TTS`)")
        super().__init__(use_cuda)
        self.model = self._load_model()

    def _load_model(self):
        logger.info(f"Loading TTS model '{XTTS_MODEL_NAME}' onto device: {self.device}")
        try:
            # --- Alternative: Use weights_only context manager ---
            logger.info("Attempting to load model within torch.serialization.weights_only(False) context.")
            from torch.serialization import weights_only
            start_time = time.time()
            with warnings.catch_warnings(), weights_only(False): # Wrap TTS init
                warnings.simplefilter("ignore", UserWarning)
                # TTS checks for CUDA itself, but passing the device is good practice
                model = TTS(model_name=XTTS_MODEL_NAME, progress_bar=True).to(self.device)
            end_time = time.time()
            logger.info(f"TTS model '{XTTS_MODEL_NAME}' loaded in {end_time - start_time:.2f} seconds.")
            return model
        except Exception as e:
            logger.exception(f"Failed to load TTS model: {XTTS_MODEL_NAME}")
            # Include Coqui TTS license acceptance in hints
            hint = ("Check logs, dependencies (TTS, PyTorch), "
                    "Python version compatibility, network connection, "
                    "and ensure you have accepted the Coqui TTS license terms.")
            raise RuntimeError(f"Could not initialize TTS model '{XTTS_MODEL_NAME}'. {hint}") from e

    def synthesize(self, text: str, language: str, output_path: Path, **kwargs) -> bool:
        """Synthesizes using XTTSv2."""
        speaker_wav = kwargs.get("speaker_wav")
        speed = kwargs.get("speed", 1.0)

        if not speaker_wav:
             logger.error("XTTSv2Engine requires 'speaker_wav' parameter.")
             return False
        if not Path(speaker_wav).is_file():
            logger.error(f"Speaker reference file not found: {speaker_wav}")
            raise FileNotFoundError(f"Speaker reference file not found: {speaker_wav}")

        logger.info(f"Synthesizing audio to: {output_path.name} using XTTSv2")
        logger.info(f"Params: Lang={language}, Speed={speed}, Speaker={Path(speaker_wav).name}")
        logger.debug(f"Full Text Length: {len(text)} chars")

        if self.model is None:
             logger.error("XTTS model not loaded.")
             return False

        try:
            start_time = time.time()
            self.model.tts_to_file(
                text=text, speaker_wav=str(speaker_wav), language=language,
                file_path=str(output_path), speed=speed, split_sentences=True
            )
            end_time = time.time()
            logger.info(f"XTTS Synthesis complete in {end_time - start_time:.2f} seconds.")
            print(f"✅ Audio successfully saved to: {output_path}")
            return True
        except Exception as e:
            logger.exception(f"XTTS synthesis failed")
            print(f"❌ Error during XTTS synthesis: {e}")
            if output_path.exists():
                try: output_path.unlink(missing_ok=True) # Py 3.8+
                except OSError: pass
            return False


# --- Bark Engine Implementation ---
class BarkEngine(BaseTTSEngine):
    """TTS Engine using Suno AI's Bark."""
    def __init__(self, use_cuda: bool = True):
        if not BARK_AVAILABLE:
             raise RuntimeError("Bark library not found. Please install it (`pip install bark`)")
        if not SOUNDFILE_AVAILABLE:
             raise RuntimeError("SoundFile library not found. Please install it (`pip install soundfile`) for Bark output.")
        super().__init__(use_cuda)
        # Bark manages device internally but preload can be guided
        self.model = self._load_model() # Preload models

    def _load_model(self):
        logger.info(f"Loading Bark models... (Device selection is managed internally by Bark/PyTorch based on availability)")
        # We don't store the 'model' per se, just preload. Bark's functions handle device selection.
        # We still need to respect the --cpu flag by potentially forcing the device if Bark allows.
        # However, Bark's generate_audio doesn't take an explicit device flag. It relies on
        # PyTorch's default device unless specific environment variables are set (e.g., CUDA_VISIBLE_DEVICES)
        # Let's just ensure the check runs and preload the models.
        original_cuda_visible = os.environ.get("CUDA_VISIBLE_DEVICES")
        if self.device == "cpu":
             logger.info("Attempting to force Bark to use CPU by setting CUDA_VISIBLE_DEVICES=-1")
             os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

        try:
            start_time = time.time()
            if preload_models: # Check if import succeeded
                 preload_models() # Downloads and loads models as needed
            else:
                 raise RuntimeError("Bark's preload_models function not available.")
            end_time = time.time()
            logger.info(f"Bark models preloaded in {end_time - start_time:.2f} seconds.")
            # Restore env var if we changed it
            if self.device == "cpu":
                 if original_cuda_visible is None:
                     if "CUDA_VISIBLE_DEVICES" in os.environ: del os.environ["CUDA_VISIBLE_DEVICES"]
                 else:
                     os.environ["CUDA_VISIBLE_DEVICES"] = original_cuda_visible
            return True # Indicate loading successful
        except Exception as e:
            # Restore env var on error too
            if self.device == "cpu":
                 if original_cuda_visible is None:
                     if "CUDA_VISIBLE_DEVICES" in os.environ: del os.environ["CUDA_VISIBLE_DEVICES"]
                 else:
                     os.environ["CUDA_VISIBLE_DEVICES"] = original_cuda_visible

            logger.exception(f"Failed to preload Bark models")
            hint = "Check logs, dependencies (bark, transformers, pytorch), network connection."
            raise RuntimeError(f"Could not initialize Bark models. {hint}") from e


    def synthesize(self, text: str, language: str, output_path: Path, **kwargs) -> bool:
        """Synthesizes using Bark."""
        # Bark doesn't use speaker wavs or speed in the same way.
        # Language is used via 'history prompts' typically. Let's check if provided lang is supported.
        speaker_prompt = kwargs.get("speaker_prompt", None) # Allow passing specific bark prompt
        logger.info(f"Synthesizing audio to: {output_path.name} using Bark")
        logger.info(f"Params: Lang={language}")
        if speaker_prompt: logger.info(f"Speaker Prompt: {speaker_prompt}")
        logger.debug(f"Full Text Length: {len(text)} chars")

        if not self.model: # Check if preloading indicated success
             logger.error("Bark models not preloaded.")
             return False
        if not generate_audio or not sf:
            logger.error("Bark or Soundfile function not available.")
            return False

        # Basic language check - Bark primarily uses history prompts for speaker/language.
        # We can attempt to use a generic language prompt if available.
        # Bark official docs list: en, zh, fr, de, hi, it, ja, ko, pl, pt, ru, es, tr
        simple_lang_code = language.split('-')[0].lower()
        # BARK_SUPPORTED_LANGS is a list of tuples like ('English', 'en')
        bark_lang_supported = any(lang_tuple[1].startswith(simple_lang_code) for lang_tuple in BARK_SUPPORTED_LANGS if isinstance(lang_tuple, (tuple, list)) and len(lang_tuple) > 1)

        history_prompt = speaker_prompt # Use user provided first
        if not history_prompt:
            if bark_lang_supported:
                # Construct a *valid* generic history prompt (e.g., "en_speaker_0")
                # Assuming index 0 is a reasonable default.
                history_prompt = f"{simple_lang_code}_speaker_0"
                logger.info(f"Using generic Bark history prompt: {history_prompt}")
            else:
                 logger.warning(f"Language '{language}' ({simple_lang_code}) not directly listed in Bark presets. Bark may default to English or perform poorly.")
                 # Proceed without a history prompt, Bark might default

        # Set CUDA_VISIBLE_DEVICES again if needed for this specific call context?
        # Seems risky, rely on preload having set the stage.
        original_cuda_visible = os.environ.get("CUDA_VISIBLE_DEVICES")
        if self.device == "cpu" and original_cuda_visible != "-1":
            # Temporarily set it for the generation call if we need CPU
            logger.debug("Setting CUDA_VISIBLE_DEVICES=-1 for generate_audio")
            os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

        try:
            start_time = time.time()
            # Generate audio data (NumPy array)
            audio_array = generate_audio(text, history_prompt=history_prompt)
            end_time = time.time()

            logger.info(f"Bark Synthesis complete in {end_time - start_time:.2f} seconds.")

            # Save the audio array to a WAV file using soundfile
            logger.info(f"Saving Bark audio (sample rate: {BARK_SAMPLE_RATE}) to {output_path}...")
            output_path.parent.mkdir(parents=True, exist_ok=True)
            sf.write(str(output_path), audio_array, BARK_SAMPLE_RATE)

            print(f"✅ Audio successfully saved to: {output_path}")
            return True
        except Exception as e:
            logger.exception(f"Bark synthesis failed")
            print(f"❌ Error during Bark synthesis: {e}")
            if output_path.exists():
                try: output_path.unlink(missing_ok=True)
                except OSError: pass
            return False
        finally:
             # Always restore CUDA_VISIBLE_DEVICES
             if self.device == "cpu" and os.environ.get("CUDA_VISIBLE_DEVICES") == "-1":
                  if original_cuda_visible is None:
                     if "CUDA_VISIBLE_DEVICES" in os.environ:
                         logger.debug("Removing CUDA_VISIBLE_DEVICES env var.")
                         del os.environ["CUDA_VISIBLE_DEVICES"]
                  else:
                     logger.debug(f"Restoring CUDA_VISIBLE_DEVICES to '{original_cuda_visible}'")
                     os.environ["CUDA_VISIBLE_DEVICES"] = original_cuda_visible
