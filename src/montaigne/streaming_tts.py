import logging
import time
from pathlib import Path
import sys
import torch
from datetime import datetime
import numpy as np
from typing import Optional
import re # For sentence splitting in stream_speak
import uuid # For session IDs

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

    def _synthesize_chunk_to_temp(self, text: str) -> Optional[Path]:
        """Synthesizes a text chunk to a temporary WAV file and returns its path."""
        if not self.voice_model:
            logger.error("No voice model loaded.")
            return None

        logger.debug(f"Synthesizing chunk to temp: '{text[:50]}...'")
        start_time = time.time()
        temp_file_obj = None
        temp_path = None

        try:
            # Import necessary modules locally
            import wave
            import tempfile
            import os

            # Create a temporary WAV file that persists after closing
            temp_file_obj = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
            temp_path = Path(temp_file_obj.name)
            temp_file_obj.close() # Close the file handle immediately

            # Open the WAV file for writing using the wave module
            with wave.open(str(temp_path), 'wb') as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(self.sample_rate)
                # Synthesize directly to the WAV file object
                self.voice_model.synthesize(text, wav_file)

            synth_end_time = time.time()
            logger.debug(f"Chunk synthesized to {temp_path.name} in {synth_end_time - start_time:.2f}s")
            return temp_path

        except wave.Error as e:
             logger.error(f"Error configuring/writing temp WAV {temp_path.name if temp_path else 'N/A'}: {e}", exc_info=True)
             # Clean up if temp file was created
             if temp_path and temp_path.exists():
                 try: os.unlink(temp_path)
                 except OSError: pass
             return None
        except Exception as e:
            logger.exception(f"Error during chunk synthesis to temp file {temp_path.name if temp_path else 'N/A'}")
             # Clean up if temp file was created
            if temp_path and temp_path.exists():
                 try: os.unlink(temp_path)
                 except OSError: pass
            return None
        # Note: No finally block here to delete the file, caller (stream_speak) is responsible

    def stream_speak(self, text: str, session_id: uuid.UUID, output_dir: Path, prompt_count: int) -> bool:
        """
        Stream speech by breaking text into chunks, synthesizing each to a temp file,
        concatenating them, saving the final output, playing it, and cleaning up temps.
        """
        if not self.voice_model:
            logger.error("No voice model loaded. Call load_model() first.")
            return False
        if not sd:
            logger.error("Sounddevice not available. Cannot play audio.")
            return False

        logger.info(f"Starting stream_speak for prompt {prompt_count} (Session: {session_id})")
        logger.debug(f"Full text: '{text[:80]}...'")

        # Split text into chunks
        chunks = re.split(r'(?<=[.!?,\n])\s+', text)
        chunks = [chunk.strip() for chunk in chunks if chunk.strip()]

        if not chunks:
            logger.warning("Text splitting resulted in no chunks.")
            return True

        temp_chunk_files: list[Path] = []
        all_chunks_synthesized = True

        # Synthesize each chunk to a temporary file
        for i, chunk in enumerate(chunks):
            logger.info(f"Synthesizing chunk {i+1}/{len(chunks)} for prompt {prompt_count}...")
            temp_path = self._synthesize_chunk_to_temp(chunk)
            if temp_path and temp_path.exists():
                temp_chunk_files.append(temp_path)
            else:
                logger.error(f"Failed to synthesize chunk {i+1}. Aborting stream for this prompt.")
                all_chunks_synthesized = False
                break # Stop processing chunks for this prompt if one fails

        # Proceed only if all chunks were synthesized and we have temp files
        final_output_path = output_dir / f"live_{session_id}_{prompt_count}.wav"
        concatenation_successful = False
        playback_successful = False

        if all_chunks_synthesized and temp_chunk_files:
            logger.info(f"Concatenating {len(temp_chunk_files)} chunks into {final_output_path.name}...")
            # Import concatenation utils here
            from .audio_utils import concatenate_audio_files, cleanup_files
            import soundfile as sf # Needed for reading final file for playback

            concatenation_successful = concatenate_audio_files(temp_chunk_files, final_output_path)

            if concatenation_successful and final_output_path.exists():
                logger.info(f"Playing concatenated audio: {final_output_path.name}")
                try:
                    audio_data, read_sr = sf.read(str(final_output_path), dtype='float32')
                    if read_sr != self.sample_rate:
                         logger.warning(f"Sample rate mismatch! Model: {self.sample_rate}, Final file: {read_sr}. Using file rate.")
                         play_rate = read_sr
                    else:
                         play_rate = self.sample_rate
                    sd.play(audio_data, play_rate)
                    sd.wait()
                    playback_successful = True
                    logger.info("Playback finished.")
                except sf.SoundFileError as e:
                    logger.error(f"Error reading final audio file {final_output_path.name} for playback: {e}", exc_info=True)
                except Exception as e:
                    logger.exception(f"Error during playback of {final_output_path.name}")
            else:
                logger.error(f"Concatenation failed or final file missing: {final_output_path.name}")
        else:
             logger.error("Not all chunks were synthesized successfully, skipping concatenation and playback.")

        # Clean up temporary chunk files regardless of success/failure
        if temp_chunk_files:
            logger.info(f"Cleaning up {len(temp_chunk_files)} temporary chunk files...")
            from .audio_utils import cleanup_files # Re-import locally if needed
            cleanup_files(temp_chunk_files)

        logger.info(f"Finished stream_speak for prompt {prompt_count}.")
        # Return True if concatenation and playback were successful
        return concatenation_successful and playback_successful


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

def run_interactive_prompt(engine: PiperStreamingTTS, session_id: uuid.UUID, output_dir: Path):
    """Run an interactive prompt that converts text to speech using Piper and saves output."""

    print("🎙️ Montaigne Real-time TTS (Piper Engine - HF Download)")
    print(f"   Session ID: {session_id}")
    print(f"   Saving to: {output_dir}")
    if engine.voice_name:
        print(f"   Voice: {engine.voice_name}")
    else:
        print("   Voice: (Not loaded yet)")
    print("Type text and press Enter to hear it spoken and saved.")
    print("Type ':quit' to exit.")

    prompt_count = 0
    while True:
        try:
            text = input("> ")
            if not text.strip():
                continue
            if text.lower() == ':quit':
                break

            prompt_count += 1
            # Simple preprocessing for the REPL (can be expanded later)
            processed_text = text.strip() # Basic strip for now

            # Use stream_speak, passing session info for saving
            engine.stream_speak(processed_text, session_id, output_dir, prompt_count)

        except KeyboardInterrupt:
            print("\nExiting...")
            break
        except EOFError: # Handle Ctrl+D
            print("\nExiting...")
            break

    engine.stop() # Clean up sounddevice
