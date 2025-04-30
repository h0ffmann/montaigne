import abc
import logging
import os
import time
from pathlib import Path
from typing import List, Union # Add Union and List here

import torch

# Attempt to import necessary libraries, provide clear errors if missing
try:
    from TTS.api import TTS

    # Import XttsConfig directly for safe_globals
    from TTS.tts.configs.xtts_config import XttsConfig

    TTS_AVAILABLE = True
except ImportError:
    TTS = None  # type: ignore
    XttsConfig = None  # type: ignore
    TTS_AVAILABLE = False

try:
    # Use soundfile for saving Bark output reliably
    import soundfile as sf
    from bark import SAMPLE_RATE as BARK_SAMPLE_RATE
    from bark import generate_audio, preload_models
    from bark.generation import SUPPORTED_LANGS as BARK_SUPPORTED_LANGS

    SOUNDFILE_AVAILABLE = True
    BARK_AVAILABLE = True
except ImportError:
    BARK_SAMPLE_RATE = 24000  # Default Bark sample rate
    generate_audio = None  # type: ignore
    preload_models = None  # type: ignore
    BARK_SUPPORTED_LANGS = []
    sf = None  # type: ignore
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
                    logger.warning(
                        f"CUDA reported available, but driver check failed: {e}",
                        exc_info=False,
                    )
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
# --- XTTS Engine Implementation ---
class XTTSv2Engine(BaseTTSEngine):
    """TTS Engine using Coqui XTTSv2."""

    def __init__(self, use_cuda: bool = True):
        """Initialize the TTS engine."""
        super().__init__(use_cuda=use_cuda) # Call base class init
        self.model = self._load_model()

    def _load_model(self):
        """Load XTTS model."""
        if not TTS_AVAILABLE:
            logger.error("TTS library not available. Cannot load XTTS model.")
            return None

        logger.info(f"Loading TTS model '{XTTS_MODEL_NAME}' onto device: {self.device}")
        try:
            start_time = time.time()
            # TTS library handles safe loading internally now
            model = TTS(model_name=XTTS_MODEL_NAME, progress_bar=True).to(self.device)
            end_time = time.time()
            logger.info("✅ XTTSv2 model loaded successfully in %.2f seconds.", end_time - start_time)
            return model
        except Exception:
            logger.error("❌ Failed to load TTS model: %s", XTTS_MODEL_NAME, exc_info=True)
            hint = (
                "Check logs. Possible issues: network connection, disk space, model cache corruption (~/.local/share/tts/), "
                "missing dependencies, or license agreement (export COQUI_TOS_AGREED=1)."
            )
            logger.error("Hint: %s", hint)
            return None

    def synthesize(self, text: str, language: str, output_path: Path, **kwargs) -> bool:
        """Synthesizes using XTTSv2."""
        if not self.model:
            logger.error("XTTS model not loaded. Cannot synthesize.")
            return False

        # speaker_wav can now be a string path or a list of string paths
        speaker_wav_input = kwargs.get("speaker_wav")
        speed = kwargs.get("speed", 1.0)

        if not speaker_wav_input:
            logger.error("XTTSv2Engine requires 'speaker_wav' parameter (path or list of paths).")
            return False

        # Validate input speaker paths and prepare for logging/TTS call
        speaker_paths_str: Union[str, List[str]]
        speaker_display: str
        speaker_count = 0

        if isinstance(speaker_wav_input, list):
            valid_paths = []
            for p_str in speaker_wav_input:
                p = Path(p_str)
                if p.is_file():
                    valid_paths.append(str(p)) # Keep as string for TTS lib
                else:
                    # Log warning instead of error, proceed with valid files
                    logger.warning(f"Speaker reference file not found in list, skipping: {p_str}")
            if not valid_paths:
                 logger.error("No valid speaker reference files found in the provided list.")
                 return False
            speaker_paths_str = valid_paths
            speaker_count = len(valid_paths)
            # Log clearly how many speakers are being used
            speaker_display = f"{speaker_count} files: {[Path(p).name for p in valid_paths]}"
            logger.info(f"Using {speaker_count} speaker sample(s) for XTTS synthesis:")
            for i, path in enumerate(valid_paths, 1):
                 logger.info(f"  Speaker {i}: {Path(path).name}")

        elif isinstance(speaker_wav_input, str):
            p = Path(speaker_wav_input)
            if not p.is_file():
                logger.error(f"Speaker reference file not found: {speaker_wav_input}")
                # Raise error here as single file is critical if provided this way
                raise FileNotFoundError(f"Speaker reference file not found: {speaker_wav_input}")
            speaker_paths_str = str(p)
            speaker_display = p.name
            speaker_count = 1
            logger.info(f"Using 1 speaker sample for XTTS synthesis: {speaker_display}")
        else:
            logger.error(f"Invalid type for speaker_wav: {type(speaker_wav_input)}. Expected str or list.")
            return False

        # Ensure output directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)
        # Ensure output file does not exist before synthesis
        output_path.unlink(missing_ok=True)

        logger.info(f"Synthesizing audio to: {output_path.name} using XTTSv2")
        logger.info(f"Params: Lang={language}, Speed={speed}, Speaker(s)={speaker_display} ({speaker_count} total)")
        logger.debug(f"Full Text Length: {len(text)} chars")

        try:
            start_time = time.time()
            # Pass the validated speaker_paths_str (str or list[str]) directly
            self.model.tts_to_file(
                text=text,
                speaker_wav=speaker_paths_str,
                language=language,
                file_path=str(output_path),
                speed=speed,
                split_sentences=True, # Keep sentence splitting enabled
            )
            end_time = time.time()

            # Verify output file exists and has content
            if output_path.exists() and output_path.stat().st_size > 100: # Basic check > 100 bytes
                logger.info(f"XTTS Synthesis complete in {end_time - start_time:.2f} seconds.")
                print(f"✅ Audio successfully saved to: {output_path}")
                return True
            else:
                 logger.error(f"Synthesis process completed but output file is missing or empty: {output_path}")
                 return False
        except Exception as e:
            logger.exception("XTTS synthesis failed")
            print(f"❌ Error during XTTS synthesis: {e}")
            # Attempt cleanup of potentially partial file
            output_path.unlink(missing_ok=True)
            return False


# --- Bark Engine Implementation ---
class BarkEngine(BaseTTSEngine):
    """TTS Engine using Suno AI's Bark."""

    def __init__(self, use_cuda: bool = True):
        """Initialize the Bark engine."""
        super().__init__(use_cuda=use_cuda) # Call base class init
        # Load models during initialization and store success status
        self.model = self._load_model()

    def _load_model(self):
        """Load Bark models."""
        if not BARK_AVAILABLE:
            logger.error("Bark library not available. Cannot load Bark models.")
            return None

        logger.info(
            "Loading Bark models... (Device selection managed internally by Bark/PyTorch)"
        )
        original_cuda_visible = os.environ.get("CUDA_VISIBLE_DEVICES")
        try:
            # Force CPU if requested via device setting
            if self.device == "cpu":
                logger.info("Attempting to force Bark to use CPU by setting CUDA_VISIBLE_DEVICES=-1")
                os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

            start_time = time.time()
            if preload_models:
                preload_models() # Downloads and loads models as needed
            else:
                # This case should ideally not happen if BARK_AVAILABLE is True
                raise RuntimeError("Bark's preload_models function not available despite Bark being imported.")
            end_time = time.time()
            logger.info(f"Bark models preloaded in {end_time - start_time:.2f} seconds.")
            return True # Indicate loading successful

        except Exception as e:
            logger.exception("Failed to preload Bark models")
            hint = "Check logs, dependencies (bark, transformers, pytorch), network connection."
            # Raise a runtime error to signal failure clearly
            raise RuntimeError(f"Could not initialize Bark models. {hint}") from e
        finally:
            # Always restore env var if we changed it
            if self.device == "cpu":
                if original_cuda_visible is None:
                    # If it was originally unset, remove the var we added
                    if "CUDA_VISIBLE_DEVICES" in os.environ:
                         logger.debug("Removing CUDA_VISIBLE_DEVICES env var.")
                         del os.environ["CUDA_VISIBLE_DEVICES"]
                else:
                    # Otherwise, restore its original value
                    logger.debug(f"Restoring CUDA_VISIBLE_DEVICES to '{original_cuda_visible}'")
                    os.environ["CUDA_VISIBLE_DEVICES"] = original_cuda_visible


    def synthesize(self, text: str, language: str, output_path: Path, **kwargs) -> bool:
        """Synthesizes using Bark."""
        if not self.model: # Check if _load_model indicated success
            logger.error("Bark models not preloaded. Cannot synthesize.")
            return False
        if not generate_audio or not sf:
            logger.error("Bark generate_audio or soundfile function not available.")
            return False

        speaker_prompt = kwargs.get("speaker_prompt")
        logger.info(f"Synthesizing audio to: {output_path.name} using Bark")
        logger.info(f"Params: Lang={language}")

        # Determine history prompt based on language and speaker_prompt
        simple_lang_code = language.split("-")[0].lower()
        bark_lang_supported = simple_lang_code in BARK_SUPPORTED_LANGS

        history_prompt = speaker_prompt # Use user provided first
        if not history_prompt:
            if bark_lang_supported:
                history_prompt = f"{simple_lang_code}_speaker_0" # Default speaker 0 for the language
                logger.info(f"Using generic Bark history prompt: {history_prompt}")
            else:
                logger.warning(
                    f"Language '{language}' ({simple_lang_code}) not directly listed in Bark presets. "
                    "Bark may default to English or perform poorly. No history prompt used."
                )
                history_prompt = None # Explicitly set to None if not supported and not provided
        else:
             logger.info(f"Using provided speaker prompt: {history_prompt}")

        logger.debug(f"Full Text Length: {len(text)} chars")

        # Ensure output directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.unlink(missing_ok=True) # Ensure clean state

        original_cuda_visible = os.environ.get("CUDA_VISIBLE_DEVICES")
        try:
            # Temporarily set env var for CPU if needed for this specific call
            if self.device == "cpu" and original_cuda_visible != "-1":
                logger.debug("Temporarily setting CUDA_VISIBLE_DEVICES=-1 for Bark generate_audio")
                os.environ["CUDA_VISIBLE_DEVICES"] = "-1"

            start_time = time.time()
            # Generate audio data (NumPy array)
            audio_array = generate_audio(text, history_prompt=history_prompt)
            end_time = time.time()
            logger.info(f"Bark audio generation complete in {end_time - start_time:.2f} seconds.")

            # Save the audio array to a WAV file using soundfile
            logger.info(f"Saving Bark audio (sample rate: {BARK_SAMPLE_RATE}) to {output_path}...")
            sf.write(str(output_path), audio_array, BARK_SAMPLE_RATE)

            # Verify output
            if output_path.exists() and output_path.stat().st_size > 100:
                print(f"✅ Audio successfully saved to: {output_path}")
                return True
            else:
                 logger.error(f"Bark synthesis finished but output file is missing or empty: {output_path}")
                 return False
        except Exception as e:
            logger.exception("Bark synthesis failed")
            print(f"❌ Error during Bark synthesis: {e}")
            output_path.unlink(missing_ok=True) # Cleanup partial file on error
            return False
        finally:
            # Always restore CUDA_VISIBLE_DEVICES if we changed it
            if self.device == "cpu" and os.environ.get("CUDA_VISIBLE_DEVICES") == "-1":
                if original_cuda_visible is None:
                    if "CUDA_VISIBLE_DEVICES" in os.environ:
                        logger.debug("Removing CUDA_VISIBLE_DEVICES env var.")
                        del os.environ["CUDA_VISIBLE_DEVICES"]
                else:
                    logger.debug(f"Restoring CUDA_VISIBLE_DEVICES to '{original_cuda_visible}'")
                    os.environ["CUDA_VISIBLE_DEVICES"] = original_cuda_visible


# --- End of BarkEngine ---
