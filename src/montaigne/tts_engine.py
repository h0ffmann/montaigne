import logging
import torch
from TTS.api import TTS
from pathlib import Path
import time
import warnings

logger = logging.getLogger(__name__)
XTTS_MODEL_NAME = "tts_models/multilingual/multi-dataset/xtts_v2"

class TTSEngine:
    def __init__(self, use_cuda: bool = True):
        self.device = "cuda" if use_cuda and torch.cuda.is_available() else "cpu"
        logger.info(f"Initializing TTS engine on device: {self.device}")
        if self.device == "cpu":
            logger.warning("CUDA not available/selected. TTS inference will be slow.")
        self.model = self._load_model()

    def _load_model(self):
        try:
            start_time = time.time()
            # Suppress specific UserWarnings if necessary during model loading
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                model = TTS(model_name=XTTS_MODEL_NAME, progress_bar=True).to(self.device)
            end_time = time.time()
            logger.info(f"TTS model '{XTTS_MODEL_NAME}' loaded in {end_time - start_time:.2f} seconds.")
            return model
        except Exception as e:
            logger.exception(f"Failed to load TTS model: {XTTS_MODEL_NAME}")
            raise RuntimeError(f"Could not initialize TTS model '{XTTS_MODEL_NAME}'. Check logs, dependencies, Python version compatibility with PyTorch/TTS.") from e

    def synthesize(self, text: str, speaker_wav: str, language: str, output_path: Path, speed: float = 1.0):
        if not Path(speaker_wav).is_file():
            logger.error(f"Speaker reference file not found: {speaker_wav}")
            raise FileNotFoundError(f"Speaker reference file not found: {speaker_wav}")

        logger.info(f"Synthesizing audio to: {output_path.name}")
        logger.info(f"Params: Lang={language}, Speed={speed}, Speaker={Path(speaker_wav).name}")
        logger.debug(f"Full Text Length: {len(text)} chars")

        try:
            start_time = time.time()
            self.model.tts_to_file(
                text=text, speaker_wav=str(speaker_wav), language=language,
                file_path=str(output_path), speed=speed, split_sentences=True
            )
            end_time = time.time()
            logger.info(f"Synthesis complete in {end_time - start_time:.2f} seconds.")
            print(f"✅ Audio successfully saved to: {output_path}")
            return True
        except Exception as e:
            logger.exception(f"TTS synthesis failed")
            print(f"❌ Error during TTS synthesis: {e}")
            if output_path.exists():
                try: output_path.unlink(missing_ok=True) # Py 3.8+
                except OSError: pass
            return False
