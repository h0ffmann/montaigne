import logging
from pathlib import Path
from typing import List
from pydub import AudioSegment
import os

logger = logging.getLogger(__name__)

def concatenate_audio_files(file_paths: List[Path], output_path: Path, crossfade_ms: int = 20):
    """Concatenates multiple WAV files into a single file using crossfade."""
    if not file_paths:
        logger.warning("No audio file paths provided for concatenation.")
        return False

    try:
        combined = AudioSegment.from_wav(str(file_paths[0]))
        logger.info(f"Starting concatenation with {file_paths[0].name}")

        for file_path in file_paths[1:]:
            try:
                next_segment = AudioSegment.from_wav(str(file_path))
                logger.debug(f"Adding {file_path.name} (duration: {len(next_segment)}ms)")
                # Use crossfade for smoother transitions
                combined = combined.append(next_segment, crossfade=crossfade_ms)
            except Exception as e:
                logger.error(f"Error processing segment {file_path.name}: {e}. Skipping this segment.")
                # Decide whether to skip or abort - skipping for now

        logger.info(f"Exporting combined audio (total duration: {len(combined)}ms) to {output_path}...")
        output_path.parent.mkdir(parents=True, exist_ok=True) # Ensure output dir exists
        combined.export(str(output_path), format="wav")
        logger.info(f"✅ Concatenation complete: {output_path}")
        return True

    except FileNotFoundError:
        logger.error(f"Concatenation failed: Initial file {file_paths[0]} not found.")
        return False
    except Exception as e:
        logger.exception(f"An unexpected error occurred during audio concatenation for {output_path}")
        return False

def cleanup_files(file_paths: List[Path]):
    """Deletes a list of files, logging errors."""
    logger.info(f"Cleaning up {len(file_paths)} temporary chunk files...")
    for file_path in file_paths:
        try:
            os.remove(file_path)
            logger.debug(f"Deleted {file_path.name}")
        except OSError as e:
            logger.error(f"Error deleting temporary file {file_path}: {e}")
    logger.info("Cleanup finished.")

# Future functions like trim_silence, normalize_audio can be added here
