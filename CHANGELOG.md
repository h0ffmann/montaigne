# Changelog

All notable changes to Montaigne TTS will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2024-05-03

### Added
- **MP3 Output Support**: MP3 is now the default output format with 192kbps encoding
- **Intelligent Default Naming**: Automatic filename generation using pattern `{language}-{profile}-{engine}-{model}-{timestamp}.{format}`
- **Comprehensive Audio Metrics**: Detailed analysis including SNR, spectral characteristics, and voice quality scoring
- **TOML Metadata Persistence**: Complete synthesis metadata saved alongside output files
- **Audio Processing Control**: New flags to skip processing steps for faster synthesis
  - `--skip-audio-processing`: Skip all audio transformations
  - `--skip-preprocessors`: Skip text preprocessing only
  - `--skip-voice-preprocessing`: Skip voice profile preprocessing
  - `--skip-voice-isolation`: Skip voice isolation step
- **Audio Quality Scoring**: Composite voice quality score (0-100) based on multiple metrics
- **Metadata Analysis Tool**: New CLI utility to analyze synthesis metadata files
- **New Dependencies**: `tomli-w` for TOML writing, enhanced `librosa` integration

### Changed
- **Breaking**: Default output format changed from WAV to MP3
- **Breaking**: Default output naming scheme follows new pattern
- **Modularized Code**: Split audio metrics and metadata management into separate modules
- **Enhanced Metrics Display**: Improved output with comprehensive audio metrics
- Updated to uv 0.7.2 in the development environment

### Fixed
- Improved error handling for audio processing pipeline
- Better memory management for large synthesis tasks

### Performance
- Up to 5x faster synthesis with `--skip-audio-processing` flag
- Optimized metadata handling and storage

## Migration Guide

### From v0.1.0 to v0.2.0

1. **Output Format**: Update scripts expecting WAV output
   ```bash
   # Old (WAV output)
   montaigne synthesize --text "Hello"
   
   # New (MP3 default)
   montaigne synthesize --text "Hello"
   
   # Force WAV
   montaigne synthesize --text "Hello" --output-format wav
   ```

2. **Output Naming**: Scripts relying on specific output names should use `--output-file`
   ```bash
   # Ensure consistent naming
   montaigne synthesize --text "Hello" --output-file output.mp3
   ```

3. **New Dependencies**: Install additional packages
   ```bash
   pip install tomli-w  # For metadata saving
   ```

4. **Metadata Access**: Update any scripts that parse output metadata
   ```python
   # New: Load TOML metadata
   import tomli
   with open("output.mp3.toml", "rb") as f:
       metadata = tomli.load(f)
   ```

## [0.1.0] - 2024-04-01

### Added
- Initial release
- Support for XTTS v2 and Bark engines
- Voice profiles system
- Text preprocessing with emphasis and tone tags
- YouTube voice extraction
- CPU/GPU support
- Command-line interface