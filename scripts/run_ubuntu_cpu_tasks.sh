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
uv venv .venv --seed # Create venv

echo "📦 Installing dependencies (CPU-only PyTorch)..."
# Use uv binary from the created venv to install into it
.venv/bin/uv pip install \
    torch==2.1.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cpu \
    numpy pandas scipy \
    -e . # Install editable local project into venv

echo "✨ Running TTS synthesis with CPU..."
# Force CPU mode via env vars and call python from venv directly
CUDA_VISIBLE_DEVICES="" USE_CUDA="0" FORCE_CPU="1" \
.venv/bin/python -m montaigne.main synthesize \
    --cpu \
    --output-file output/debug_output.wav \
    --speaker-wav input/speaker.wav \
    --language en \
    --text "This is a debug test with emphasis (Ubuntu CPU script)."

echo "✨ Running Bark synthesis with CPU..."
CUDA_VISIBLE_DEVICES="" USE_CUDA="0" FORCE_CPU="1" \
.venv/bin/python -m montaigne.main synthesize \
    --engine bark \
    --cpu \
    --text "Hello from the Bark engine on Ubuntu (CPU script)." \
    --language en \
    --output-file output/bark_ubuntu_test.wav

echo "👾 Generate repomix output..."
# Ensure repomix is installed in the venv first if not globally available
echo "   (Skipping repomix install check - ensure it's installed in venv or globally if needed)"
# Example: .venv/bin/uv pip install repomix
.venv/bin/python -m repomix . # Assuming repomix installed as module

echo "✅ TTS tasks completed successfully in CPU-only mode! Activate env with: source .venv/bin/activate"
