# New Features in Montaigne TTS

## 1. MP3 Output Support

### Default Format Change
- MP3 is now the default output format (replaces WAV)
- High-quality 192kbps encoding
- Smaller file sizes with good audio quality

### Usage
```bash
# MP3 output (default)
montaigne synthesize --text "Hello world" --language en --speaker-wav voice.wav

# Specify format explicitly
montaigne synthesize --text "Hello world" --language en --speaker-wav voice.wav --output-format mp3

# WAV output
montaigne synthesize --text "Hello world" --language en --speaker-wav voice.wav --output-format wav
```

## 2. Intelligent Default Naming

### Automatic Output Naming
If no output file is specified, Montaigne automatically generates a filename with the format:
```
{language}-{profile_or_speaker}-{engine}-{model}-{timestamp}.{format}
```

Examples:
- `en-obama-xtts-xtts_v2-20240503_143022.mp3`
- `pt-lula-bark-bark-20240503_143022.mp3`
- `en-default-xtts-xtts_v2-20240503_143022.mp3`

### Manual Naming
You can still specify custom output paths:
```bash
montaigne synthesize --text "Hello" --output-file custom/path/output.mp3
```

## 3. Audio Processing Control

### Skip All Processing
New `--skip-audio-processing` flag to bypass all audio transformations:
```bash
montaigne synthesize --text "Hello" --skip-audio-processing
```

### Granular Control
Additional options for fine-grained control:
- `--skip-preprocessors`: Skip text preprocessing
- `--skip-voice-preprocessing`: Skip voice profile preprocessing
- `--skip-voice-isolation`: Skip voice isolation for profiles

## 4. Comprehensive Audio Metrics

### Input Metrics
For each input audio file (speaker reference), Montaigne calculates:
- Signal-to-Noise Ratio (SNR)
- RMS Energy levels
- Dynamic range
- Spectral characteristics
- Voice quality score (0-100)

### Output Metrics
For synthesized audio, additional metrics:
- Duration
- Sample rate
- Harmonic ratio
- Pitch characteristics
- Zero-crossing rate

### Metrics Display
Metrics are displayed at the end of synthesis:
```
📊 Output Audio Metrics:
  Duration: 12.3s
  SNR: 24.5dB
  RMS Energy: 0.085
  Dynamic Range: 32.1dB
  Sample Rate: 22050Hz
  Voice Quality Score: 85.3/100
```

## 5. TOML Metadata Persistence

### Automatic Metadata Saving
Every synthesis run creates a corresponding `.toml` file with complete metadata:
- All synthesis parameters
- Engine configuration
- Processing flags
- Input/output metrics
- Timestamps and timing information

### Metadata Location
Metadata is saved alongside the output file:
- Output: `output.mp3`
- Metadata: `output.mp3.toml`

### Metadata Structure
```toml
[general]
engine = "xtts"
language = "en"
output_format = "mp3"
timestamp = "2024-05-03T14:30:22"
processing_time_sec = 12.5

[input]
text_source = "CLI --text option"
voice_profile = "obama"
processed_chunks = 3

[output]
file = "output.mp3"
synthesis_successful = true

[output.metrics]
duration_sec = 12.3
snr_db = 24.5
voice_quality_score = 85.3
```

## 6. Enhanced Voice Quality Scoring

### Quality Assessment
Montaigne now provides a composite voice quality score (0-100) based on:
- SNR quality (30% weight)
- Dynamic range (20% weight)
- Harmonic content (20% weight)
- Energy levels (15% weight)
- Spectral characteristics (10% weight)
- Pitch stability (5% weight)

### Interpreting Scores
- 90-100: Excellent voice quality
- 80-89: Good voice quality
- 70-79: Acceptable quality (may need improvement)
- Below 70: Poor quality (consider better input or settings)

## Migration Notes

### Breaking Changes

1. **Default Format**: MP3 is now default instead of WAV
   - Update scripts that expect WAV output
   - Use `--output-format wav` for legacy compatibility

2. **Output Naming**: Automatic naming scheme has changed
   - Custom scripts should handle the new naming pattern
   - Always use `--output-file` for consistent naming

### New Dependencies

Install required packages:
```bash
pip install tomli-w  # For TOML writing
pip install librosa  # For audio analysis
```

## Examples

### Basic Usage with New Features
```bash
# Use voice profile with MP3 output
montaigne synthesize \
    --text "The quick brown fox jumps" \
    --language en \
    --voice-profile morgan_freeman
    
# Skip all processing for fastest synthesis
montaigne synthesize \
    --text "Hello world" \
    --language en \
    --speaker-wav input.wav \
    --skip-audio-processing
    
# Custom output with metrics display
montaigne synthesize \
    --text "Test audio quality" \
    --language en \
    --speaker-wav input.wav \
    --output-file test_quality.mp3
```

### Analyzing Existing Synthesis

Load and analyze previous synthesis metadata:
```python
import tomli
from pathlib import Path

# Load metadata
with open("output.mp3.toml", "rb") as f:
    metadata = tomli.load(f)

# Check synthesis success
if metadata["output"]["synthesis_successful"]:
    print(f"Quality score: {metadata['output']['metrics']['voice_quality_score']}")
    print(f"Duration: {metadata['output']['metrics']['duration_sec']}s")
```

## Performance Optimization

The new `--skip-audio-processing` flag can significantly improve synthesis speed:
- No preprocessing: ~2x faster
- No voice isolation: ~3x faster (when using voice profiles)
- No postprocessing: ~1.5x faster
- Combined: Up to 5x faster synthesis

Use this flag for:
- Quick testing
- Batch processing where quality isn't critical
- Real-time applications