# === Docker Image Build with Entrypoint ===
prepare_docker_files: prepare_local_model
    @echo "📝 Creating entrypoint script for Docker..."
    @# Create entrypoint.sh with PyTorch security fix - line by line to avoid heredoc issues
    @echo '#!/bin/bash' > entrypoint.sh
    @echo '' >> entrypoint.sh
    @echo '# Apply PyTorch security settings before any model loading' >> entrypoint.sh
    @echo 'python3 -c "import torch; from torch.serialization import add_safe_globals; add_safe_globals([\"TTS.tts.configs.xtts_config.XttsConfig\"]); torch._C._set_default_weights_only_false_for_speed(); print(\"✅ PyTorch security configuration applied\")"' >> entrypoint.sh
    @echo '' >> entrypoint.sh
    @echo '# Execute the original command' >> entrypoint.sh
    @echo 'exec "$@"' >> entrypoint.sh
    @chmod +x entrypoint.sh
    
    @# Create temporary Dockerfile.new with entrypoint
    @cat Dockerfile > Dockerfile.new
    @# Add ENTRYPOINT before the final CMD
    @echo "" >> Dockerfile.new 
    @echo "# Add entrypoint script for PyTorch security fixes" >> Dockerfile.new
    @echo "COPY entrypoint.sh /app/entrypoint.sh" >> Dockerfile.new
    @echo "ENTRYPOINT [\"/app/entrypoint.sh\"]" >> Dockerfile.new
    @echo "" >> Dockerfile.new
    
    @# Make backup of original Dockerfile
    @if [ ! -f "Dockerfile.bak" ]; then cp Dockerfile Dockerfile.bak; fi
    
    @# Replace Dockerfile with new version
    @mv Dockerfile.new Dockerfile
    @echo "✅ Docker build files prepared with PyTorch security fix"# -*- mode: conf -*-

# Load environment variables from .env file if it exists
set dotenv-load := true

# Justfile for the Montaigne TTS project
# Uses Nix Flake for environment and dependency management.

# === Variables ===
PROJECT_NAME := "montaigne" # Should match pyproject.toml
UV           := "uv" # Keep uv command available if needed for other tasks

# === Docker Settings ===
DOCKER_TAG_LATEST := "latest"
DOCKER_TAG_GIT    := `git rev-parse --short HEAD`
DOCKER_IMAGE_NAME := PROJECT_NAME
GITHUB_OWNER_REPO := env_var_or_default('GITHUB_REPOSITORY', "hoffmann/montaigne") # Better default
GHCR_IMAGE_BASE   := "ghcr.io/" + GITHUB_OWNER_REPO + "/" + DOCKER_IMAGE_NAME 
GHCR_TAG_LATEST   := GHCR_IMAGE_BASE + ":" + DOCKER_TAG_LATEST
GHCR_TAG_COMMIT   := GHCR_IMAGE_BASE + ":" + DOCKER_TAG_GIT
MANUAL_TAG        := env_var_or_default('MANUAL_TAG', '') 

# === Default Task ===
default:
    @just --list

# === Environment & Dependencies (Managed by Nix Flake) ===
install:
    @echo "🐍 Python dependencies are managed by the Nix flake."
    @echo "✅ Environment should be ready when inside 'nix develop'."

setup: install

nix:
    @nix flake update
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure

# === Linting & Formatting ===
lint:
    @command -v ruff > /dev/null 2>&1 || (echo "❌ 'ruff' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "✨ Running Ruff linter..."
    @ruff check .

format:
    @command -v ruff > /dev/null 2>&1 || (echo "❌ 'ruff' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🎨 Running Ruff formatter..."
    @ruff format .

check: lint format
    @echo "✅ Lint and format checks passed."

# === Testing ===
test:
    @command -v pytest > /dev/null 2>&1 || (echo "❌ 'pytest' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🧪 Running tests with pytest..."
    @pytest tests/

# === Cleaning ===
clean_pycache:
    @echo "🧹 Removing __pycache__ directories and .pyc files..."
    @find . -type d -name "__pycache__" -exec rm -r {} +
    @find . -type f -name "*.py[co]" -delete

clean_build:
    @echo "🧹 Removing build artifacts..."
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/

clean: clean_pycache clean_build
    @echo "✅ Project directories cleaned."

clean_all: clean
    @echo "✅ Full clean completed."

# === TTS Tasks ===
# Create input/output dirs and sample audio if needed
prepare_dirs:
    @echo "📁 Preparing directories and sample audio..."
    @mkdir -p input output
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ Creating sample speaker.wav file..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "❌ Failed to create speaker.wav. Is ffmpeg installed?" && exit 1); \
    fi

# Run XTTS synthesis
xtts: prepare_dirs
    @echo "✨ Running XTTS synthesis..."
    @python -m montaigne.main synthesize \
        --output-file output/xtts_output.wav \
        --speaker-wav input/speaker.wav \
        --language en \
        --text "This is a test with XTTS. It supports [p=0.5] pauses and *emphasis*."

# Run Bark synthesis
bark: prepare_dirs
    @echo "🐾 Running Bark synthesis..."
    @python -m montaigne.main synthesize \
        --engine bark \
        --text "Hello from the Bark engine. It sounds different!" \
        --language en \
        --output-file output/bark_en_default.wav

# Run YouTube speaker synthesis
yt: prepare_dirs
    @echo "▶️ Running XTTS with YouTube speaker..."
    @python -m montaigne.main synthesize \
        --engine xtts \
        --speaker-youtube-id "dQw4w9WgXcQ" \
        --text "Testing YouTube download." \
        --language en \
        --output-file output/yt_test.wav

# === Docker Tasks ===
# Check if Docker is available and working
docker_check:
    @echo "🔍 Checking Docker setup..."
    @if ! command -v docker >/dev/null 2>&1; then \
        echo "❌ Docker not installed or not in PATH"; \
        exit 1; \
    fi
    @if ! docker info >/dev/null 2>&1; then \
        echo "❌ Docker daemon is not running or permission issue"; \
        echo "Try: sudo systemctl start docker"; \
        echo "     sudo usermod -aG docker $$USER && newgrp docker"; \
        exit 1; \
    fi
    @echo "✅ Docker is ready: $$(docker --version)"

# Prepare local TTS model for Docker
prepare_local_model:
    @echo "📦 Preparing local TTS model..."
    @mkdir -p model_files
    @MODEL_PATH="${HOME}/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2"; \
    if [ -d "$${MODEL_PATH}" ]; then \
        echo "📦 Found local model at $${MODEL_PATH} - copying to build context"; \
        if ! rsync -a --info=progress2 "$${MODEL_PATH}/" model_files/; then \
            echo "❌ Failed to copy local model from $${MODEL_PATH}"; \
            exit 1; \
        fi; \
        echo "✅ Local model copied successfully."; \
    else \
        echo "⚠️ Local model not found at $${MODEL_PATH}"; \
        echo "   Model will be downloaded during Docker build if USE_LOCAL_MODEL=true is set."; \
    fi

# Build Docker image with better error handling
docker_build *ARGS: docker_check
    @echo "🐳 Building Docker image..."
    @echo "   Local Tags:  {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}, {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}"
    @echo "   GHCR Tags:   {{GHCR_TAG_LATEST}}, {{GHCR_TAG_COMMIT}}"
    
    @# Use BuildKit and proper argument formatting
    @docker build \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" \
        -t "{{GHCR_TAG_LATEST}}" \
        -t "{{GHCR_TAG_COMMIT}}" \
        {{ARGS}} \
        . || (echo "❌ Docker build failed" && exit 1)
    
    @# Add manual tag if provided
    @if [ -n "{{MANUAL_TAG}}" ]; then \
        echo "   Adding manual tag: {{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        docker tag "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" "{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
    fi
    @echo "✅ Docker image built successfully."

# Build with local model and entrypoint fix
docker_dev: prepare_docker_files
    @echo "🐳 Building Docker image with local model and PyTorch security fix..."
    @just docker_build --build-arg USE_LOCAL_MODEL=true
    @rm -rf ./model_files
    @echo "⚠️ NOTE: Keeping entrypoint.sh for Docker runs"

# Run container with proper volume mounts using absolute paths
docker_run *ARGS: prepare_dirs docker_check
    @echo "🐳 Running default synthesis in Docker container..."
    # Get absolute paths to avoid expansion issues
    @CURRENT_DIR=$(pwd); \
    docker run --rm \
        -v "${CURRENT_DIR}/input:/app/input:ro" \
        -v "${CURRENT_DIR}/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        synthesize \
          --text "This is a Docker container test." \
          --output-file /app/output/docker_output.wav \
          --speaker-wav /app/input/speaker.wav \
          --language en \
        {{ARGS}} || (echo "❌ Docker run failed" && exit 1)
    @echo "✅ Docker synthesis complete. Check output/docker_output.wav"

# GPU version with fixed volume paths
docker_run_gpu *ARGS: prepare_dirs docker_check
    @echo "🐳 Running Docker container with GPU..."
    # Get absolute paths to avoid expansion issues
    @CURRENT_DIR=$(pwd); \
    docker run --rm --gpus all \
        -v "${CURRENT_DIR}/input:/app/input:ro" \
        -v "${CURRENT_DIR}/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        {{ARGS}} || (echo "❌ Docker GPU run failed" && exit 1)

# === Main Pipeline ===
# Run TTS tasks inside Nix shell for reliable environment
run_tts_tasks:
    @echo "🚀 Running TTS tasks inside Nix shell..."
    @echo "🐍 Provide edits in DIFF format, please."
    @nix develop --impure --command bash -c '\
        set -e; \
        echo "=== Refresh repo-content.txt ==="; \
        @repomix . --output repo-content.txt; \
        echo "=== Inside Nix Shell ==="; \
        just prepare_dirs; \
        echo "✨ Running XTTS synthesis..."; \
        python -m montaigne.main synthesize \
            --output-file output/debug_output.wav \
            --speaker-wav input/speaker.wav \
            --language en \
            --text "This is a debug test [p=0.5] with *emphasis*."; \
        echo "🐾 Running Bark synthesis..."; \
        python -m montaigne.main synthesize \
            --engine bark \
            --text "Hello from the Bark engine. It sounds different!" \
            --language en \
            --output-file output/bark_en_default.wav; \
        echo "▶️ Running YouTube speaker synthesis..."; \
        python -m montaigne.main synthesize \
            --engine xtts \
            --speaker-youtube-id "dQw4w9WgXcQ" \
            --text "Testing YouTube download." \
            --language en \
            --output-file output/yt_test.wav; \
        echo "=== Nix Shell Tasks Complete ==="; \
    ' || (echo "❌ TTS tasks failed" && exit 1)

# Improved main pipeline with better error handling
all:
    @echo "🚀 Starting Montaigne TTS pipeline..."
    
    @# Step 1: Run TTS tasks in Nix shell
    @just run_tts_tasks || (echo "❌ TTS tasks failed, aborting pipeline." && exit 1)
    
    @# Step 2: Build Docker image with PyTorch fixes
    @echo "=== Running Docker Tasks ==="
    @just prepare_docker_files || (echo "❌ Docker file preparation failed." && exit 1)
    @just docker_build --build-arg USE_LOCAL_MODEL=true || \
      (echo "❌ Docker build failed with local model, trying without..." && \
       just docker_build)
    
    @# Step 3: Run Docker test with --cpu flag
    @just docker_run --cpu || \
      (echo "❌ Docker test run failed, but previous steps completed." && exit 1)
    
    @echo "✅ All tasks completed successfully!"
