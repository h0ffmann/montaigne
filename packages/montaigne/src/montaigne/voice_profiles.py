"""
Module for managing voice profiles in Montaigne TTS.

This module handles:
1. Loading profiles from TOML configuration
2. Lazy loading of voice data (only download when requested)
3. Parallel downloading of files using asyncio
4. Preprocessing of voice samples for quality improvement
5. Two modes of operation: simple and deep cloning
"""

import asyncio
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

import numpy as np
import shutil
import tempfile
import tomli

# For audio preprocessing
try:
    import librosa
    import noisereduce as nr
    import soundfile as sf
    import scipy.signal # For filters

    LIBROSA_AVAILABLE = True
except ImportError:
    LIBROSA_AVAILABLE = False
    nr = None  # type: ignore
    sf = None  # type: ignore
    librosa = None  # type: ignore
    scipy = None # type: ignore

# Attempt Spleeter import
try:
    from spleeter.separator import Separator
    SPLEETER_AVAILABLE = True
except ImportError:
    Separator = None # type: ignore
    SPLEETER_AVAILABLE = False


# Import the audio_utils for YouTube download functionality
from .audio_utils import download_audio_from_youtube

logger = logging.getLogger(__name__)

# Default location for profiles.toml file
# Assumes profiles.toml is in the same directory as this file
PROFILES_TOML_PATH = Path(__file__).parent / "profiles.toml"


@dataclass
class VoiceProfileConfig:
    """Configuration for a voice profile."""

    name: str
    language: str
    description: str
    youtube_ids: List[str]  # Changed from youtube_id to youtube_ids
    gender: str
    tags: List[str]
    preprocessing: Optional[Dict[str, bool]] = None


@dataclass
class EngineParams:
    """Parameters for the TTS engine."""

    num_gpt_outputs: int = 16
    gpt_cond_len: int = 6
    gpt_cond_chunk_len: int = 3
    max_ref_len: int = 10
    sound_norm_refs: bool = True


class VoiceProfileManager:
    """Manager for voice profiles."""

    def __init__(self, profiles_path: Union[str, Path] = PROFILES_TOML_PATH):
        """Initialize the voice profile manager.

        Args:
            profiles_path: Path to the profiles.toml file
        """
        self.profiles_path = Path(profiles_path)
        self.profiles: Dict[str, VoiceProfileConfig] = {}
        self.config: Dict[str, Any] = {}
        self.engines: Dict[str, Dict[str, Any]] = {}
        self.modes: Dict[str, Dict[str, Any]] = {}
        self._load_profiles()

        # Log library availability
        if not LIBROSA_AVAILABLE:
            logger.warning("Librosa/Soundfile/Noisereduce not available. Audio preprocessing will be limited.")
        if not SPLEETER_AVAILABLE:
            logger.warning("Spleeter not available. Voice isolation will be skipped.")

    def _load_profiles(self):
        """Load profiles from TOML file."""
        if not self.profiles_path.exists():
            logger.warning(f"Profiles file not found at {self.profiles_path}")
            return

        try:
            with open(self.profiles_path, "rb") as f:
                data = tomli.load(f)

            # Extract configuration
            self.config = data.get("config", {})
            self.engines = data.get("engines", {})
            self.modes = data.get("modes", {})

            # Create profile objects
            for profile_id, profile_data in data.get("profiles", {}).items():
                self.profiles[profile_id] = VoiceProfileConfig(
                    name=profile_data.get("name", profile_id),
                    language=profile_data.get("language", "en"),
                    description=profile_data.get("description", ""),
                    youtube_ids=profile_data.get("youtube_ids", []),  # Changed to youtube_ids
                    gender=profile_data.get("gender", "unknown"),
                    tags=profile_data.get("tags", []),
                    preprocessing=profile_data.get("preprocessing"),
                )

            logger.info(f"Loaded {len(self.profiles)} voice profiles from {self.profiles_path}")
        except Exception as e:
            logger.error(f"Error loading profiles from {self.profiles_path}: {e}")

    def get_profile_ids(self) -> List[str]:
        """Get list of available profile IDs."""
        return list(self.profiles.keys())

    def get_profile_by_id(self, profile_id: str) -> Optional[VoiceProfileConfig]:
        """Get profile configuration by ID."""
        return self.profiles.get(profile_id)

    def get_download_dir(self) -> Path:
        """Get the download directory for voice profiles."""
        download_dir = self.config.get("download_dir", "voices")
        download_dir = Path(self._expand_vars(download_dir))
        download_dir.mkdir(parents=True, exist_ok=True) # Ensure exists
        return download_dir

    def get_cache_dir(self) -> Path:
        """Get the cache directory for voice profiles."""
        cache_dir = self.config.get("cache_dir", "${HOME}/.cache/montaigne/voices")
        cache_dir = Path(self._expand_vars(cache_dir))
        cache_dir.mkdir(parents=True, exist_ok=True) # Ensure exists
        return cache_dir

    def get_preprocessed_dir(self) -> Path:
        """Get the directory for preprocessed voice samples."""
        prep_dir = self.config.get("preprocessed_dir", "${HOME}/.cache/montaigne/preprocessed")
        prep_dir = Path(self._expand_vars(prep_dir))
        prep_dir.mkdir(parents=True, exist_ok=True) # Ensure exists
        return prep_dir

    def _expand_vars(self, path_str: str) -> str:
        """Expand environment variables in a path string."""
        return os.path.expandvars(path_str)

    def get_engine_params(self, engine: str = "xtts", mode: Optional[str] = None) -> Dict[str, Any]:
        """Get engine parameters based on engine type and mode.

        Args:
            engine: The TTS engine (e.g., "xtts", "bark")
            mode: The voice mode ("simple" or "deep"), or None for default

        Returns:
            Dictionary with engine parameters
        """
        if mode is None:
            mode = self.config.get("default_mode", "simple")

        # Start with default engine parameters
        engine_config = self.engines.get(engine, {})

        # Override with mode-specific parameters if available
        mode_config = self.modes.get(mode, {})

        # Combine and create EngineParams dictionary
        params = {
            "num_gpt_outputs": mode_config.get("num_gpt_outputs", engine_config.get("num_gpt_outputs", 16)),
            "gpt_cond_len": mode_config.get("gpt_cond_len", engine_config.get("gpt_cond_len", 6)),
            "gpt_cond_chunk_len": mode_config.get("gpt_cond_chunk_len", engine_config.get("gpt_cond_chunk_len", 3)),
            "max_ref_len": mode_config.get("max_ref_len", engine_config.get("max_ref_len", 10)),
            "sound_norm_refs": mode_config.get("sound_norm_refs", engine_config.get("sound_norm_refs", True)),
        }

        return params

    async def get_voice_paths_async(self, profile_id: str, preprocess: bool = True) -> List[Path]:
        """
        Get paths to voice profile WAV files, downloading and preprocessing if needed.

        Downloads audio for multiple YouTube IDs specified in the profile.

        Args:
            profile_id: The profile ID to retrieve.
            preprocess: Whether to preprocess the voice samples for quality improvement.

        Returns:
            List of Paths to the voice profile WAV files, or an empty list if none could be processed.
        """
        profile = self.get_profile_by_id(profile_id)
        if not profile:
            logger.error(f"Voice profile not found: {profile_id}")
            return []
        if not profile.youtube_ids:
            logger.error(f"No YouTube IDs defined for profile '{profile_id}'")
            return []

        download_dir = self.get_download_dir()
        preprocessed_dir = self.get_preprocessed_dir()
        force_redownload = self.config.get("force_redownload", False)
        max_videos = self.config.get("max_videos_per_profile", 5)
        youtube_ids_to_process = profile.youtube_ids[:max_videos]

        logger.info(
            f"Processing up to {len(youtube_ids_to_process)} voice samples for profile '{profile_id}' "
            f"(Max allowed: {max_videos}). Preprocessing: {preprocess}"
        )

        # Track processed IDs to avoid duplicates within a single call
        processed_ids = set()
        tasks = []

        for i, youtube_id in enumerate(youtube_ids_to_process):
            if youtube_id in processed_ids:
                logger.info(f"Skipping duplicate YouTube ID within this request: {youtube_id}")
                continue
            processed_ids.add(youtube_id)

            # Define paths for this specific sample
            sample_suffix = f"{profile_id}_{i}" # Unique suffix for each sample
            raw_path = download_dir / f"{sample_suffix}.wav"
            prep_path = preprocessed_dir / f"{sample_suffix}.wav"

            # Create task for processing this sample
            tasks.append(
                self._process_single_sample(
                    youtube_id=youtube_id,
                    raw_path=raw_path,
                    preprocessed_path=prep_path,
                    profile=profile, # Pass the full profile for config access
                    preprocess=preprocess,
                    force_redownload=force_redownload,
                )
            )

        # Run all download/preprocessing tasks concurrently
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Filter out None results (failures) and exceptions
        successful_paths: List[Path] = []
        for i, result in enumerate(results):
            if isinstance(result, Path):
                successful_paths.append(result)
            elif isinstance(result, Exception):
                # Log exception from gather results
                yt_id = youtube_ids_to_process[i] # Get corresponding ID
                logger.error(
                    f"Error processing sample {i} (YouTube ID: {yt_id}) "
                    f"for profile '{profile_id}': {result}",
                    exc_info=False, # Don't log full trace for gather errors unless needed
                )
            # else: result is None (logged within _process_single_sample)

        if not successful_paths:
            logger.error(f"Failed to process any voice samples for profile '{profile_id}'.")
        else:
            logger.info(f"Successfully processed {len(successful_paths)} voice samples for profile '{profile_id}'.")

        return successful_paths


    async def _process_single_sample(
        self,
        youtube_id: str,
        raw_path: Path,
        preprocessed_path: Path,
        profile: VoiceProfileConfig, # Receive full profile
        preprocess: bool,
        force_redownload: bool,
    ) -> Optional[Path]:
        """Handles download, preprocessing, and voice isolation for a single YouTube ID."""
        try:
            # 1. Check for existing preprocessed file first (if preprocessing is enabled)
            if preprocess and preprocessed_path.exists() and not force_redownload:
                logger.info(f"Using existing preprocessed sample: {preprocessed_path.name}")
                return preprocessed_path

            # 2. Check for existing raw file or download
            if not raw_path.exists() or force_redownload:
                logger.info(f"Downloading sample for YouTube ID: {youtube_id} -> {raw_path.name}")
                downloaded_path = await self._download_youtube_async(youtube_id, raw_path.parent, force_redownload)
                if not downloaded_path:
                    logger.error(f"Failed to download audio for {youtube_id}")
                    return None

                # Rename downloaded file (e.g., speaker-<id>.wav) to our target raw_path name
                expected_download_name = f"speaker-{youtube_id}.wav"
                if downloaded_path.name == expected_download_name and downloaded_path != raw_path:
                     # Rename only if names differ but ID matches
                    try:
                        if raw_path.exists(): raw_path.unlink(missing_ok=True) # Avoid error if exists
                        shutil.move(str(downloaded_path), str(raw_path)) # Use shutil.move for robustness
                        logger.info(f"Downloaded and moved to {raw_path.name}")
                    except Exception as e:
                        logger.error(f"Error moving {downloaded_path} to {raw_path}: {e}. Using original download path.")
                        raw_path = downloaded_path # Fallback to using the originally downloaded path
                elif downloaded_path == raw_path:
                     logger.info(f"Download resulted directly in target path: {raw_path.name}")
                else:
                    # This case might happen if download_audio_from_youtube has complex caching/naming
                    logger.warning(f"Downloaded path '{downloaded_path}' differs significantly from expected raw path '{raw_path}'. Using downloaded path.")
                    raw_path = downloaded_path # Use the path returned by download function
            else:
                logger.info(f"Using existing raw sample: {raw_path.name}")

            # --- Start Processing ---
            current_input_path = raw_path
            processing_step_succeeded = True # Track if any step fails

            # Get effective preprocessing config
            profile_preprocessing_config = profile.preprocessing if profile.preprocessing is not None else {}
            default_preprocessing = {
                "noise_reduction": True, "normalize": True, "trim_silence": True,
                "highpass_filter": True, "lowpass_filter": True, "enhance_vocals": True,
                "compression": True, "isolate_voice": True, # Add new defaults
            }
            final_prep_config = {**default_preprocessing, **profile_preprocessing_config}

            # 3. Isolate main voice if requested and possible
            isolated_path = None
            if preprocess and final_prep_config.get("isolate_voice", True) and SPLEETER_AVAILABLE:
                isolated_dir = self.get_cache_dir() / "isolated"
                isolated_dir.mkdir(parents=True, exist_ok=True)
                isolated_path = isolated_dir / f"{raw_path.stem}_isolated.wav"

                if not isolated_path.exists() or force_redownload:
                    logger.info(f"Isolating main voice from {current_input_path.name}...")
                    # Run blocking spleeter call in executor
                    loop = asyncio.get_event_loop()
                    with ThreadPoolExecutor() as pool:
                         success = await loop.run_in_executor(
                             pool, self._isolate_main_voice, current_input_path, isolated_path
                         )
                    if success:
                        logger.info(f"Voice isolation successful: {isolated_path.name}")
                        current_input_path = isolated_path # Use isolated audio for next steps
                    else:
                        logger.warning(f"Voice isolation failed for {raw_path.name}, using original audio for further processing.")
                        isolated_path = None # Ensure isolated_path is None if failed
                        # Don't set processing_step_succeeded = False, just use original audio
                else:
                    logger.info(f"Using existing isolated voice: {isolated_path.name}")
                    current_input_path = isolated_path
            elif preprocess and final_prep_config.get("isolate_voice", True) and not SPLEETER_AVAILABLE:
                 logger.warning("Voice isolation requested but Spleeter is not available. Skipping.")


            # 4. Preprocess audio if requested and possible
            if preprocess and LIBROSA_AVAILABLE:
                 # Preprocessing should happen *after* isolation if isolation was done
                 # The output of preprocessing is always the final preprocessed_path
                 if not preprocessed_path.exists() or force_redownload or current_input_path == isolated_path: # Reprocess if isolated or forced
                    logger.info(f"Preprocessing audio: {current_input_path.name} -> {preprocessed_path.name}")
                    # Run blocking librosa call in executor
                    loop = asyncio.get_event_loop()
                    with ThreadPoolExecutor() as pool:
                        success = await loop.run_in_executor(
                             pool, self._preprocess_audio, current_input_path, preprocessed_path, final_prep_config
                        )
                    if success:
                        logger.info(f"Successfully preprocessed: {preprocessed_path.name}")
                        return preprocessed_path # Return the final preprocessed path
                    else:
                        logger.warning(f"Preprocessing failed for {current_input_path.name}. Returning unprocessed (but possibly isolated) audio.")
                        processing_step_succeeded = False
                        # Fall through to return current_input_path (which might be raw or isolated)
                 else:
                      # This case should have been caught by the check at the start, but included for safety
                      logger.info(f"Using existing preprocessed file (logic safeguard): {preprocessed_path.name}")
                      return preprocessed_path

            elif preprocess and not LIBROSA_AVAILABLE:
                 logger.warning(f"Librosa/Soundfile/Noisereduce not available. Skipping preprocessing for {raw_path.name}.")
                 # Return the current input path (raw or isolated)
                 return current_input_path

            # If preprocessing was skipped or failed, return the current input path
            if not preprocess:
                 logger.info(f"Preprocessing skipped for {raw_path.name}. Returning current input path.")
            return current_input_path # This will be raw_path or isolated_path

        except Exception as e:
            logger.error(f"Error processing sample {youtube_id}: {e}", exc_info=True)
            return None


    async def _download_youtube_async(self, youtube_id: str, output_dir: Path, force_download: bool) -> Optional[Path]:
        """Download audio from YouTube asynchronously."""

        This uses the existing download_audio_from_youtube function but wraps it
        to be callable asynchronously.
        """
        loop = asyncio.get_event_loop()
        with ThreadPoolExecutor() as pool:
            # Pass force_download=False to use caching within download_audio_from_youtube
            return await loop.run_in_executor(
                pool, download_audio_from_youtube, youtube_id, output_dir, False
            )

    def _preprocess_audio(self, input_path: Path, output_path: Path, config: Dict[str, bool]) -> None:
        """Preprocess audio file for better quality.

        Args:
            input_path: Path to input audio file
            output_path: Path to output audio file
            config: Dictionary of preprocessing options
        """
        if not LIBROSA_AVAILABLE or not scipy: # Check scipy too
            logger.warning("Librosa/Soundfile/Noisereduce/Scipy not available. Skipping preprocessing.")
            return False

        try:
            # Load audio
            logger.debug(f"Loading audio for preprocessing: {input_path}")
            y, sr = librosa.load(str(input_path), sr=None) # Use original sample rate
            output_path.parent.mkdir(parents=True, exist_ok=True) # Ensure output dir

            y_processed = y.copy() # Work on a copy
            original_duration = librosa.get_duration(y=y, sr=sr)
            logger.debug(f"Original audio duration: {original_duration:.2f}s, Sample rate: {sr}Hz")

            # --- Preprocessing Steps ---
            noise_sample = None # Define noise_sample before potential use

            # 1. Trim silence
            if config.get('trim_silence', True):
                logger.debug("Trimming silence...")
                y_trimmed, index = librosa.effects.trim(y_processed, top_db=30)
                if len(y_trimmed) > 0: y_processed = y_trimmed
                else: logger.warning("Trim silence resulted in empty audio. Skipping trim.")

            # 2. Noise reduction
            if config.get('noise_reduction', True) and nr:
                logger.debug("Applying noise reduction...")
                noise_sample_length = min(int(sr * 0.5), int(len(y_processed) * 0.1))
                if noise_sample_length > 0:
                    noise_sample = y_processed[:noise_sample_length]
                    try:
                        y_processed = nr.reduce_noise(
                            y=y_processed, sr=sr, y_noise=noise_sample,
                            stationary=False, prop_decrease=0.8
                        )
                    except Exception as nr_err:
                         logger.warning(f"Noisereduce failed: {nr_err}. Skipping noise reduction.")
                else:
                     logger.warning("Audio too short for noise sample estimation. Skipping noise reduction.")

            # 3. Normalization (Initial)
            if config.get('normalize', True):
                logger.debug("Applying initial normalization...")
                y_processed = librosa.util.normalize(y_processed)

            # 4. High-pass filter
            if config.get('highpass_filter', True):
                logger.debug("Applying high-pass filter (80Hz)...")
                try:
                    b, a = scipy.signal.butter(5, 80/(sr/2), 'highpass')
                    y_processed = scipy.signal.filtfilt(b, a, y_processed)
                except Exception as hp_err:
                     logger.warning(f"High-pass filter failed: {hp_err}. Skipping.")

            # 5. Low-pass filter
            if config.get('lowpass_filter', True):
                logger.debug("Applying low-pass filter (12kHz)...")
                try:
                    b, a = scipy.signal.butter(5, 12000/(sr/2), 'lowpass')
                    y_processed = scipy.signal.filtfilt(b, a, y_processed)
                except Exception as lp_err:
                     logger.warning(f"Low-pass filter failed: {lp_err}. Skipping.")

            # 6. Vocal enhancement
            if config.get('enhance_vocals', True):
                logger.debug("Enhancing vocal frequencies (2-4kHz)...")
                try:
                    D = librosa.stft(y_processed)
                    freqs = librosa.fft_frequencies(sr=sr)
                    vocal_range = (freqs >= 2000) & (freqs <= 4000)
                    D[vocal_range, :] *= 1.5 # Apply boost (adjust factor as needed)
                    y_processed = librosa.istft(D, length=len(y_processed))
                except Exception as ve_err:
                     logger.warning(f"Vocal enhancement failed: {ve_err}. Skipping.")

            # 7. Compression
            if config.get('compression', True):
                logger.debug("Applying simple compression...")
                try:
                    threshold = 0.5 # Example threshold (adjust based on audio levels)
                    ratio = 4.0     # Example ratio
                    y_abs = np.abs(y_processed)
                    mask = y_abs > threshold
                    if np.any(mask): # Apply only if some values exceed threshold
                        y_processed[mask] = np.sign(y_processed[mask]) * (
                            threshold + (y_abs[mask] - threshold) / ratio
                        )
                        # Normalize again after compression
                        y_processed = librosa.util.normalize(y_processed)
                    else:
                         logger.debug("No values above compression threshold. Skipping compression.")
                except Exception as comp_err:
                     logger.warning(f"Compression failed: {comp_err}. Skipping.")

            # --- Final Checks & Save ---
            # Calculate SNR
            snr = np.nan # Default to NaN
            if noise_sample is not None and len(noise_sample) > 0:
                try:
                    signal_power = np.mean(y_processed**2)
                    noise_power = np.mean(noise_sample**2)
                    snr = 10 * np.log10(signal_power / noise_power) if noise_power > 1e-10 else 100.0
                    logger.debug(f"Estimated SNR after processing: {snr:.2f} dB")
                except Exception as snr_err:
                    logger.warning(f"Could not calculate SNR: {snr_err}")
            else:
                 logger.debug("Skipping SNR calculation (no valid noise sample).")

            # Check minimum length
            min_len_sec = self.config.get("min_voice_length", 6.0)
            processed_duration = librosa.get_duration(y=y_processed, sr=sr)
            if processed_duration < min_len_sec:
                 logger.warning(f"Processed audio duration ({processed_duration:.2f}s) is less than minimum required ({min_len_sec}s). Skipping save for {output_path.name}.")
                 return False # Indicate failure due to length

            # Save processed audio
            logger.debug(f"Saving processed audio to {output_path}")
            sf.write(str(output_path), y_processed, sr)
            logger.info(f"Processed audio saved: {output_path.name} ({processed_duration:.2f}s, SNR: {snr:.2f}dB)")
            return True

        except Exception as e:
            logger.error(f"Error during audio preprocessing for {input_path.name}: {e}", exc_info=True)
            # Clean up potentially incomplete output file
            output_path.unlink(missing_ok=True)
            return False


    def _isolate_main_voice(self, input_path: Path, output_path: Path) -> bool:
        """Isolate the main voice using Spleeter. Returns True on success."""
        if not SPLEETER_AVAILABLE or Separator is None:
            logger.warning("Spleeter not available. Skipping voice isolation.")
            return False

        try:
            logger.info(f"Isolating main voice from {input_path.name} -> {output_path.name}")
            output_path.parent.mkdir(parents=True, exist_ok=True) # Ensure output dir

            # Use a temporary directory for Spleeter's output structure
            with tempfile.TemporaryDirectory() as temp_dir:
                temp_dir_path = Path(temp_dir)
                logger.debug(f"Using temporary directory for Spleeter: {temp_dir_path}")

                # Initialize the separator (2stems separates vocals from accompaniment)
                # Consider 'spleeter:4stems' or 'spleeter:5stems' for more control if needed
                separator = Separator('spleeter:2stems', multiprocess=False) # Disable multiprocess for stability in threads

                # Separate vocals from other sounds
                separator.separate_to_file(
                    str(input_path),
                    str(temp_dir_path),
                    filename_format='{instrument}.{codec}', # Ensure predictable output names
                    codec='wav'
                )

                # Spleeter creates a subdirectory named after the input file stem
                spleeter_output_dir = temp_dir_path / input_path.stem
                vocals_file = spleeter_output_dir / "vocals.wav"

                if not vocals_file.exists():
                    logger.error(f"Spleeter processing completed but vocals file not found at expected path: {vocals_file}")
                    # Log contents of temp dir for debugging
                    logger.debug(f"Contents of Spleeter temp dir ({spleeter_output_dir}): {list(spleeter_output_dir.glob('*')) if spleeter_output_dir.exists() else 'Dir not found'}")
                    return False

                # Copy the vocals file to the final output path
                shutil.copy2(str(vocals_file), str(output_path))
                logger.info(f"Main voice isolated and saved to {output_path.name}")
                return True

        except Exception as e:
            logger.error(f"Error during voice isolation for {input_path.name}: {e}", exc_info=True)
            return False


# Create a singleton instance
voice_profile_manager = VoiceProfileManager()


def get_voice_profile(profile_name: str, download_dir: Optional[str] = None) -> List[Path]:
    """Get paths to voice profile WAV files, downloading if needed.

    This is a synchronous wrapper around the async version.

    Args:
        profile_name: The profile ID to retrieve
        download_dir: Deprecated, use profiles.toml config instead. If provided,
                      it temporarily overrides the config for this call.

    Returns:
        List of Paths to the voice profile WAV files, or an empty list on failure.
    """
    # Create a new event loop for async operations if one isn't running
    try:
        loop = asyncio.get_running_loop()
        logger.debug("Reusing existing asyncio loop for get_voice_profile.")
    except RuntimeError:
        logger.debug("Creating new asyncio loop for get_voice_profile.")
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        close_loop = True # Flag to close the loop we created
    else:
        close_loop = False

    original_dir = None
    try:
        # Override download directory if specified (temporary)
        if download_dir is not None:
            original_dir = voice_profile_manager.config.get("download_dir")
            logger.warning(f"Temporarily overriding download_dir to '{download_dir}' for profile '{profile_name}'")
            voice_profile_manager.config["download_dir"] = download_dir

        # Run the async function in the event loop
        # Use preprocess=True by default when called this way
        result = loop.run_until_complete(voice_profile_manager.get_voice_paths_async(profile_name, preprocess=True))

        # Restore original download directory if needed
        if original_dir is not None:
            voice_profile_manager.config["download_dir"] = original_dir

        return result
    finally:
        # Clean up the event loop only if we created it
        if close_loop:
            logger.debug("Closing asyncio loop created for get_voice_profile.")
            loop.close()


def list_voice_profiles() -> list[str]:
    """Return list of available voice profile names."""
    return voice_profile_manager.get_profile_ids()


def get_voice_profile_config(profile_name: str) -> Optional[Dict[str, Any]]:
    """Get configuration for a voice profile.

    Args:
        profile_name: The profile ID to retrieve

    Returns:
        Dictionary with profile configuration, or None if not found
    """
    profile = voice_profile_manager.get_profile_by_id(profile_name)
    if profile:
        # Convert dataclass to dict for external use if needed, or return directly
        # For now, returning specific fields as a dict
        return {
            "name": profile.name,
            "language": profile.language,
            "description": profile.description,
            "youtube_ids": profile.youtube_ids,
            "gender": profile.gender,
            "tags": profile.tags,
            "preprocessing_settings": profile.preprocessing # Expose preprocessing settings
        }
    return None


def get_engine_params(engine: str = "xtts", mode: Optional[str] = None) -> Dict[str, Any]:
    """Get engine parameters for the specified engine and mode.

    Args:
        engine: The TTS engine (e.g., "xtts", "bark")
        mode: The voice mode ("simple" or "deep"), or None for default

    Returns:
        Dictionary with engine parameters
    """
    # Directly call the manager method
    return voice_profile_manager.get_engine_params(engine, mode)
