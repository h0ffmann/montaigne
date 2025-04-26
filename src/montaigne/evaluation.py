import logging
import whisper
import rapidfuzz
from pathlib import Path
import torch
import time
import warnings

logger = logging.getLogger(__name__)
WHISPER_MODEL_NAME = "base"

class AudioEvaluator:
    def __init__(self, use_cuda: bool = True):
        self.device = "cuda" if use_cuda and torch.cuda.is_available() else "cpu"
        logger.info(f"Initializing Whisper STT model ({WHISPER_MODEL_NAME}) on device: {self.device}")
        if self.device == "cpu":
             logger.warning("CUDA not available/selected. Whisper STT evaluation will run on CPU.")
        self.model = self._load_model()

    def _load_model(self):
        try:
            start_time = time.time()
            # Suppress potential UserWarnings from Whisper/PyTorch internals
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                model = whisper.load_model(WHISPER_MODEL_NAME, device=self.device)
            end_time = time.time()
            logger.info(f"Whisper model ({WHISPER_MODEL_NAME}) loaded in {end_time - start_time:.2f} seconds.")
            return model
        except Exception as e:
            logger.exception(f"Failed to load Whisper model: {WHISPER_MODEL_NAME}")
            raise RuntimeError(f"Could not initialize Whisper STT model '{WHISPER_MODEL_NAME}'. Check dependencies, model download path.") from e

    def evaluate_audio(self, audio_path: Path, target_text: str) -> tuple[float, str] | None:
        if not audio_path.is_file():
            logger.error(f"Evaluation failed: Audio file not found at {audio_path}")
            return None

        logger.info(f"Evaluating audio quality: Transcribing {audio_path.name}...")
        try:
            start_time = time.time()
            result = self.model.transcribe(str(audio_path), fp16=(self.device == 'cuda'))
            transcribed_text = result["text"]
            end_time = time.time()
            logger.info(f"Transcription finished in {end_time - start_time:.2f} seconds.")

            if not transcribed_text:
                 logger.warning("Whisper returned an empty transcription.")
                 return 0.0, ""

            norm_transcribed = transcribed_text.lower().strip()
            norm_target = target_text.lower().strip()
            similarity_score = rapidfuzz.fuzz.ratio(norm_target, norm_transcribed)
            logger.info(f"Evaluation Similarity Score: {similarity_score:.2f}%")

            return similarity_score, transcribed_text

        except Exception as e:
            logger.exception(f"Whisper transcription failed for {audio_path.name}")
            print(f"❌ Error during Whisper transcription: {e}")
            return None
