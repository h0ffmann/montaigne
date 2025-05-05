#!/usr/bin/env python
"""
Utility to analyze Montaigne TTS synthesis metadata files.

Usage:
    python metadata_analyzer.py <metadata.toml>
    python metadata_analyzer.py --directory <dir>  # Analyze all metadata files in directory
"""

import argparse
import sys
from pathlib import Path
from typing import Any

try:
    import tomli

    TOMLI_AVAILABLE = True
except ImportError:
    TOMLI_AVAILABLE = False
    print("Error: tomli package not installed. Install with: pip install tomli")
    sys.exit(1)

from montaigne.metadata_manager import MetadataManager


class MetadataAnalyzer:
    """Analyzes synthesis metadata files."""

    @staticmethod
    def load_metadata(path: Path) -> dict[str, Any]:
        """Load metadata from TOML file."""
        try:
            with open(path, "rb") as f:
                return tomli.load(f)
        except Exception as e:
            print(f"Error loading {path}: {e}")
            return {}

    @staticmethod
    def analyze_single_file(path: Path) -> None:
        """Analyze a single metadata file."""
        print(f"\n{'=' * 60}")
        print(f"Analyzing: {path.name}")
        print("=" * 60)

        metadata = MetadataAnalyzer.load_metadata(path)
        if not metadata:
            return

        # Validate metadata
        if not MetadataManager.validate_metadata(metadata):
            print("⚠️ Invalid metadata structure")
            return

        # Display summary
        print(MetadataManager.generate_summary(metadata))

        # Additional detailed analysis
        print("\n📊 Detailed Analysis:")

        # Timing analysis
        if "general" in metadata and "processing_time_sec" in metadata["general"]:
            processing_time = metadata["general"]["processing_time_sec"]
            print(f"  Processing Time: {processing_time:.2f}s")

            # Estimate performance
            if processing_time < 1:
                print("  Performance: ⚡ Extremely Fast")
            elif processing_time < 5:
                print("  Performance: 🚀 Fast")
            elif processing_time < 10:
                print("  Performance: ✅ Normal")
            else:
                print("  Performance: 🐌 Slow")

        # Quality analysis
        if "output" in metadata and "metrics" in metadata["output"]:
            metrics = metadata["output"]["metrics"]

            # Voice quality score
            if "voice_quality_score" in metrics:
                score = metrics["voice_quality_score"]
                print(f"  Voice Quality: {score:.1f}/100")

                if score >= 90:
                    print("  Quality Rating: ⭐⭐⭐⭐⭐ Excellent")
                elif score >= 80:
                    print("  Quality Rating: ⭐⭐⭐⭐ Good")
                elif score >= 70:
                    print("  Quality Rating: ⭐⭐⭐ Acceptable")
                else:
                    print("  Quality Rating: ⭐⭐ Poor")

            # Audio characteristics
            if "duration_sec" in metrics:
                duration = metrics["duration_sec"]
                print(f"  Audio Length: {duration:.1f}s")

                if duration < 1:
                    print("  Length Category: Very Short")
                elif duration < 10:
                    print("  Length Category: Short")
                elif duration < 60:
                    print("  Length Category: Medium")
                elif duration < 300:
                    print("  Length Category: Long")
                else:
                    print("  Length Category: Very Long")

            # Technical details
            if "sample_rate" in metrics:
                sr = metrics["sample_rate"]
                print(f"  Sample Rate: {sr}Hz")

                if sr >= 44100:
                    print("  Audio Quality: 🎵 High fidelity")
                elif sr >= 22050:
                    print("  Audio Quality: 🔊 Standard")
                else:
                    print("  Audio Quality: 📻 Low fidelity")

        # Configuration analysis
        if "flags" in metadata:
            flags = metadata["flags"]
            optimizations = []

            if flags.get("cpu_mode", False):
                optimizations.append("CPU mode")
            if flags.get("skip_audio_processing", False):
                optimizations.append("Fast processing")
            if flags.get("skip_preprocessors", False):
                optimizations.append("No preprocessing")

            if optimizations:
                print(f"  Optimizations: {', '.join(optimizations)}")

        # Input analysis
        if "input" in metadata:
            input_data = metadata["input"]

            # Source type
            if "voice_profile" in input_data and input_data["voice_profile"]:
                print(f"  Voice Source: 👤 Profile ({input_data['voice_profile']})")
            elif "speaker_file" in input_data and input_data["speaker_file"]:
                print(f"  Voice Source: 🎙️ File ({Path(input_data['speaker_file']).name})")
            elif "speaker_prompt" in input_data and input_data["speaker_prompt"]:
                print("  Voice Source: ✍️ Text prompt")

            # Text processing
            if "processed_chunks" in input_data:
                chunks = input_data["processed_chunks"]
                print(f"  Text Chunks: {chunks}")

                if chunks > 10:
                    print("  Text Complexity: 📚 Very Complex")
                elif chunks > 5:
                    print("  Text Complexity: 📖 Complex")
                elif chunks > 2:
                    print("  Text Complexity: 📝 Moderate")
                else:
                    print("  Text Complexity: 📄 Simple")

    @staticmethod
    def analyze_directory(directory: Path) -> None:
        """Analyze all metadata files in a directory."""
        toml_files = list(directory.glob("*.toml"))

        if not toml_files:
            print(f"No TOML metadata files found in {directory}")
            return

        print(f"\nFound {len(toml_files)} metadata files in {directory}")

        # Overall statistics
        total_processing_time = 0
        total_duration = 0
        quality_scores = []
        engines_used = {}
        languages_used = {}

        for toml_file in toml_files:
            metadata = MetadataAnalyzer.load_metadata(toml_file)
            if not metadata:
                continue

            # Aggregate statistics
            if "general" in metadata:
                general = metadata["general"]

                # Processing time
                if "processing_time_sec" in general:
                    total_processing_time += general["processing_time_sec"]

                # Engine usage
                engine = general.get("engine", "unknown")
                engines_used[engine] = engines_used.get(engine, 0) + 1

                # Language usage
                language = general.get("language", "unknown")
                languages_used[language] = languages_used.get(language, 0) + 1

            if "output" in metadata and "metrics" in metadata["output"]:
                metrics = metadata["output"]["metrics"]

                # Duration
                if "duration_sec" in metrics:
                    total_duration += metrics["duration_sec"]

                # Quality scores
                if "voice_quality_score" in metrics:
                    quality_scores.append(metrics["voice_quality_score"])

        # Display summary statistics
        print("\n" + "=" * 60)
        print("Directory Summary")
        print("=" * 60)

        print("\n📊 Overall Statistics:")
        print(f"  Total Files: {len(toml_files)}")
        print(f"  Total Processing Time: {total_processing_time:.1f}s")
        print(f"  Total Audio Duration: {total_duration:.1f}s")

        if quality_scores:
            avg_quality = sum(quality_scores) / len(quality_scores)
            print(f"  Average Quality Score: {avg_quality:.1f}/100")

        # Engine distribution
        if engines_used:
            print("\n🔧 Engine Usage:")
            for engine, count in sorted(engines_used.items(), key=lambda x: x[1], reverse=True):
                percentage = (count / len(toml_files)) * 100
                print(f"  {engine}: {count} ({percentage:.1f}%)")

        # Language distribution
        if languages_used:
            print("\n🌍 Language Distribution:")
            for lang, count in sorted(languages_used.items(), key=lambda x: x[1], reverse=True):
                percentage = (count / len(toml_files)) * 100
                print(f"  {lang}: {count} ({percentage:.1f}%)")

        # Performance insights
        if total_processing_time > 0 and total_duration > 0:
            efficiency = total_duration / total_processing_time
            print("\n⚡ Performance Insights:")
            print(f"  Processing Efficiency: {efficiency:.2f}x real-time")

            if efficiency > 5:
                print("  Overall Performance: Excellent (>5x real-time)")
            elif efficiency > 3:
                print("  Overall Performance: Good (>3x real-time)")
            elif efficiency > 1:
                print("  Overall Performance: Acceptable (>1x real-time)")
            else:
                print("  Overall Performance: Needs Improvement (<1x real-time)")


def main():
    parser = argparse.ArgumentParser(description="Analyze Montaigne TTS metadata files")
    parser.add_argument("path", nargs="?", type=str, help="Path to metadata file or directory")
    parser.add_argument("--directory", "-d", type=str, help="Directory to analyze")
    parser.add_argument("--json", action="store_true", help="Output in JSON format")

    args = parser.parse_args()

    # Determine what to analyze
    if args.directory:
        path = Path(args.directory)
        if not path.is_dir():
            print(f"Error: {path} is not a directory")
            sys.exit(1)

        MetadataAnalyzer.analyze_directory(path)

    elif args.path:
        path = Path(args.path)

        if path.is_file():
            MetadataAnalyzer.analyze_single_file(path)
        elif path.is_dir():
            MetadataAnalyzer.analyze_directory(path)
        else:
            print(f"Error: {path} does not exist")
            sys.exit(1)

    else:
        # Default to current directory
        MetadataAnalyzer.analyze_directory(Path.cwd())


if __name__ == "__main__":
    main()
