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
# Installs workspace packages using uv within the current (presumably nix) environment
install_workspace:
    @echo "📦 Installing/Updating workspace packages using UV..."
    # Ensure uv is available
    @command -v {{UV}} > /dev/null 2>&1 || (echo "❌ '{{UV}}' command not found. Are you inside 'nix develop'?" && exit 1)
    # Install root and any subpackages found/configured in pyproject.toml/packages/*
    @{{UV}} pip install -e . --verbose
    # Example if explicit listing is needed and ./packages/montaigne exists:
    # @{{UV}} pip install -e ./packages/montaigne -e . --verbose
    @echo "✅ Workspace packages installed."

setup: install_workspace # Alias

# Update flake and enter nix shell, then install workspace packages
nix_setup:
    @nix flake update
    @echo "Entering Nix shell and setting up workspace..."
    # Use --command to execute setup steps *within* the environment
    # Add NIXPKGS_ALLOW_BROKEN=1 if needed by your flake dependencies
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash -c ' \
        echo "🐍 Inside Nix environment. Installing workspace packages..."; \
        just install_workspace; \
        echo "✅ Workspace setup complete inside Nix environment."; \
        echo "ℹ️ You can now run other commands or type '\''exit'\'' to leave."; \
        exec bash' # Keep the shell open

# Enter nix develop shell (user should run `just install_workspace` manually if needed)
nix_shell:
    @nix flake update
    @echo "Entering Nix develop shell..."
    # Add NIXPKGS_ALLOW_BROKEN=1 if needed
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure

# === Linting & Formatting (Run inside Nix Shell) ===
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
    @aider-analytics .

# === Testing ===
test:
    @command -v pytest > /dev/null 2>&1 || (echo "❌ 'pytest' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🧪 Running tests with pytest..."
    @pytest packages/montaigne/tests/ # Update test path if tests were moved

# === Cleaning ===
clean_pycache:
    @echo "🧹 Removing __pycache__ directories and .pyc files..."
    @find . -type d -name "__pycache__" -exec rm -r {} +
    @find . -type f -name "*.py[co]" -delete

clean_build:
    @echo "🧹 Removing build artifacts..."
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/ model_files/ entrypoint.sh Dockerfile.bak .venv/

clean: clean_pycache clean_build
    @echo "✅ Project directories cleaned."

clean_all: clean
    @echo "✅ Full clean completed."

# === TTS Tasks ===
# Create input/output dirs and sample audio if needed
prepare_dirs:
    @echo "📁 Preparing directories and sample audio..."
    @mkdir -p input output
    # Ensure ffmpeg is available (should be via Nix flake)
    @command -v ffmpeg > /dev/null 2>&1 || (echo "❌ 'ffmpeg' not found. Ensure it is in your Nix flake dependencies and you are inside 'nix develop'." && exit 1)
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ Creating sample speaker.wav file..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "❌ Failed to create speaker.wav." && exit 1); \
    fi

# Run XTTS synthesis (Must be run inside `nix develop`)
xtts: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "✨ Running XTTS synthesis..."
    @python -m montaigne.main synthesize \
        --output-file output/xtts_output.wav \
        --speaker-wav input/speaker.wav \
        --language en \
        --text "This is a test with XTTS. It supports [p=0.5] pauses and *emphasis*."

# Run Bark synthesis (Must be run inside `nix develop`)
bark: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🐾 Running Bark synthesis..."
    @python -m montaigne.main synthesize \
        --engine bark \
        --text "Hello from the Bark engine. It sounds different!" \
        --language en \
        --output-file output/bark_en_default.wav

# Run YouTube speaker synthesis (Must be run inside `nix develop`)
yt: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "▶️ Running XTTS with YouTube speaker..."
    @python -m montaigne.main synthesize \
        --engine xtts \
        --speaker-youtube-id "dQw4w9WgXcQ" \
        --text "Testing YouTube download." \
        --language en \
        --output-file output/yt_test.wav

# === Debugging Tasks (Run inside Nix Shell) ===
# Simple XTTS synthesis test run (CPU)
debug: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🐛 Running debug XTTS synthesis (CPU)..."
    @python -m montaigne.main synthesize \
        --output-file output/debug_output.wav \
        --speaker-wav input/speaker.wav \
        --language en \
        --text "This is a debug test [p=0.5] with *emphasis*." \
        --cpu

# Check PyTorch CUDA availability
debug_gpu:
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🐛 Checking PyTorch CUDA availability..."
    @python -c "import torch; print(f'---> Torch Version: {torch.__version__}'); print(f'---> CUDA Available: {torch.cuda.is_available()}'); print(f'---> Device Count: {torch.cuda.device_count()}')"

# === Docker Tasks ===
# Check if Docker is available and working
docker_check:
    @echo "🔍 Checking Docker setup..."
    @if ! command -v docker >/dev/null 2>&1; then \
        echo "❌ Docker command not found. Is it installed and in PATH?"; \
        exit 1; \
    fi
    @if ! docker info >/dev/null 2>&1; then \
        echo "❌ Docker daemon is not running or permission issue."; \
        echo "   Try commands like: sudo systemctl start docker"; \
        echo "                    sudo usermod -aG docker \$$USER && newgrp docker"; \
        exit 1; \
    fi
    @echo "✅ Docker is ready: $$(docker --version)"

# Check Dockerfile with hadolint (Provide hadolint via Nix or run via Docker)
hadolint_check:
    @echo "🔍 Checking Dockerfile with hadolint..."
    @# Option 1: Assume hadolint is provided by Nix Flake
    @if command -v hadolint >/dev/null 2>&1; then \
        if ! hadolint Dockerfile; then \
           echo "❌ Dockerfile linting failed using local hadolint"; exit 1; \
        fi; \
    else \
        # Option 2: Try running hadolint via Docker if local not found
        echo "⚠️ hadolint command not found, attempting to run via Docker..."; \
        if ! docker run --rm -i -v "$(pwd)/.hadolint.yaml:/.hadolint.yaml" hadolint/hadolint < Dockerfile; then \
           echo "❌ Dockerfile linting failed using Dockerized hadolint"; exit 1; \
        fi; \
    fi
    @echo "✅ Dockerfile passed linting checks."

# Prepare local TTS model for Docker build context using just variable
prepare_local_model:
    @echo "📦 Preparing local TTS model directory..."
    @mkdir -p model_files
    @echo "   Checking for model at: {{MODEL_PATH_VAR}}"
    @if [ -d "{{ MODEL_PATH_VAR }}" ]; then \
        echo '   Found local model - copying to build context (./model_files)...'; \
        # Use rsync for efficient copy, show progress
        if ! rsync -a --info=progress2 "{{ MODEL_PATH_VAR }}/" model_files/; then \
            echo '   ❌ Failed to copy local model.'; \
            # Decide if this is fatal - maybe allow build without local model?
            # exit 1; # Uncomment to make this error fatal
            echo '   ⚠️ Continuing build without pre-copied local model.'; \
        else \
            echo "   ✅ Local model copied successfully."; \
        fi; \
    else \
        echo '   ⚠️ Local model not found at "{{ MODEL_PATH_VAR }}".'; \
        echo "      If USE_LOCAL_MODEL=true is set in build args, Docker build might fail or download the model."; \
    fi

# Create Entrypoint and Modify Dockerfile
prepare_docker_files: prepare_local_model
    @echo "📝 Creating entrypoint script (entrypoint.sh)..."
    @echo '#!/bin/bash' > entrypoint.sh
    @echo '#' Generated by 'just prepare_docker_files' >> entrypoint.sh
    @echo 'set -e' >> entrypoint.sh
    @echo '' >> entrypoint.sh
    @echo '# Optional: Check PyTorch version inside container' >> entrypoint.sh
    @echo 'echo -n "---> Container PyTorch version: "' >> entrypoint.sh
    @echo '/usr/bin/python3.11 -c "import torch; print(torch.__version__)" || echo "Unavailable"' >> entrypoint.sh
    @echo '' >> entrypoint.sh
    @echo '# Execute the command passed to the container (CMD or docker run args)' >> entrypoint.sh
    @echo 'echo "🚀 Executing Docker CMD/args: $@" ' >> entrypoint.sh
    @echo 'exec "$@"' >> entrypoint.sh
    @chmod +x entrypoint.sh
    @echo "✅ Entrypoint script created."

    @echo "📝 Modifying Dockerfile to add entrypoint (if needed)..."
    @if [ ! -f "Dockerfile.bak" ]; then cp Dockerfile Dockerfile.bak; fi
    @# Check if entrypoint is already managed in the Dockerfile
    if grep -q "entrypoint.sh" Dockerfile; then \
        echo "ℹ️ Entrypoint script seems already managed by Dockerfile. Skipping modification."; \
    else \
        echo "   Appending ENTRYPOINT logic to Dockerfile..."; \
        # Use awk for safer append without creating intermediate file
        awk '1; END { \
            print ""; \
            print "# Added by '\''just prepare_docker_files'\''"; \
            print "COPY entrypoint.sh /app/entrypoint.sh"; \
            print "RUN chmod +x /app/entrypoint.sh"; \
            print "ENTRYPOINT [\"/app/entrypoint.sh\"]"; \
        }' Dockerfile > Dockerfile.new && mv Dockerfile.new Dockerfile; \
        echo "   ✅ Entrypoint added to Dockerfile."; \
    fi
    @echo "✅ Dockerfile preparation complete."

# Build Docker image with better error handling
# Usage: just docker_build USE_LOCAL_MODEL=true --no-cache
docker_build *BUILD_ARGS: docker_check hadolint_check
    @echo "🐳 Building Docker image..."
    @# Convert key=value args from just into --build-arg key=value for Docker
    _DOCKER_BUILD_ARGS=""
    _USE_LOCAL_ARG_FOUND=false
    for arg in {{BUILD_ARGS}}; do \
        if [[ "$$arg" == *=* ]]; then \
           _DOCKER_BUILD_ARGS="$${_DOCKER_BUILD_ARGS} --build-arg $$arg"; \
           if [[ "$$arg" == USE_LOCAL_MODEL* ]]; then _USE_LOCAL_ARG_FOUND=true; fi; \
        else \
           # Assume non key=value args are standard docker build flags like --no-cache
           _DOCKER_BUILD_ARGS="$${_DOCKER_BUILD_ARGS} $$arg"; \
        fi; \
    done; \
    # Prepare local model files if USE_LOCAL_MODEL=true is passed or implied
    if $_USE_LOCAL_ARG_FOUND; then \
        echo "   preparing local model required"; \
        just prepare_docker_files; \
    else \
       echo "   USE_LOCAL_MODEL not explicitly set, skipping model preparation."; \
    fi; \

    echo "   Docker Build Command: docker build $${_DOCKER_BUILD_ARGS} -t ... ."

    @# Build with all tags
    docker build \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" \
        -t "{{GHCR_TAG_LATEST}}" \
        -t "{{GHCR_TAG_COMMIT}}" \
        $${_DOCKER_BUILD_ARGS} \
        . || (echo "❌ Docker build failed" && exit 1)

    @# Add manual tag if provided via environment variable
    if [ -n "{{MANUAL_TAG}}" ]; then \
        _MANUAL_TAG_FULL="{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        echo "   Adding manual tag: $${_MANUAL_TAG_FULL}"; \
        docker tag "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" "$${_MANUAL_TAG_FULL}"; \
    fi
    @echo "✅ Docker image built successfully."

# Build with local model & entrypoint fix (calls prepare_docker_files automatically via build)
docker_dev *ARGS:
    @echo "🐳 Building Docker DEV image (local model implied, pass --no-cache etc. via ARGS)..."
    @just docker_build USE_LOCAL_MODEL=true {{ARGS}}
    # Clean up copied model files only after build is successful
    @if [ -d "model_files" ]; then rm -rf ./model_files; fi
    @echo "✅ Docker DEV build process complete."

# Push GHCR tags (Requires docker login ghcr.io)
docker_push: docker_check
    @echo "⏫ Pushing images to GHCR ({{GHCR_IMAGE_BASE}})..."
    @if [[ "{{GITHUB_OWNER_REPO}}" == "hoffmann/montaigne" ]] || [[ "{{GITHUB_OWNER_REPO}}" == "YOUR_USERNAME/YOUR_REPO" ]]; then \
        echo "⚠️ Trying to push to default/fallback repository ('{{GITHUB_OWNER_REPO}}')."; \
        echo "   Ensure GITHUB_REPOSITORY env var is set correctly if running locally (e.g., 'export GITHUB_REPOSITORY=myuser/myrepo')."; \
        # Optional: Exit here if you want to prevent pushes to fallback repo
        # exit 1; \
    fi

    @echo "   Pushing GHCR Tag: {{GHCR_TAG_LATEST}}"
    docker push "{{GHCR_TAG_LATEST}}" || (echo "❌ Push failed: {{GHCR_TAG_LATEST}}" && exit 1)
    @echo "   Pushing GHCR Tag: {{GHCR_TAG_COMMIT}}"
    docker push "{{GHCR_TAG_COMMIT}}" || (echo "❌ Push failed: {{GHCR_TAG_COMMIT}}" && exit 1)

    @if [ -n "{{MANUAL_TAG}}" ]; then \
        _GHCR_TAG_MANUAL="{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        echo "   Pushing GHCR Manual Tag: $${_GHCR_TAG_MANUAL}"; \
        docker push "$${_GHCR_TAG_MANUAL}" || (echo "❌ Push failed: $${_GHCR_TAG_MANUAL}" && exit 1); \
    fi
    @echo "✅ Images pushed to GHCR."


# Run container with proper volume mounts using absolute paths
# Ensures dummy speaker file exists for the default run
docker_run *ARGS: prepare_dirs docker_check
    @echo "🐳 Running default synthesis in Docker container..."
    @# Create dummy speaker if needed (prepare_dirs should handle this, but double-check)
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "   ⚠️ Re-creating missing dummy input/speaker.wav for Docker run..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "   ❌ Failed to create dummy speaker.wav." && exit 1); \
    fi

    _ABS_INPUT_DIR=$(realpath ./input)
    _ABS_OUTPUT_DIR=$(realpath ./output)

    echo "   Mapping host input:  $${_ABS_INPUT_DIR} -> /app/input (ro)"
    echo "   Mapping host output: $${_ABS_OUTPUT_DIR} -> /app/output (rw)"
    echo "   Using image:         {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}"
    echo "   Command + Args:    python -m montaigne.main synthesize --text ... {{ARGS}}"

    docker run --rm \
        -v "$${_ABS_INPUT_DIR}:/app/input:ro" \
        -v "$${_ABS_OUTPUT_DIR}:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        python -m montaigne.main synthesize \
        --text "This is a Docker container test run via 'just docker_run'." \
        --output-file /app/output/docker_output.wav \
        --speaker-wav /app/input/speaker.wav \
        --language en \
        {{ARGS}} || (echo "❌ Docker run failed" && exit 1)
    @echo "✅ Docker synthesis complete. Check output/docker_output.wav"

# GPU version with fixed volume paths
# Usage: just docker_run_gpu -- --some-montaigne-arg # Pass montaigne args after --
docker_run_gpu *ARGS: prepare_dirs docker_check
    @echo "🐳 Running Docker container with GPU support..."
     _ABS_INPUT_DIR=$(realpath ./input)
     _ABS_OUTPUT_DIR=$(realpath ./output)

    echo "   Mapping host input:  $${_ABS_INPUT_DIR} -> /app/input (ro)"
    echo "   Mapping host output: $${_ABS_OUTPUT_DIR} -> /app/output (rw)"
    echo "   Using image:         {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}"
    echo "   Command + Args:    python -m montaigne.main {{ARGS}}"

    docker run --rm --gpus all \
        -v "$${_ABS_INPUT_DIR}:/app/input:ro" \
        -v "$${_ABS_OUTPUT_DIR}:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        python -m montaigne.main \
        {{ARGS}} || (echo "❌ Docker GPU run failed" && exit 1)
    @echo "✅ Docker GPU run complete."


# Lint Dockerfile without building
lint_dockerfile: hadolint_check
    @echo "✅ Dockerfile linting completed."


# Generate repomix (expects to be run inside nix shell)
mix:
    @command -v repomix > /dev/null 2>&1 || (echo "❌ 'repomix' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "👾 Generating repomix..."
    @repomix .
    @echo "✅ Repomix generated."


# === Main Pipeline (Refactored) ===
# Run TTS tasks (assumes already in Nix shell)
run_tts_tasks:
    @echo "🚀 Running TTS tasks..."
    @just prepare_dirs
    @just xtts
    @just bark
    @just yt
    @echo "=== TTS Tasks Complete ==="

# Improved main pipeline with better error handling
all:
    @echo "🚀 Starting Montaigne TTS pipeline..."
    @nix develop --impure --command bash -c '''
set -e
echo "📦 Current Python environment packages:"
uv pip freeze

# Install workspace packages
echo "=== Install workspace packages ==="
echo "Installing all workspace packages at once..."
uv pip install --editable ./packages/montaigne --editable .
echo "Verifying montaigne module..."
python -c "import montaigne; print(f\"✅ Found montaigne module: {montaigne.__file__}\")"

# Run repomix
echo "=== Refresh repomix.md (using config) ==="
repomix .

# Prepare directories and run TTS tasks
just prepare_dirs

# Run TTS synthesis tasks
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

# Docker tasks
echo "=== Running Docker Tasks ==="
just prepare_docker_files || (echo "❌ Docker file preparation failed." && exit 1)

echo "Attempting Docker build with local model (using --no-cache)..."
just docker_build --no-cache --build-arg USE_LOCAL_MODEL=true || \
  (echo "❌ Docker build failed with local model, trying without local model (using --no-cache)..." && \
   just docker_build --no-cache) || \
  (echo "❌ All Docker build attempts failed." && exit 1)

echo "🐳 Running Docker test command..."
just docker_run --cpu || (echo "❌ Docker test run failed." && exit 1)
''' || (echo "❌ Pipeline failed" && exit 1)

    @echo "✅ All tasks completed successfully!"

mix:
    @repomix .

# === Workspace Management ===
#workspace_install:
#    @echo "📦 Installing all workspace packages in development mode..."
#    @uv pip install -e .
#
#workspace_add_pkg NAME:
#    @echo "📦 Creating new package {{NAME}} in workspace..."
#    @mkdir -p packages/{{NAME}}/src/{{NAME}}
#    @touch packages/{{NAME}}/src/{{NAME}}/__init__.py
#    @echo '''[project]
#name = "{{NAME}}"
#version = "0.1.0"
#description = "Add description here"
#authors = [{ name = "Matheus Hoffmann", email = "hoffmann@poli.ufrj.br" }]
#requires-python = ">=3.11,<3.12"
#dependencies = []
#
#[build-system]
#requires = ["setuptools>=61.0"]
#build-backend = "setuptools.build_meta"
# === Ubuntu TTS Tasks (CPU-Only, No Nix/Flake required) ===
# This task remains largely independent
run_tts_tasks_ubuntu_cpu:
    @echo "🚀 Running TTS tasks on Ubuntu (CPU-only, No Nix/Flake)..."
    @mkdir -p input output
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "🔊 Creating sample speaker.wav file (requires ffmpeg)..."; \
        command -v ffmpeg >/dev/null 2>&1 || (echo "❌ ffmpeg command needed but not found!" && exit 1); \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav; \
    fi

    @echo "🐍 Setting up Python virtual environment (.venv)..."
    @command -v uv >/dev/null 2>&1 || (echo "❌ uv command not found! Install uv first (e.g., pip install uv)." && exit 1)
    @uv venv .venv --seed # Create venv
    @echo "source .venv/bin/activate" > .venv/bin/activate_this.sh # Helper script hint

    @echo "📦 Installing dependencies (CPU-only PyTorch)..."
    #. .venv/bin/activate is tricky in Justfiles across lines; run uv directly targeting the venv python
    @.venv/bin/uv pip install \
        torch==2.1.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cpu \
        numpy pandas scipy \
        -e . # Install editable local project

    @echo "✨ Running TTS synthesis with CPU..."
    # Activate won't persist, so export vars and call python from venv directly
    @CUDA_VISIBLE_DEVICES="" USE_CUDA="0" FORCE_CPU="1" \
    .venv/bin/python -m montaigne.main synthesize \
        --cpu \
        --output-file output/debug_output.wav \
        --speaker-wav input/speaker.wav \
        --language en \
        --text "This is a debug test with emphasis (Ubuntu CPU)."

    @echo "✨ Running Bark synthesis with CPU..."
    @CUDA_VISIBLE_DEVICES="" USE_CUDA="0" FORCE_CPU="1" \
    .venv/bin/python -m montaigne.main synthesize \
        --engine bark \
        --cpu \
        --text "Hello from the Bark engine on Ubuntu (CPU)." \
        --language en \
        --output-file output/bark_ubuntu_test.wav

    @echo "👾 Generate repomix output..."
    # Need repomix installed in the venv or globally
    # Example: .venv/bin/uv pip install repomix # Uncomment if needed
    @.venv/bin/python -m repomix . # If repomix is installed as python module

    @echo "✅ TTS tasks completed successfully in CPU-only mode! Activate env with: source .venv/bin/activate"
