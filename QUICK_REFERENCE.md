# Montaigne TTS Quick Reference

## 🚀 New Features at a Glance

### 1. Output Format
```bash
# MP3 output (default)
montaigne synthesize --text "Hello"

# WAV output
montaigne synthesize --text "Hello" --output-format wav
```

### 2. File Naming
```bash
# Automatic naming: en-obama-xtts-xtts_v2-20240503_143022.mp3
montaigne synthesize --text "Hello" --voice-profile obama

# Custom naming
montaigne synthesize --text "Hello" --output-file custom.mp3
```

### 3. Processing Control
```bash
# Skip all processing (fastest)
montaigne synthesize --text "Hello" --skip-audio-processing

# Skip specific steps
montaigne synthesize --text "Hello" \
    --skip-preprocessors \
    --skip-voice-preprocessing \
    --skip-voice-isolation
```

### 4. Audio Metrics
```bash
# Metrics displayed automatically
📊 Output Audio Metrics:
  Duration: 12.3s
  SNR: 24.5dB
  Voice Quality Score: 85.3/100
```

### 5. Metadata Access
```python
# Load synthesis metadata
import tomli
with open("output.mp3.toml", "rb") as f:
    metadata = tomli.load(f)
    
# Check quality score
score = metadata["output"]["metrics"]["voice_quality_score"]
print(f"Quality: {score}/100")
```

### 6. Metadata Analysis
```bash
# Analyze single metadata file
python metadata_analyzer.py output.mp3.toml

# Analyze directory
python metadata_analyzer.py --directory ./output_files

# JSON output
python metadata_analyzer.py --json output.mp3.toml
```

## 🔄 Common Workflows

### Fastest Synthesis
```bash
montaigne synthesize \
    --text "Quick test" \
    --language en \
    --speaker-wav voice.wav \
    --skip-audio-processing
```

### Quality Analysis
```bash
# Generate high-quality output
montaigne synthesize \
    --text "Quality test" \
    --voice-profile morgan_freeman \
    --output-file quality.mp3

# Check metrics
cat quality.mp3.toml
```

### Batch Processing
```bash
# Process multiple texts
for text in "Hello" "Goodbye" "Thank you"; do
    montaigne synthesize \
        --text "$text" \
        --voice-profile obama \
        --skip-audio-processing
done

# Analyze results
python metadata_analyzer.py --directory .
```

## 🎯 Performance Tips

| Flag | Speed Boost | Quality Impact |
|------|-------------|----------------|
| `--skip-audio-processing` | 5x faster | Minimal |
| `--skip-preprocessors` | 2x faster | Moderate |
| `--skip-voice-preprocessing` | 1.5x faster | Low (profiles only) |
| `--skip-voice-isolation` | 3x faster | Low (profiles only) |

## 🔍 Quick Troubleshooting

### Low Quality Output
1. Check quality score in metadata
2. Try different voice profile
3. Ensure good input audio (SNR > 15dB)
4. Avoid `--skip-audio-processing` for best quality

### Slow Processing
1. Use `--skip-audio-processing` for speed
2. Consider CPU mode for short texts
3. Check metadata for processing times

### File Not Found
- Check automatic naming pattern
- Use `--output-file` for specific paths
- Verify output directory exists

## 📦 Required Dependencies

```bash
# Install new dependencies
pip install tomli-w  # TOML writing
pip install librosa  # Audio analysis
```

## 🆕 Version Checking

```bash
# Check current version
montaigne --version

# Check feature support
python -c "import tomli_w; print('TOML writing: OK')"
python -c "import librosa; print('Audio metrics: OK')"
```