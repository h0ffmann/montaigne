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
import requests
import tomli

# For audio preprocessing
try:
    import librosa
    import noisereduce as nr
    import soundfile as sf

    LIBROSA_AVAILABLE = True
except ImportError:
    LIBROSA_AVAILABLE = False
    nr = None  # type: ignore
    sf = None  # type: ignore
    librosa = None  # type: ignore


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
        self.engines: Dict[str, Any] = {}
        self.modes: Dict[str, Any] = {}
        self._load_profiles()

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
        return Path(self._expand_vars(download_dir))

    def get_cache_dir(self) -> Path:
        """Get the cache directory for voice profiles."""
        cache_dir = self.config.get("cache_dir", "${HOME}/.cache/montaigne/voices")
        return Path(self._expand_vars(cache_dir))

    def get_preprocessed_dir(self) -> Path:
        """Get the directory for preprocessed voice samples."""
        prep_dir = self.config.get("preprocessed_dir", "${HOME}/.cache/montaigne/preprocessed")
        return Path(self._expand_vars(prep_dir))

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

    async def get_voice_path_async(self, profile_id: str, preprocess: bool = True) -> Optional[Path]:
        """Get path to voice profile WAV file, downloading if needed (async version).

        Args:
            profile_id: The profile ID to retrieve
            preprocess: Whether to preprocess the voice sample for quality improvement

        Returns:
            Path to the voice profile WAV file, or None if not found
        """
        profile = self.get_profile_by_id(profile_id)
        if not profile:
            logger.error(f"Voice profile '{profile_id}' not found. Available profiles: {self.get_profile_ids()}")
            return None

        # Check if preprocessed version exists and should be used
        preprocessed_path = self.get_preprocessed_dir() / f"{profile_id}.wav"
        if preprocess and preprocessed_path.exists() and not self.config.get("force_redownload", False):
            logger.info(f"Using preprocessed voice profile for {profile_id} from {preprocessed_path}")
            return preprocessed_path

        # Check if raw download exists
        voice_path = self.get_download_dir() / f"{profile_id}.wav"
        force_redownload = self.config.get("force_redownload", False)

        if not voice_path.exists() or force_redownload:
            # Download the voice profile from YouTube
            if not profile.youtube_ids:
                logger.error(f"No YouTube IDs defined for profile '{profile_id}'")
                return None

            # For simplicity, we'll just use the first YouTube ID for now.
            # A more robust implementation would download and potentially combine audio from multiple IDs.
            youtube_id_to_download = profile.youtube_ids[0]
            logger.info(f"Downloading voice for profile '{profile_id}' using YouTube ID: {youtube_id_to_download}")

            try:
                # Ensure download directory exists
                voice_path.parent.mkdir(parents=True, exist_ok=True)

                # Use the YouTube download function
                downloaded_path = await self._download_youtube_async(youtube_id_to_download, voice_path.parent)
                if not downloaded_path:
                    logger.error(f"Failed to download voice profile {profile_id} from YouTube")
                    return None

                # Rename the downloaded file to match the profile ID
                # The download function creates a name like speaker-<youtube_id>.wav
                expected_download_name = f"speaker-{youtube_id_to_download}.wav"
                if downloaded_path.name == expected_download_name:
                    downloaded_path.rename(voice_path)
                    logger.info(f"Downloaded and renamed to {voice_path}")
                elif downloaded_path.name == voice_path.name:
                    # Already named correctly (e.g., if cached and renamed previously)
                    logger.info(f"Using existing downloaded file: {voice_path}")
                else:
                    logger.warning(
                        f"Downloaded file name '{downloaded_path.name}' doesn't match expected '{expected_download_name}' or '{voice_path.name}'. Using as is."
                    )
                    # If the name is unexpected, we might have an issue. For now, proceed but log.
                    # A better approach might be to force rename or handle errors.
                    # For now, assume it's okay or the download function returned the correct final path.
                    voice_path = downloaded_path # Use the path returned by download function

            except Exception as e:
                logger.error(f"Error downloading voice profile {profile_id}: {e}")
                return None
        else:
             logger.info(f"Using existing raw voice file for {profile_id} from {voice_path}")


        # Apply preprocessing if needed
        if preprocess and LIBROSA_AVAILABLE:
            logger.info(f"Preprocessing voice file for {profile_id}...")
            try:
                preprocessed_path.parent.mkdir(parents=True, exist_ok=True)

                # Get profile-specific preprocessing config or default to True for all steps if not specified
                preprocessing_config = profile.preprocessing if profile.preprocessing is not None else {}
                default_preprocessing = {
                    "noise_reduction": True,
                    "normalize": True,
                    "trim_silence": True,
                    "emphasize_bass": False, # Default off unless specified
                    "equalize": False # Default off unless specified
                }
                # Merge defaults with profile specifics
                final_prep_config = {**default_preprocessing, **preprocessing_config}


                # Do preprocessing
                self._preprocess_audio(voice_path, preprocessed_path, final_prep_config)

                return preprocessed_path
            except Exception as e:
                logger.warning(f"Error during preprocessing for {profile_id}, using original file: {e}", exc_info=True)
                return voice_path # Fallback to original if preprocessing fails
        elif preprocess and not LIBROSA_AVAILABLE:
             logger.warning("Librosa/Soundfile/Noisereduce not available. Skipping preprocessing.")
             return voice_path # Return original path if preprocessing requested but libs missing
        else:
            # Return original path if preprocessing not requested
            return voice_path

    async def _download_youtube_async(self, youtube_id: str, output_dir: Path) -> Optional[Path]:
        """Download audio from YouTube asynchronously.

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
        if not LIBROSA_AVAILABLE:
            # This check is redundant if called from get_voice_path_async, but safe to keep
            logger.warning("Librosa/Soundfile/Noisereduce not available, cannot preprocess.")
            raise RuntimeError("Audio preprocessing libraries not available.")

        # Load audio
        try:
            y, sr = librosa.load(str(input_path), sr=None) # Use str() for older librosa versions
            logger.info(f"Loaded audio {input_path.name} with sr={sr}, duration={len(y)/sr:.2f}s")
        except Exception as e:
            logger.error(f"Failed to load audio file {input_path}: {e}")
            raise

        y_processed = y.copy() # Work on a copy

        # Apply preprocessing steps
        noise_sample = y_processed[: int(sr * 0.5)] if len(y_processed) > sr * 0.5 else y_processed

        if config.get("noise_reduction", False):
            logger.debug("Applying noise reduction...")
            try:
                # Use noisereduce to remove background noise
                y_processed = nr.reduce_noise(y=y_processed, sr=sr, y_noise=noise_sample, prop_decrease=1.0, stationary=False)
                logger.debug("Noise reduction applied.")
            except Exception as e:
                 logger.warning(f"Noise reduction failed: {e}. Skipping.")


        if config.get("normalize", False):
            logger.debug("Applying normalization...")
            y_processed = librosa.util.normalize(y_processed)
            logger.debug("Normalization applied.")

        if config.get("trim_silence", False):
            logger.debug("Applying silence trimming...")
            y_trimmed, index = librosa.effects.trim(y_processed, top_db=30)
            if len(y_trimmed) > 0:
                 y_processed = y_trimmed
                 logger.debug(f"Silence trimmed. Original len: {len(y)}, Trimmed len: {len(y_processed)}")
            else:
                 logger.warning("Trim silence resulted in empty audio. Skipping trim.")


        if config.get("emphasize_bass", False):
            logger.debug("Applying bass emphasis...")
            try:
                # Boost lower frequencies for deeper voices
                # Simple low-pass filter effect approximation
                stft = librosa.stft(y_processed)
                freqs = librosa.fft_frequencies(sr=sr)
                # Define frequency range for bass boost (e.g., below 250 Hz)
                bass_range = freqs < 250
                # Apply boost (e.g., 1.5x magnitude)
                stft[bass_range, :] *= 1.5
                y_processed = librosa.istft(stft, length=len(y_processed))
                logger.debug("Bass emphasis applied.")
            except Exception as e:
                logger.warning(f"Bass emphasis failed: {e}. Skipping.")


        if config.get("equalize", False):
             logger.debug("Applying simple equalization...")
             try:
                # Simple equalization example (adjust frequencies as needed)
                stft = librosa.stft(y_processed)
                freqs = librosa.fft_frequencies(sr=sr)
                # Example: Reduce low rumble (< 60Hz), boost voice range (300Hz-3kHz)
                stft[freqs < 60, :] *= 0.5
                stft[(freqs > 300) & (freqs < 3000), :] *= 1.2
                y_processed = librosa.istft(stft, length=len(y_processed))
                logger.debug("Equalization applied.")
             except Exception as e:
                 logger.warning(f"Equalization failed: {e}. Skipping.")


        # Calculate SNR (Signal-to-Noise Ratio) - Use original noise sample
        try:
            signal_power = np.mean(y_processed**2)
            noise_power = np.mean(noise_sample**2)
            snr = 10 * np.log10(signal_power / noise_power) if noise_power > 1e-10 else 100.0 # Avoid log(0)
        except Exception as e:
            logger.warning(f"Could not calculate SNR: {e}")
            snr = np.nan # Indicate SNR calculation failed

        # Check if SNR is acceptable
        min_snr = self.config.get("min_snr", 15.0)
        if not np.isnan(snr) and snr < min_snr:
            logger.warning(f"Low SNR ({snr:.2f} dB) for {input_path.name} after processing, quality might be poor.")
        elif np.isnan(snr):
             logger.warning(f"SNR calculation failed for {input_path.name}.")

        # Save processed audio
        try:
            sf.write(str(output_path), y_processed, sr)
            logger.info(f"Preprocessed audio saved to {output_path} (SNR: {snr:.2f} dB)")
        except Exception as e:
            logger.error(f"Failed to write processed audio file {output_path}: {e}")
            raise


# Create a singleton instance
voice_profile_manager = VoiceProfileManager()


def get_voice_profile(profile_name: str, download_dir: Optional[str] = None) -> Optional[Path]:
    """Get path to voice profile WAV file, downloading if needed.

    This is a synchronous wrapper around the async version for backward compatibility.

    Args:
        profile_name: The profile ID to retrieve
        download_dir: Deprecated, use profiles.toml config instead. If provided,
                      it temporarily overrides the config for this call.

    Returns:
        Path to the voice profile WAV file, or None if not found
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
        result = loop.run_until_complete(voice_profile_manager.get_voice_path_async(profile_name, preprocess=True))

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
