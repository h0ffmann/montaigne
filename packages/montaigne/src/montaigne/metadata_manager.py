"""
Metadata management module for Montaigne TTS.

Handles saving and loading synthesis metadata in TOML format.
"""

import logging
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np

try:
    import tomli
    import tomli_w

    TOMLI_AVAILABLE = True
except ImportError:
    TOMLI_AVAILABLE = False
    tomli = None  # type: ignore
    tomli_w = None  # type: ignore

logger = logging.getLogger(__name__)


class MetadataManager:
    """
    Manages synthesis metadata in TOML format.

    Provides methods to save and load synthesis parameters, metrics,
    and processing information to/from TOML files.
    """

    @staticmethod
    def create_metadata(
        engine: str,
        language: str,
        output_format: str,
        source_name: str,
        input_content: str,
        processed_chunks: int,
        voice_profile: str | None,
        actual_speaker_wav: Path | list[Path] | None,
        speaker_youtube_id: str | None,
        speaker_prompt: str | None,
        input_metrics: dict[str, Any],
        engine_params: dict[str, Any],
        cpu: bool,
        skip_preprocessors: bool,
        skip_voice_preprocessing: bool,
        skip_voice_isolation: bool,
        skip_audio_processing: bool,
        final_output_path: Path,
        synthesis_successful: bool,
        output_metrics: dict[str, float],
        processing_time: float,
    ) -> dict[str, Any]:
        """
        Create a comprehensive metadata dictionary for synthesis run.

        Args:
            All synthesis parameters and results

        Returns:
            Dictionary containing all metadata
        """
        metadata = {
            "general": {
                "engine": engine,
                "language": language,
                "output_format": output_format,
                "timestamp": datetime.now().isoformat(),
                "processing_time_sec": processing_time,
                "source_type": "voice_profile" if voice_profile else "file" if actual_speaker_wav else "text",
            },
            "input": {
                "text_source": source_name,
                "text_preview": input_content[:200],  # First 200 chars
                "processed_chunks": processed_chunks,
                "voice_profile": voice_profile,
                "speaker_file": str(actual_speaker_wav)
                if actual_speaker_wav and isinstance(actual_speaker_wav, Path)
                else None,
                "speaker_files": [str(p) for p in actual_speaker_wav] if isinstance(actual_speaker_wav, list) else None,
                "youtube_id": speaker_youtube_id,
                "speaker_prompt": speaker_prompt,
                "metrics": input_metrics,
            },
            "engine_params": engine_params,
            "flags": {
                "cpu_mode": cpu,
                "skip_preprocessors": skip_preprocessors,
                "skip_voice_preprocessing": skip_voice_preprocessing,
                "skip_voice_isolation": skip_voice_isolation,
                "skip_audio_processing": skip_audio_processing,
            },
            "output": {
                "file": str(final_output_path),
                "format": output_format,
                "synthesis_successful": synthesis_successful,
                "metrics": output_metrics,
            },
            "system_info": {
                "python_version": "3.11",  # Could be made dynamic
                "montaigne_version": "0.1.0",  # Should match package version
            },
        }

        return metadata

    @staticmethod
    def _clean_metadata_for_toml(data: Any) -> Any:
        """Recursively clean data structure for TOML serialization."""
        if isinstance(data, dict):
            cleaned_dict = {}
            for k, v in data.items():
                cleaned_dict[k] = MetadataManager._clean_metadata_for_toml(v)
            return cleaned_dict
        elif isinstance(data, list):
            return [MetadataManager._clean_metadata_for_toml(item) for item in data]
        elif isinstance(data, Path):
            return str(data) # Convert Path objects to strings
        elif isinstance(data, float):
            if data == float('inf'):
                return "Infinity"
            elif data == float('-inf'):
                return "-Infinity"
            elif np.isnan(data):
                return "NaN"
            return data
        elif data is None:
            return "N/A" # Replace None with "N/A" string
        # Add other type conversions if necessary (e.g., datetime to isoformat string)
        elif isinstance(data, datetime):
             return data.isoformat()
        # Ensure basic types are returned directly
        elif isinstance(data, str | int | bool):
             return data
        else:
             # Convert unknown types to string as a fallback
             return str(data)

    @staticmethod
    def save_metadata(metadata: dict[str, Any], output_path: Path) -> bool:
        """
        Save metadata to TOML file.

        Args:
            metadata: Dictionary containing metadata
            output_path: Path to save the TOML file

        Returns:
            True if successful, False otherwise
        """
        if not TOMLI_AVAILABLE:
            logger.warning("tomli_w not available. Cannot save metadata to TOML.")
            return False

        metadata_path = output_path.with_suffix(output_path.suffix + ".toml")
        try:
            # Clean metadata before saving
            cleaned_metadata = MetadataManager._clean_metadata_for_toml(metadata)

            with open(metadata_path, "wb") as f:
                tomli_w.dump(cleaned_metadata, f)
            logger.info(f"Metadata saved to: {metadata_path}") # Use standard logger
            return True
        except Exception as e:
            logger.error(f"Failed to save metadata: {e}")
            return False

    @staticmethod
    def load_metadata(metadata_path: Path) -> dict[str, Any] | None:
        """
        Load metadata from TOML file.

        Args:
            metadata_path: Path to the TOML file

        Returns:
            Dictionary containing metadata if successful, None otherwise
        """
        if not TOMLI_AVAILABLE:
            logger.warning("tomli not available. Cannot load metadata from TOML.")
            return None

        try:
            with open(metadata_path, "rb") as f:
                metadata = tomli.load(f)
            return metadata
        except Exception as e:
            logger.error(f"Failed to load metadata: {e}")
            return None

    @staticmethod
    def get_metadata_path(audio_path: Path) -> Path:
        """
        Get the metadata file path for a given audio file.

        Args:
            audio_path: Path to the audio file

        Returns:
            Path to the metadata TOML file
        """
        return audio_path.with_suffix(audio_path.suffix + ".toml")

    @staticmethod
    def validate_metadata(metadata: dict[str, Any]) -> bool:
        """
        Validate metadata structure.

        Args:
            metadata: Dictionary containing metadata

        Returns:
            True if valid, False otherwise
        """
        required_sections = ["general", "input", "engine_params", "flags", "output"]
        required_general_fields = ["engine", "language", "timestamp"]
        required_output_fields = ["file", "synthesis_successful"]

        # Check required sections
        for section in required_sections:
            if section not in metadata:
                logger.error(f"Missing required metadata section: {section}")
                return False

        # Check required general fields
        for field in required_general_fields:
            if field not in metadata["general"]:
                logger.error(f"Missing required field in general section: {field}")
                return False

        # Check required output fields
        for field in required_output_fields:
            if field not in metadata["output"]:
                logger.error(f"Missing required field in output section: {field}")
                return False

        return True

    @staticmethod
    def merge_metadata(old_metadata: dict[str, Any], new_metadata: dict[str, Any]) -> dict[str, Any]:
        """
        Merge two metadata dictionaries, keeping both versions.

        Useful for tracking multiple runs or updates to the same audio file.

        Args:
            old_metadata: Existing metadata
            new_metadata: New metadata to merge

        Returns:
            Merged metadata dictionary
        """
        merged = old_metadata.copy()

        # Create a history section if not exists
        if "history" not in merged:
            merged["history"] = []

        # Add the old metadata to history
        history_item = {
            "timestamp": old_metadata["general"].get("timestamp", "unknown"),
            "metadata": old_metadata.copy(),
        }
        merged["history"].append(history_item)

        # Update current metadata
        for key, value in new_metadata.items():
            if key != "history":
                merged[key] = value

        return merged

    @staticmethod
    def generate_summary(metadata: dict[str, Any]) -> str:
        """
        Generate a human-readable summary of the metadata.

        Args:
            metadata: Dictionary containing metadata

        Returns:
            Formatted string summary
        """
        if not MetadataManager.validate_metadata(metadata):
            return "Invalid metadata structure"

        summary = []

        # General info
        general = metadata["general"]
        summary.append("Synthesis Summary:")
        summary.append(f"  Engine: {general.get('engine', 'unknown')}")
        summary.append(f"  Language: {general.get('language', 'unknown')}")
        summary.append(f"  Timestamp: {general.get('timestamp', 'unknown')}")
        summary.append(f"  Processing Time: {general.get('processing_time_sec', 'N/A'):.1f}s")
        summary.append("")

        # Input info
        input_info = metadata["input"]
        summary.append("Input:")
        summary.append(f"  Source: {input_info.get('text_source', 'unknown')}")
        if input_info.get("voice_profile"):
            summary.append(f"  Voice Profile: {input_info['voice_profile']}")
        if input_info.get("speaker_file"):
            summary.append(f"  Speaker File: {Path(input_info['speaker_file']).name}")
        summary.append("")

        # Output info
        output_info = metadata["output"]
        summary.append("Output:")
        summary.append(f"  File: {Path(output_info.get('file', 'unknown')).name}")
        summary.append(f"  Format: {output_info.get('format', 'unknown')}")
        summary.append(f"  Success: {output_info.get('synthesis_successful', False)}")

        # Metrics if available
        if output_info.get("metrics"):
            metrics = output_info["metrics"]
            summary.append(f"  SNR: {metrics.get('snr_db', 'N/A'):.1f}dB")
            summary.append(f"  Duration: {metrics.get('duration_sec', 'N/A'):.1f}s")
            # Handle potential 'N/A' before formatting
            quality_score = metrics.get("voice_quality_score", "N/A")
            if isinstance(quality_score, int | float):
                summary.append(f"  Quality Score: {quality_score:.1f}/100")
            else:
                summary.append(f"  Quality Score: {quality_score}") # Display 'N/A' or other non-numeric value directly

        return "\n".join(summary)


# Convenience functions for backward compatibility
def save_synthesis_metadata(
    engine: str,
    language: str,
    output_format: str,
    source_name: str,
    input_content: str,
    processing_params: dict[str, Any],
    output_path: Path,
    output_metrics: dict[str, float],
    processing_time: float,
    synthesis_successful: bool,
) -> bool:
    """
    Save synthesis metadata to TOML file.
    Convenience wrapper for common use case.
    """
    metadata = MetadataManager.create_metadata(
        engine=engine,
        language=language,
        output_format=output_format,
        source_name=source_name,
        input_content=input_content,
        processed_chunks=processing_params.get("processed_chunks", 0),
        voice_profile=processing_params.get("voice_profile"),
        actual_speaker_wav=processing_params.get("actual_speaker_wav"),
        speaker_youtube_id=processing_params.get("speaker_youtube_id"),
        speaker_prompt=processing_params.get("speaker_prompt"),
        input_metrics=processing_params.get("input_metrics", {}),
        engine_params=processing_params.get("engine_params", {}),
        cpu=processing_params.get("cpu", False),
        skip_preprocessors=processing_params.get("skip_preprocessors", False),
        skip_voice_preprocessing=processing_params.get("skip_voice_preprocessing", False),
        skip_voice_isolation=processing_params.get("skip_voice_isolation", False),
        skip_audio_processing=processing_params.get("skip_audio_processing", False),
        final_output_path=output_path,
        synthesis_successful=synthesis_successful,
        output_metrics=output_metrics,
        processing_time=processing_time,
    )

    return MetadataManager.save_metadata(metadata, output_path)
