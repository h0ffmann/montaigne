#!/usr/bin/env python
"""
Utility to analyze Montaigne TTS synthesis metadata files.

Usage:
    python metadata_analyzer.py <metadata_file>
    python metadata_analyzer.py --directory <dir>  # Analyze all metadata files in directory
"""

import sys
from pathlib import Path
from typing import Any

try:
    import click
    import tomli

    TOMLI_AVAILABLE = True
except ImportError:
    TOMLI_AVAILABLE = False
    click.echo("Error: tomli package is required for metadata analysis", err=True)
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
        except (tomli.TOMLDecodeError, UnicodeDecodeError) as e:
            click.echo(f"❌ Error parsing TOML file {path}: {e}", err=True)
            sys.exit(1)
        except IOError as e:
            click.echo(f"❌ Error reading file {path}: {e}", err=True)
            sys.exit(1)

    @staticmethod
    def analyze_single_file(metadata_path: Path):
        """Analyze a single metadata file."""
        if not metadata_path.exists():
            click.echo(f"❌ Metadata file not found: {metadata_path}", err=True)
            sys.exit(1)

        metadata = MetadataAnalyzer.load_metadata(metadata_path)
        MetadataAnalyzer._print_analysis(metadata, metadata_path.name)

    @staticmethod
    def _print_analysis(metadata: dict[str, Any], filename: str):
        """Print analysis of metadata to console."""
        print(f"\n🔍 Analyzing: {filename}")
        print("=" * 60)

        # General info
        general = metadata.get("general", {})
        print("\nℹ️ General Information:")
        print(f"  Engine: {general.get('engine', 'unknown')}")
        print(f"  Language: {general.get('language', 'unknown')}")
        print(f"  Output Format: {general.get('output_format', 'unknown')}")

        # Input info
        input_data = metadata.get("input", {})
        print("\n📥 Input:")
        print(f"  Source: {input_data.get('text_source', 'unknown')}")
        print(f"  Processed Chunks: {input_data.get('processed_chunks', 'unknown')}")

        speaker_file = input_data.get("speaker_file")
        if speaker_file:
            print(f"  Voice Source: 🎙️ File ({Path(speaker_file).name})")
        elif "speaker_prompt" in input_data and input_data["speaker_prompt"]:
            print("  Voice Source: ✍️ Text prompt")

        # Output info
        output = metadata.get("output", {})
        print("\n📤 Output:")
        print(f"  File: {Path(output.get('file', 'unknown')).name}")
        print(f"  Format: {output.get('format', 'unknown')}")
        print(f"  Duration: {output.get('duration', 'unknown')}s")

        # Performance
        stats = metadata.get("stats", {})
        print("\n⏱️ Performance:")
        print(f"  Processing Time: {stats.get('processing_time', 'unknown')}s")
        print(f"  Real-time Factor: {stats.get('real_time_factor', 'unknown')}x")

        print("\n")
        print("=" * 60)

    @staticmethod
    def analyze_directory(directory: Path):
        """Analyze all metadata files in a directory."""
        if not directory.is_dir():
            click.echo(f"❌ Not a directory: {directory}", err=True)
            sys.exit(1)

        toml_files = list(directory.glob("*.toml"))
        if not toml_files:
            click.echo(f"❌ No .toml files found in {directory}", err=True)
            sys.exit(1)

        total_processing_time = 0.0
        total_duration = 0.0
        engines_used = {}
        languages_used = {}

        for toml_file in toml_files:
            try:
                metadata = MetadataAnalyzer.load_metadata(toml_file)

                # Collect stats
                stats = metadata.get("stats", {})
                total_processing_time += float(stats.get("processing_time", 0))
                total_duration += float(metadata.get("output", {}).get("duration", 0))

                # Track engine usage
                engine = metadata.get("general", {}).get("engine")
                if engine:
                    engines_used[engine] = engines_used.get(engine, 0) + 1

                # Track language usage
                language = metadata.get("general", {}).get("language")
                if language:
                    languages_used[language] = languages_used.get(language, 0) + 1

            except Exception as e:
                click.echo(f"⚠️ Error processing {toml_file.name}: {e}", err=True)
                continue

        avg_processing_time = total_processing_time / len(toml_files) if toml_files else 0
        avg_duration = total_duration / len(toml_files) if toml_files else 0

        print("\n")
        print("=" * 60)

        print("\n📊 Overall Statistics:")
        print(f"  Total Files: {len(toml_files)}")
        print(f"  Total Processing Time: {total_processing_time:.1f}s")
        print(f"  Average Processing Time per File: {avg_processing_time:.1f}s")
        print(f"  Total Audio Duration: {total_duration:.1f}s")
        print(f"  Average Duration per File: {avg_duration:.1f}s")

        # Engine distribution
        if engines_used:
            print("\n🔧 Engine Usage:")
            for engine, count in sorted(engines_used.items(), key=lambda x: x[1], reverse=True):
                percentage = (count / len(toml_files)) * 100
                print(f"  {engine}: {count} files ({percentage:.1f}%)")

        # Language distribution
        if languages_used:
            print("\n🌍 Language Distribution:")
            for lang, count in sorted(languages_used.items(), key=lambda x: x[1], reverse=True):
                percentage = (count / len(toml_files)) * 100
                print(f"  {lang}: {count} files ({percentage:.1f}%)")

        # Performance insights
        if total_processing_time > 0 and total_duration > 0:
            efficiency = total_duration / total_processing_time
            print("\n⚡ Performance Insights:")
            print(f"  Processing Efficiency: {efficiency:.2f}x real-time")

        print("\n")
        print("=" * 60)
        print("✅ All metadata files analyzed.")


@click.command()
@click.argument("metadata_file", required=False, type=click.Path(exists=True, path_type=Path))
@click.option(
    "--directory",
    "-d",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    help="Analyze all metadata files in directory",
)
@click.option("--json", "json_output", is_flag=True, help="Output in JSON format (for future use)")
def main(metadata_file, directory, json_output):
    """Analyze Montaigne TTS metadata files."""
    if directory and metadata_file:
        click.echo("Error: Specify either a metadata file or --directory, not both.", err=True)
        sys.exit(1)

    if not directory and not metadata_file:
        click.echo("Error: Either metadata file or --directory must be specified.", err=True)
        sys.exit(1)

    # Analyze directory
    if directory:
        MetadataAnalyzer.analyze_directory(directory)
        return

    # Analyze single file
    MetadataAnalyzer.analyze_single_file(metadata_file)


if __name__ == "__main__":
    main()
