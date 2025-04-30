import logging
import os
import time
from pathlib import Path

from pydub import AudioSegment

# Try importing yt-dlp, handle if missing
try:
    import yt_dlp

    YTDLP_AVAILABLE = True
except ImportError:
    YTDLP_AVAILABLE = False

logger = logging.getLogger(__name__)


def concatenate_audio_files(file_paths: list[Path], output_path: Path, crossfade_ms: int = 20):
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
        output_path.parent.mkdir(parents=True, exist_ok=True)  # Ensure output dir exists
        combined.export(str(output_path), format="wav")
        logger.info(f"✅ Concatenation complete: {output_path}")
        return True

    except FileNotFoundError:
        logger.error(f"Concatenation failed: Initial file {file_paths[0]} not found.")
        return False
    except Exception:
        logger.exception(f"An unexpected error occurred during audio concatenation for {output_path}")
        return False


def cleanup_files(file_paths: list[Path]):
    """Deletes a list of files, logging errors."""
    logger.info(f"Cleaning up {len(file_paths)} temporary chunk files...")
    for file_path in file_paths:
        try:
            os.remove(file_path)
            logger.debug(f"Deleted {file_path.name}")
        except OSError as e:
            logger.error(f"Error deleting temporary file {file_path}: {e}")
    logger.info("Cleanup finished.")


def download_audio_from_youtube(
    youtube_id: str,
    output_dir: Path = Path("output-youtube"),
    force_download: bool = False,
) -> Path | None:
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

    expected_wav_path = output_dir / f"speaker-{safe_id}.wav"
    youtube_url = f"https://www.youtube.com/watch?v={safe_id}"  # Construct full URL

    # --- Caching Check ---
    if not force_download and expected_wav_path.exists():
        file_size = expected_wav_path.stat().st_size
        if file_size > 1000: # Basic integrity check (over 1KB)
            logger.info(f"📂 Cache HIT: Using existing file {expected_wav_path.name} ({file_size/1024:.1f}KB)")
            return expected_wav_path
        else:
            logger.warning(f"⚠️ Cache file exists but may be corrupt: {expected_wav_path} ({file_size} bytes). Re-downloading.")
    else:
        logger.info(f"📥 Cache MISS: Downloading {youtube_id} to {expected_wav_path.name}")

    # --- Download ---
    output_template = output_dir / f"speaker-{safe_id}.%(ext)s"
    logger.info(f"Attempting to download speaker audio for YouTube ID: {safe_id}...")
    logger.info(f"Target URL: {youtube_url}")
    logger.info(f"Output path template: {output_template}") # Log template used by ytdl

    ydl_opts = {
        "format": "bestaudio/best",
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "wav",
                "preferredquality": "192", # Added quality setting
            }
        ],
        "outtmpl": str(output_template),  # yt-dlp needs string path template
        "quiet": True,  # Suppress most console output from yt-dlp
        "noplaylist": True,  # Ensure only single video is downloaded
        "logger": logger,  # Integrate yt-dlp logging (might be verbose)
        "progress_hooks": [
            lambda d: print(f"\rDownloading: {d['_percent_str'] if d.get('_percent_str') else '...'} ", end="")
            if d["status"] == "downloading"
            else None
        ], # Basic progress
    }

    start_time = time.time()
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            logger.debug(f"Starting yt-dlp download for {safe_id}")
            error_code = ydl.download([youtube_url])
        download_time = time.time() - start_time
        print()  # Newline after progress

        if error_code != 0:
            logger.error(f"yt-dlp download failed with error code: {error_code} for ID {safe_id}")
            return None

        # Verify the expected output file exists *after* download
        if not expected_wav_path.exists():
             logger.error(f"Download process finished but expected WAV file not found: {expected_wav_path}")
             # Check if a file with a different extension exists due to postprocessor issue
             possible_other_exts = list(output_dir.glob(f"speaker-{safe_id}.*"))
             if possible_other_exts:
                 logger.warning(f"Found potential files with different extensions: {possible_other_exts}. Check yt-dlp/ffmpeg setup.")
             return None

        file_size = expected_wav_path.stat().st_size
        logger.info(f"✅ Downloaded {expected_wav_path.name} successfully ({file_size/1024:.1f}KB in {download_time:.1f}s)")
        return expected_wav_path
    except Exception:
        print()  # Ensure newline after potential progress output on error
        logger.exception(f"Failed to download/process YouTube audio for ID {safe_id}")
        # Clean up potentially incomplete file
        if expected_wav_path.exists():
            try:
                expected_wav_path.unlink(missing_ok=True) # Use missing_ok
                logger.info(f"Removed potentially incomplete download: {expected_wav_path.name}")
            except OSError:
                 logger.warning(f"Could not remove potentially incomplete file {expected_wav_path.name}")
        return None


# Future functions like trim_silence, normalize_audio can be added here
