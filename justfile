# -*- mode: conf -*-

# Load environment variables from .env file if it exists
set dotenv-load := true

# Justfile for the Montaigne TTS project
# Uses Nix Flake for environment and dependency management.

# === Variables ===
PROJECT_NAME := "montaigne" # Should match pyproject.toml
UV           := "uv" # Keep uv command available if needed for other tasks
# Define MODEL_PATH_VAR using env_var function for HOME
MODEL_PATH_VAR := env_var('HOME') + "/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2"

# === Docker Settings ===
DOCKER_TAG_LATEST := "latest"
DOCKER_TAG_GIT    := `git rev-parse --short HEAD`
DOCKER_IMAGE_NAME := PROJECT_NAME
# Use env_var_or_default; GITHUB_REPOSITORY is set in GH Actions. REPLACE FALLBACK FOR LOCAL USE.
GITHUB_OWNER_REPO := env_var_or_default('GITHUB_REPOSITORY', "hoffmann/montaigne") # Adjusted fallback
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

# === Analysis ===
analytics:
    @echo "📊 Running commit analysis..."
    @python aider_analytics.py

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
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/ model_files/ entrypoint.sh Dockerfile.bak

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

# Run XTTS synthesis (Must be run inside `nix develop`)
xtts: prepare_dirs
    @echo "✨ Running XTTS synthesis..."
    @python -m montaigne.main synthesize \
        --output-file output/xtts_output.wav \
        --speaker-wav input/speaker.wav \
        --language en \
        --text "This is a test with XTTS. It supports [p=0.5] pauses and *emphasis*."

# Run Bark synthesis (Must be run inside `nix develop`)
bark: prepare_dirs
    @echo "🐾 Running Bark synthesis..."
    @python -m montaigne.main synthesize \
        --engine bark \
        --text "Hello from the Bark engine. It sounds different!" \
        --language en \
        --output-file output/bark_en_default.wav

# Run YouTube speaker synthesis (Must be run inside `nix develop`)
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

# Check Dockerfile with hadolint
hadolint_check:
    @echo "🔍 Checking Dockerfile with hadolint..."
    @if ! command -v hadolint >/dev/null 2>&1; then \
        echo "⚠️ hadolint not found, attempting to run via Docker..."; \
        if ! docker run --rm -i -v $(pwd)/.hadolint.yaml:/.hadolint.yaml hadolint/hadolint < Dockerfile; then \
            echo "❌ Dockerfile linting failed"; \
            exit 1; \
        fi; \
    else \
        if ! hadolint Dockerfile; then \
            echo "❌ Dockerfile linting failed"; \
            exit 1; \
        fi; \
    fi
    @echo "✅ Dockerfile passed linting checks"

# Prepare local TTS model for Docker build context using just variable
prepare_local_model:
    @echo "📦 Preparing local TTS model..."
    @mkdir -p model_files
    @# Use the just variable {{ MODEL_PATH_VAR }}. No $$ needed.
    if [ -d "{{ MODEL_PATH_VAR }}" ]; then \
    echo '📦 Found local model at "{{ MODEL_PATH_VAR }}" - copying to build context'; \
    if ! rsync -a --info=progress2 "{{ MODEL_PATH_VAR }}/" model_files/; then \
        echo '❌ Failed to copy local model from "{{ MODEL_PATH_VAR }}"'; \
        exit 1; \
    fi; \
    echo "✅ Local model copied successfully."; \
    else \
    echo '⚠️ Local model not found at "{{ MODEL_PATH_VAR }}"'; \
    echo "   Model will be downloaded during Docker build if USE_LOCAL_MODEL=true is set."; \
    fi

# Create Entrypoint and Modify Dockerfile
prepare_docker_files: prepare_local_model
    @echo "📝 Creating entrypoint script for Docker..."
    @# Revert to line-by-line echo commands for creating entrypoint.sh
    @# This avoids the heredoc parsing issue in just.
    echo '#!/bin/bash' > entrypoint.sh
    echo 'set -e' >> entrypoint.sh
    echo '' >> entrypoint.sh
    echo '# Optional: Just print PyTorch version for confirmation' >> entrypoint.sh
    echo '/usr/bin/python3.11 -c "import torch; print(f\"---> PyTorch version: {torch.__version__}\", flush=True)" || echo "⚠️ Could not print PyTorch version."' >> entrypoint.sh
    echo '' >> entrypoint.sh
    echo '# Execute the original command' >> entrypoint.sh
    echo 'echo "🚀 Executing Docker CMD/args: $@" ' >> entrypoint.sh
    echo 'exec "$@"' >> entrypoint.sh
    @chmod +x entrypoint.sh
    @echo "✅ Entrypoint script created."

    @echo "📝 Modifying Dockerfile to add entrypoint..."
    @# Backup Dockerfile if not already backed up
    if [ ! -f "Dockerfile.bak" ]; then cp Dockerfile Dockerfile.bak; fi

    @# Create temporary Dockerfile.new with entrypoint logic
    # Check if entrypoint is already added to avoid duplication
    if grep -q "COPY entrypoint.sh /app/entrypoint.sh" Dockerfile; then \
        echo "ℹ️ Entrypoint already seems to be in Dockerfile. Skipping modification."; \
        cp Dockerfile Dockerfile.new; \
    else \
        echo "   Adding ENTRYPOINT logic to Dockerfile..."; \
        cat Dockerfile > Dockerfile.new; \
        echo "" >> Dockerfile.new; \
        echo "# Add entrypoint script for PyTorch security fixes" >> Dockerfile.new; \
        echo "COPY entrypoint.sh /app/entrypoint.sh" >> Dockerfile.new; \
        echo "RUN chmod +x /app/entrypoint.sh" >> Dockerfile.new; \
        echo "ENTRYPOINT [\"/app/entrypoint.sh\"]" >> Dockerfile.new; \
        echo "✅ Entrypoint added to temporary Dockerfile.new"; \
    fi

    @# Replace Dockerfile with new version
    mv Dockerfile.new Dockerfile
    @echo "✅ Dockerfile preparation complete."


# Build Docker image with better error handling
docker_build *ARGS: docker_check hadolint_check
    @echo "🐳 Building Docker image..."
    @echo "   Local Tags:  {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}, {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}"
    @echo "   GHCR Tags:   {{GHCR_TAG_LATEST}}, {{GHCR_TAG_COMMIT}}"

    @docker build \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" \
        -t "{{GHCR_TAG_LATEST}}" \
        -t "{{GHCR_TAG_COMMIT}}" \
        {{ARGS}} \
        . || (echo "❌ Docker build failed" && exit 1)

    @# Add manual tag if provided
    if [ -n "{{MANUAL_TAG}}" ]; then \
        echo "   Adding manual tag: {{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        docker tag "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" "{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
    fi
    @echo "✅ Docker image built successfully."

# Build with local model and entrypoint fix applied
docker_dev: prepare_docker_files
    @echo "🐳 Building Docker DEV image (local model + entrypoint)..."
    @just docker_build --build-arg USE_LOCAL_MODEL=true
    # Clean up copied model files, keep entrypoint.sh for potential manual runs
    @rm -rf ./model_files
    @echo "✅ Docker DEV build complete."

# Push GHCR tags
docker_push: docker_check
    @echo "⏫ Pushing GHCR images..."
    @test {{GITHUB_OWNER_REPO}} != "YOUR_USERNAME/YOUR_REPO" || (echo "❌ Cannot push using fallback GITHUB_REPOSITORY. Run from GitHub Actions or set env var GITHUB_REPOSITORY=owner/repo." && exit 1)
    @echo "   Pushing GHCR Tag: {{GHCR_TAG_LATEST}}"
    @docker push "{{GHCR_TAG_LATEST}}"
    @echo "   Pushing GHCR Tag: {{GHCR_TAG_COMMIT}}"
    @docker push "{{GHCR_TAG_COMMIT}}"
    @if [ -n "{{MANUAL_TAG}}" ]; then \
        _GHCR_TAG_MANUAL="{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        echo "   Pushing GHCR Manual Tag: $${_GHCR_TAG_MANUAL}"; \
        docker push "$${_GHCR_TAG_MANUAL}"; \
    fi
    @echo "✅ Images pushed to GHCR."


# Run container with proper volume mounts using absolute paths
# Ensures dummy speaker file exists for the default run
docker_run *ARGS: prepare_dirs docker_check
    @echo "🐳 Running default synthesis in Docker container..."
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ Creating dummy speaker.wav for Docker run..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "❌ Failed to create dummy speaker.wav." && exit 1); \
    fi
    @# This single '@' covers the CURRENT_DIR assignment AND the docker run command.
    # All subsequent lines starting at column 0 are part of this shell script.
    CURRENT_DIR=$(pwd); \
    echo "   Running docker command from: $${CURRENT_DIR}"; \
    docker run --rm \
        -v "${CURRENT_DIR}/input:/app/input:ro" \
        -v "${CURRENT_DIR}/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        montaigne synthesize \
        --text "This is a Docker container test." \
        --output-file /app/output/docker_output.wav \
        --speaker-wav /app/input/speaker.wav \
        --language en \
        {{ARGS}} || (echo "❌ Docker run failed" && exit 1)
    @echo "✅ Docker synthesis complete. Check output/docker_output.wav"

# GPU version with fixed volume paths
docker_run_gpu *ARGS: prepare_dirs docker_check
    @echo "🐳 Running Docker container with GPU..."
    @# This single '@' covers the CURRENT_DIR assignment AND the docker run command.
    CURRENT_DIR=$(pwd); \
    echo "   Running docker command from: $${CURRENT_DIR}"; \
    docker run --rm --gpus all \
        -v "${CURRENT_DIR}/input:/app/input:ro" \
        -v "${CURRENT_DIR}/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        montaigne \
        {{ARGS}} || (echo "❌ Docker GPU run failed" && exit 1)

# Lint Dockerfile without building
lint_dockerfile: hadolint_check
    @echo "✅ Dockerfile linting completed"

# === Main Pipeline ===
# Run TTS tasks inside Nix shell for reliable environment
run_tts_tasks:
    @echo "🚀 Running TTS tasks inside Nix shell..."
    @echo "🐍 Provide edits in DIFF format, please." # Request for Gemini
    @nix develop --impure --command bash -c '\
        set -e; \
        echo "=== Refresh repo-content.txt ==="; \
        repomix . --output repo-content.txt; \
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
    @echo "📦 Current Python environment packages:"
    @nix develop --impure --command bash -c 'uv pip freeze'

    @just run_tts_tasks || (echo "❌ TTS tasks failed, aborting pipeline." && exit 1)

    @echo "=== Running Docker Tasks ==="
    @just prepare_docker_files || (echo "❌ Docker file preparation failed." && exit 1)
    @echo "Attempting Docker build with local model (using --no-cache)..."
    @just docker_build --no-cache --build-arg USE_LOCAL_MODEL=true || \
      (echo "❌ Docker build failed with local model, trying without local model (using --no-cache)..." && \
       just docker_build --no-cache) || \
      (echo "❌ All Docker build attempts failed." && exit 1) # Exit if all builds fail

    # Step 3: Run Docker test with --cpu flag
    @echo "🐳 Running Docker test command..."
    @just docker_run --cpu || \
      (echo "❌ Docker test run failed." && exit 1) # Exit on test failure

    @echo "✅ All tasks completed successfully!"
