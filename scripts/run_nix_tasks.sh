#!/bin/bash
# This script executes tasks within the Nix environment for the 'all' pipeline.
set -e

echo "--- [Nix Env] Check Environment ---"
echo "🐍 Python: $(python --version)"
echo "📦 UV: $(uv --version)"
python -c "import torch; print('🐍 PyTorch Version:', torch.__version__)" || echo "🐍 PyTorch not available yet."

echo "--- [Nix Env] Installing Workspace Packages ---"
uv pip install -e . --verbose
python -c "import montaigne; print(f'✅ Verified montaigne module: {montaigne.__file__}')"

echo "--- [Nix Env] Running Linter and Formatter Checks ---"
ruff check .
ruff format .

echo "--- [Nix Env] Generating Repomix ---"
repomix .

echo "--- [Nix Env] Preparing Directories ---"
# Use direct commands instead of 'just prepare_dirs'
mkdir -p input output
if [ ! -f "input/speaker.wav" ]; then
    echo "⚠️ Creating sample speaker.wav file (via script)..."
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        { echo "❌ Failed to create speaker.wav (inside script)."; exit 1; }
fi

echo "--- [Nix Env] Running TTS Synthesis Tasks ---"
echo "✨ Running XTTS synthesis (via script)..."
python -m montaigne.main synthesize \
    --output-file output/xtts_output.wav \
    --speaker-wav input/speaker.wav \
    --language en \
    --text "This is a test with XTTS from script."

echo "🐾 Running Bark synthesis (via script)..."
python -m montaigne.main synthesize \
    --engine bark \
    --text "Hello from the Bark engine from script." \
    --language en \
    --output-file output/bark_en_default.wav

echo "▶️ Running XTTS with YouTube speaker (via script)..."
python -m montaigne.main synthesize \
    --engine xtts \
    --speaker-youtube-id "dQw4w9WgXcQ" \
    --text "Testing YouTube download from script." \
    --language en \
    --output-file output/yt_test.wav


echo "--- [Nix Env] Tasks Completed Successfully ---"
