#!/usr/bin/env bash
set -e

echo "--- [Nix Env] Check Environment ---"
echo "🐍 Python: $(python --version)"
echo "📦 UV: $(uv --version)"
echo "🐍 PyTorch check:"
python -c "import torch; print(f'  Version: {torch.__version__}, CUDA Available: {torch.cuda.is_available()}')" || echo "  PyTorch check failed or not installed yet."

echo "--- [Nix Env] Install/Update Workspace Packages ---"
uv pip install -e . --verbose
echo "Verifying montaigne module..."
python -c "import montaigne; print(f'✅ Found montaigne module: {montaigne.__file__}')"

echo "--- [Nix Env] Generate Repomix ---"
repomix .

echo "--- [Nix Env] Prepare Directories & Run TTS Tasks ---"
just prepare_dirs
echo "✨ Running XTTS synthesis..."
python -m montaigne.main synthesize \
    --output-file output/xtts_output.wav \
    --speaker-wav input/speaker.wav \
    --language en \
    --text "This is a test with XTTS. It supports [p=0.5] pauses and *emphasis*."

echo "🐾 Running Bark synthesis..."
python -m montaigne.main synthesize \
    --engine bark \
    --text "Hello from the Bark engine. It sounds different!" \
    --language en \
    --output-file output/bark_en_default.wav

echo "▶️ Running XTTS with YouTube speaker..."
python -m montaigne.main synthesize \
    --engine xtts \
    --speaker-youtube-id "dQw4w9WgXcQ" \
    --text "Testing YouTube download." \
    --language en \
    --output-file output/yt_test.wav

echo "--- [Nix Env -> Host Docker] Running Docker Tasks ---"
echo "Checking Docker version (from Nix env)..."
docker --version

echo "Preparing Docker files (via nested just)..."
just prepare_docker_files || { echo "❌ Docker file preparation failed."; exit 1; }

echo "Building Docker image (via nested just - trying local model first)..."
command just docker_build USE_LOCAL_MODEL=true --no-cache || { \
  echo "   ⚠️ Docker build with local model failed, trying without local model..."; \
  command just docker_build --no-cache ; } || { \
  echo "❌ All Docker build attempts failed."; exit 1; }

echo "Running Docker test command (via nested just)..."
command just docker_run --cpu || { echo "❌ Docker test run failed."; exit 1; }

echo "--- [Nix Env] Tasks Completed ---"
