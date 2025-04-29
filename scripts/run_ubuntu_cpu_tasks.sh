#!/bin/bash
# This script executes the Ubuntu CPU-only TTS tasks.
set -e

echo "🚀 Running TTS tasks on Ubuntu (CPU-only, No Nix/Flake)..."
mkdir -p input output

if [ ! -f "input/speaker.wav" ]; then
    echo "🔊 Creating sample speaker.wav file (requires ffmpeg)..."
    command -v ffmpeg >/dev/null 2>&1 || { echo "❌ ffmpeg command needed but not found!"; exit 1; }
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav
fi

echo "🐍 Setting up Python virtual environment (.venv) using UV..."
command -v uv >/dev/null 2>&1 || { echo "❌ uv command not found! Install uv first (e.g., pip install uv)."; exit 1; }
# Ensure clean environment if script is rerun
rm -rf .venv
uv venv .venv --seed # Create venv

echo "📦 Installing dependencies (CPU-only PyTorch & montaigne package) into .venv using system uv..."
# Use the system 'uv' command and point it to the venv's Python interpreter

# 1. Install PyTorch CPU first
echo "   Installing PyTorch CPU..."
uv pip install --python .venv/bin/python \
    torch==2.1.2 torchaudio==2.1.2 --extra-index-url https://download.pytorch.org/whl/cpu

# 2. Install the montaigne package from the packages directory editably.
#    This ensures its modules are found and pulls in its specific dependencies.
#    Add any other direct dependencies needed at the top level if required (like numpy/scipy if not already pulled).
echo "   Installing montaigne package and dependencies..."
uv pip install --python .venv/bin/python \
    numpy pandas scipy \
    -e ./packages/montaigne # <-- Install the specific package editably

# Note: We removed the '-e .' which installed the root workspace.
# We now explicitly install the required member '-e ./packages/montaigne'.

echo "✨ Running TTS synthesis with CPU using uv run..."
# Force CPU mode via env vars and use 'uv run' to execute within the venv
COQUI_TOS_AGREED=1 CUDA_VISIBLE_DEVICES="" USE_CUDA="0" FORCE_CPU="1" \
uv run python -m montaigne.main synthesize \
    --cpu \
    --output-file output/debug_output.wav \
    --speaker-wav input/speaker.wav \
    --language en \
    --text "This is a debug test with emphasis (Ubuntu CPU script)."

echo "🐾 Running Bark synthesis with CPU using uv run..."
COQUI_TOS_AGREED=1 CUDA_VISIBLE_DEVICES="" USE_CUDA="0" FORCE_CPU="1" \
uv run python -m montaigne.main synthesize \
    --engine bark \
    --cpu \
    --text "Hello from the Bark engine on Ubuntu (CPU script)." \
    --language en \
    --output-file output/bark_ubuntu_test.wav


echo "▶️ Running XTTS with YouTube speaker using uv run..."
COQUI_TOS_AGREED=1 CUDA_VISIBLE_DEVICES="" USE_CUDA="0" FORCE_CPU="1" \
uv run python -m montaigne.main synthesize \
    --engine xtts \
    --speaker-youtube-id "dQw4w9WgXcQ" \
    --text "Testing YouTube download." \
    --language en \
    --output-file output/yt_test.wav


echo "✅ TTS tasks completed successfully in CPU-only mode! Activate env with: source .venv/bin/activate"
