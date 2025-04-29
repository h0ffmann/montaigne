import logging
from pathlib import Path
from typing import List
from pydub import AudioSegment
import os
from typing import Optional

# Try importing yt-dlp, handle if missing
try:
    import yt_dlp
    YTDLP_AVAILABLE = True
except ImportError:
    YTDLP_AVAILABLE = False

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


def download_audio_from_youtube(youtube_id: str, output_dir: Path = Path("output-youtube"), force_download: bool = False) -> Optional[Path]:
    """Downloads audio from a YouTube video ID as WAV, caches results."""
    if not YTDLP_AVAILABLE:
        logger.error("yt-dlp library not found. Cannot download from YouTube. Install it (`pip install yt-dlp`).")
        return None

    output_dir.mkdir(parents=True, exist_ok=True)
    # Use only the ID part for filename safety, handle URLs slightly more gracefully
    safe_id = youtube_id.split("v=")[-1].split("&")[0].strip()
    if not safe_id:
        logger.error(f"Could not extract a valid ID from '{youtube_id}'")
        return None

    output_template = output_dir / f"speaker-{safe_id}.%(ext)s"
    # Final expected path (yt-dlp replaces %(ext)s)
    expected_wav_path = output_dir / f"speaker-{safe_id}.wav"
    youtube_url = f"https://www.youtube.com/watch?v={safe_id}" # Construct full URL

    if not force_download and expected_wav_path.exists():
        logger.info(f"Using cached speaker audio: {expected_wav_path.name}")
        return expected_wav_path

    logger.info(f"Attempting to download speaker audio for YouTube ID: {safe_id}...")
    logger.info(f"Target URL: {youtube_url}")
    logger.info(f"Output path: {expected_wav_path}")

    ydl_opts = {
        'format': 'bestaudio/best',
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'wav',
        }],
        'outtmpl': str(output_template), # yt-dlp needs string path template
        'quiet': True, # Suppress console output from yt-dlp
        'noplaylist': True, # Ensure only single video is downloaded if ID is part of playlist
        'logger': logger, # Integrate yt-dlp logging
        'progress_hooks': [lambda d: print(f"   yt-dlp: {d.get('_percent_str', 'N/A')}", end='\r') if d['status'] == 'downloading' else None], # Basic progress
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            error_code = ydl.download([youtube_url])
            print() # Newline after progress
            if error_code != 0:
                logger.error(f"yt-dlp download failed with error code: {error_code} for ID {safe_id}")
                return None
        logger.info(f"✅ Successfully downloaded and converted speaker audio: {expected_wav_path.name}")
        return expected_wav_path
    except Exception as e:
        print() # Ensure newline after potential progress output on error
        logger.exception(f"Failed to download/process YouTube audio for ID {safe_id}")
        # Clean up potentially incomplete file
        if expected_wav_path.exists():
            try: expected_wav_path.unlink()
            except OSError: pass
        return None

# Future functions like trim_silence, normalize_audio can be added here