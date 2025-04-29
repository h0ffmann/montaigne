import logging
import time
from pathlib import Path
import sys
import torch
from datetime import datetime
import numpy as np
from typing import Optional

# Import sounddevice safely
try:
    import sounddevice as sd
    SOUNDDEVICE_AVAILABLE = True
except ImportError:
    print("⚠️ Sounddevice library not found. Audio playback will not work. (`pip install sounddevice`)", file=sys.stderr)
    sd = None # type: ignore
    SOUNDDEVICE_AVAILABLE = False

# Import Hugging Face Hub safely
try:
    from huggingface_hub import hf_hub_download
    HF_HUB_AVAILABLE = True
except ImportError:
    print("⚠️ huggingface-hub library not found. Model download will not work. (`pip install huggingface-hub`)", file=sys.stderr)
    hf_hub_download = None # type: ignore
    HF_HUB_AVAILABLE = False

# Import Piper safely (only needed within the class methods)
PIPER_AVAILABLE = True # Assume available initially, check during load
try:
    from piper import PiperVoice
except ImportError:
    PiperVoice = None # type: ignore
    PIPER_AVAILABLE = False


logger = logging.getLogger(__name__)

class PiperStreamingTTS:
    """Streaming TTS using Piper, downloading models from Hugging Face."""
    def __init__(self, use_cuda: bool = True):
        if not SOUNDDEVICE_AVAILABLE:
            raise RuntimeError("Sounddevice library is required for audio playback but not found.")
        if not HF_HUB_AVAILABLE:
            raise RuntimeError("huggingface-hub library is required for model download but not found.")

        self.device = "cuda" if use_cuda and torch.cuda.is_available() else "cpu"
        self.model_path: Optional[str] = None
        self.voice_model: Optional['PiperVoice'] = None # Use forward reference if PiperVoice is imported later
        self.sample_rate: int = 22050  # Default Piper sample rate, updated on load
        self.voice_name: Optional[str] = None
        self.use_cuda = use_cuda # Store cuda preference for model loading

        logger.info(f"--- Initializing Piper Streaming TTS ---")
        logger.info(f"Device preference: {self.device}")

    def load_model(self, voice_name: str = "en_US-amy-low") -> bool:
        """Load a Piper voice model from Hugging Face."""
        # Check PIPER_AVAILABLE which should be set at the module level
        if not PIPER_AVAILABLE:
            logger.error("piper-tts library is required but was not found during initial import. Install with `pip install piper-tts`")
            return False

        logger.info(f"Attempting to load Piper voice: {voice_name} (CUDA: {self.use_cuda})")
        # Basic structure assumption: lang/lang_REGION/speaker/quality/model.onnx
        # Example: en/en_US/amy/low/en_US-amy-low.onnx
        try:
            parts = voice_name.split('-')
            if len(parts) != 3:
                raise ValueError(f"Invalid voice name format: '{voice_name}'. Expected format like 'lang_REGION-speaker-quality'.")
            lang_region, speaker, quality = parts
            lang = lang_region.split('_')[0]

            repo_id = "rhasspy/piper-voices"
            base_path = f"{lang}/{lang_region}/{speaker}/{quality}"
            model_filename = f"{base_path}/{voice_name}.onnx"
            config_filename = f"{base_path}/{voice_name}.onnx.json"

            logger.info(f"Downloading model '{model_filename}' from '{repo_id}'...")
            model_path_hf = hf_hub_download(repo_id=repo_id, filename=model_filename)
            logger.info(f"Downloading config '{config_filename}' from '{repo_id}'...")
            config_path_hf = hf_hub_download(repo_id=repo_id, filename=config_filename)

            logger.info(f"Loading PiperVoice model...")
            # Import PiperVoice here, right before use, ensuring it's in scope
            # The global PIPER_AVAILABLE check at the start ensures this import should succeed
            from piper import PiperVoice

            # PiperVoice.load handles device selection internally based on onnxruntime providers
            # Pass use_cuda preference to it
            self.voice_model = PiperVoice.load(model_path_hf, config_path_hf, use_cuda=self.use_cuda)
            self.model_path = model_path_hf # Store path to downloaded model
            self.sample_rate = self.voice_model.config.sample_rate # Get actual sample rate
            self.voice_name = voice_name
            logger.info(f"Model loaded successfully: {self.voice_name} (Sample Rate: {self.sample_rate})")
            return True
        except FileNotFoundError as e:
             logger.error(f"Model or config file not found on Hugging Face Hub: {e}. Check voice name and repo structure.")
             return False
        except ValueError as e:
             logger.error(f"Error processing voice name: {e}")
             return False
        except Exception as e:
            logger.exception(f"Error loading model '{voice_name}'")
            # Check if it's an import error specifically
            if "piper" in str(e).lower() and not PIPER_AVAILABLE:
                 logger.error("Is the piper-tts library installed correctly?")
            return False

    def speak(self, text: str) -> bool:
        """Synthesizes text using the loaded Piper model and plays it using sounddevice."""
        if not self.voice_model:
            logger.error("No voice model loaded. Call load_model() first.")
            return False
        if not sd: # Should have been checked in __init__, but double-check
            logger.error("Sounddevice not available. Cannot play audio.")
            return False

        logger.debug(f"Synthesizing text with Piper ({self.voice_name}): '{text[:50]}...'")
        start_time = time.time()
        try:
            # Use the correct method: synthesize, which returns a list of int16 samples
            audio_int16_list = self.voice_model.synthesize(text)

            if not audio_int16_list:
                 logger.warning("Piper synthesis resulted in empty audio.")
                 return True # Not an error, just nothing to play

            # Convert the list of int16 samples to a NumPy array
            audio_array_int16 = np.array(audio_int16_list, dtype=np.int16)

            # Convert to float32 for sounddevice playback
            # Normalize int16 range [-32768, 32767] to float32 [-1.0, 1.0]
            audio_float32 = audio_array_int16.astype(np.float32) / 32768.0

            synth_end_time = time.time()
            logger.debug(f"Piper synthesis took {synth_end_time - start_time:.2f}s")

            # --- Playback ---
            logger.debug(f"Playing audio ({len(audio_float32)/self.sample_rate:.2f}s) via sounddevice...")
            sd.play(audio_float32, self.sample_rate)
            sd.wait() # Wait for playback to finish
            play_end_time = time.time()
            logger.debug(f"Playback finished (duration: {play_end_time - synth_end_time:.2f}s)")
            return True

        except Exception as e:
            logger.exception(f"Error during Piper synthesis or playback")
            print(f"❌ Error generating or playing speech: {e}", file=sys.stderr)
            return False

    def stop(self):
        """Stops any ongoing audio playback via sounddevice."""
        if sd:
            logger.info("Stopping sounddevice playback...")
            try:
                sd.stop()
            except Exception as e:
                logger.error(f"Error stopping sounddevice: {e}")
        logger.info("Piper streaming TTS stopped.")


# --- Interactive Prompt Functionality ---
# Needs to be adapted for the new PiperStreamingTTS class

def run_interactive_prompt(engine: PiperStreamingTTS, output_dir: Optional[Path] = None):
    """Run an interactive prompt that converts text to speech using Piper."""
    # Note: The new class doesn't support saving chunks directly.
    # This function could be adapted to save the *entire* synthesized audio if needed,
    # but the primary use case here is live playback.
    if output_dir:
        logger.warning("Saving audio chunks is not directly supported by PiperStreamingTTS in this implementation.")

    print("🎙️ Montaigne Real-time TTS (Piper Engine - HF Download)")
    if engine.voice_name:
        print(f"   Voice: {engine.voice_name}")
    else:
        print("   Voice: (Not loaded yet)")
    print("Type text and press Enter to hear it spoken.")
    print("Type ':quit' to exit.")

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
