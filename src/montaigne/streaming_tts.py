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
        """Synthesize and play speech using Piper TTS."""
        if not self.voice_model:
            logger.error("No voice model loaded. Call load_model() first.")
            return False
        if not sd: # Should have been checked in __init__, but double-check
            logger.error("Sounddevice not available. Cannot play audio.")
            return False

        logger.debug(f"Synthesizing text with Piper ({self.voice_name}): '{text[:50]}...'")
        start_time = time.time()
        temp_path = None # Initialize path for cleanup in finally block

        try:
            # Import necessary modules locally for this method's logic
            import wave
            import tempfile
            import soundfile as sf # Use soundfile for reading back
            import os

            # Create a temporary WAV file
            # Using delete=False and manual cleanup is safer across platforms
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
                temp_path = temp_file.name
            # temp_file is now closed, but the file persists at temp_path

            # Open the WAV file for writing using the wave module
            with wave.open(temp_path, 'wb') as wav_file:
                # Configure WAV parameters (16-bit mono at sample rate)
                wav_file.setnchannels(1)  # Mono
                wav_file.setsampwidth(2)  # 16-bit (2 bytes)
                wav_file.setframerate(self.sample_rate)  # Sample rate from model

                # Now synthesize directly to the WAV file object
                logger.info(f"Synthesizing text to temporary file: {temp_path}")
                self.voice_model.synthesize(text, wav_file)
                # wave file is automatically closed by 'with' statement

            synth_end_time = time.time()
            logger.debug(f"Piper synthesis to file took {synth_end_time - start_time:.2f}s")

            # Read back the audio data from the temporary file using soundfile
            logger.info(f"Reading audio from {temp_path} for playback...")
            # soundfile automatically detects sample rate, but good to verify
            audio_data, read_sr = sf.read(temp_path, dtype='float32') # Read as float32 for sounddevice
            if read_sr != self.sample_rate:
                 logger.warning(f"Sample rate mismatch! Model: {self.sample_rate}, Read file: {read_sr}. Using read rate.")
                 play_rate = read_sr
            else:
                 play_rate = self.sample_rate

            # Play audio using sounddevice
            logger.debug(f"Playing audio ({len(audio_data)/play_rate:.2f}s) via sounddevice...")
            sd.play(audio_data, play_rate)
            sd.wait() # Wait for playback to finish
            play_end_time = time.time()
            logger.debug(f"Playback finished (duration: {play_end_time - synth_end_time:.2f}s)")

            return True

        except wave.Error as e:
             logger.error(f"Error configuring or writing WAV file: {e}", exc_info=True)
             print(f"❌ Error handling WAV file: {e}", file=sys.stderr)
             return False
        except sf.SoundFileError as e:
             logger.error(f"Error reading back temporary WAV file: {e}", exc_info=True)
             print(f"❌ Error reading audio file: {e}", file=sys.stderr)
             return False
        except Exception as e:
            logger.exception(f"Error during Piper synthesis or playback")
            print(f"❌ Error generating or playing speech: {e}", file=sys.stderr)
            return False
        finally:
            # Clean up the temporary file
            if temp_path and os.path.exists(temp_path):
                try:
                    logger.debug(f"Cleaning up temporary file: {temp_path}")
                    os.unlink(temp_path)
                except OSError as e:
                    logger.error(f"Failed to delete temporary file {temp_path}: {e}")


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
