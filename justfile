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
    @command -v {{UV}} > /dev/null 2>&1 || (echo "❌ '{{UV}}' command not found. Are you inside 'nix develop'?" && exit 1)
    @{{UV}} pip install -e . --verbose
    @echo "✅ Workspace packages installed."

setup: install_workspace # Alias

# Update flake and enter nix shell, running the setup script inside
nix_setup:
    @nix flake update
    @echo "Entering Nix shell and setting up workspace..."
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash scripts/nix_setup_script.sh

# Enter nix develop shell (user should run `just install_workspace` manually if needed)
nix_shell:
    @nix flake update
    @echo "Entering Nix develop shell..."
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

# === Analysis (Run inside Nix Shell) ===
# Assuming aider-analytics is a tool available in the Nix env
analytics:
    @command -v aider-analytics > /dev/null 2>&1 || (echo "❌ 'aider-analytics' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "📊 Running commit analysis..."
    @aider-analytics .

# === Testing (Run inside Nix Shell) ===
test:
    @command -v pytest > /dev/null 2>&1 || (echo "❌ 'pytest' not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🧪 Running tests with pytest..."
    # Ensure this path points to your tests correctly
    @pytest packages/montaigne/tests/

# === Cleaning ===
clean_pycache:
    @echo "🧹 Removing __pycache__ directories and .pyc files..."
    @find . \( -type d -name "__pycache__" -o -type f -name "*.py[co]" \) -delete

clean_build:
    @echo "🧹 Removing build artifacts..."
    # Add _*.sh from root if old temp files might still exist
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/ model_files/ entrypoint.sh Dockerfile.bak .venv/ _nix_ci_script_orig.sh

clean: clean_pycache clean_build
    @echo "✅ Project directories cleaned."

# === TTS Tasks (Run inside Nix Shell) ===
# Create input/output dirs and sample audio if needed
prepare_dirs:
    @echo "📁 Preparing directories and sample audio..."
    @mkdir -p input output
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
        @bash scripts/run_hadolint_docker.sh || exit 1; \
    fi
    @echo "✅ Dockerfile passed linting checks."

# Prepare local TTS model for Docker build context using just variable
prepare_local_model:
    @echo "📦 Preparing local TTS model directory..."
    @mkdir -p model_files
    @echo "   Checking for model at: {{MODEL_PATH_VAR}}"
    @if [ -d "{{ MODEL_PATH_VAR }}" ]; then \
        echo '   Found local model - copying to build context (./model_files)...'; \
        if ! rsync -a --info=progress2 "{{ MODEL_PATH_VAR }}/" model_files/; then \
            echo '   ❌ Failed to copy local model.'; \
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
    @printf '%s\n' \
        '#!/bin/bash' \
        '# Generated by '\''just prepare_docker_files'\''' \
        'set -e' \
        '' \
        '# Optional: Check PyTorch version inside container' \
        'echo -n "---> Container PyTorch version: "' \
        '/usr/bin/python3.11 -c "import torch; print(torch.__version__)" || echo "Unavailable"' \
        '' \
        '# Execute the command passed to the container (CMD or docker run args)' \
        'echo "🚀 Executing Docker CMD/args: $@" ' \
        'exec "$@"' > entrypoint.sh
    @chmod +x entrypoint.sh
    @echo "✅ Entrypoint script created."

    @echo "📝 Modifying Dockerfile to add entrypoint (if needed)..."
    @if [ ! -f "Dockerfile.bak" ]; then cp Dockerfile Dockerfile.bak; fi
    @if grep -q "entrypoint.sh" Dockerfile; then \
        echo "ℹ️ Entrypoint script seems already managed by Dockerfile. Skipping modification."; \
    else \
        echo "   Appending ENTRYPOINT logic to Dockerfile..."; \
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
docker_build *BUILD_FLAGS_AND_ARGS: docker_check hadolint_check
    @echo "🐳 Building Docker image..."
    _DOCKER_BUILD_ARGS=""
    _DOCKER_FLAGS=""
    _USE_LOCAL_ARG_FOUND=false

    for arg in {{BUILD_FLAGS_AND_ARGS}}; do
        if [[ "$arg" == *=* ]]; then
           _DOCKER_BUILD_ARGS="$${_DOCKER_BUILD_ARGS} --build-arg $arg"
           if [[ "$arg" == USE_LOCAL_MODEL=true ]]; then _USE_LOCAL_ARG_FOUND=true; fi
        else
           _DOCKER_FLAGS="$${_DOCKER_FLAGS} $arg"
        fi
    done

    # Prepare step is now assumed run externally by caller (e.g., `all` or `docker_dev`)
    if $_USE_LOCAL_ARG_FOUND; then
        echo "   Build argument USE_LOCAL_MODEL=true found. Ensure 'prepare_docker_files' was run."
    else
        echo "   Build argument USE_LOCAL_MODEL=true not found. Ensure 'prepare_docker_files' was run if entrypoint needed."
    fi

    echo "   Docker Build Flags: $${_DOCKER_FLAGS}"
    echo "   Docker Build Args: $${_DOCKER_BUILD_ARGS}"
    echo "   Docker Build Command: docker build $${_DOCKER_FLAGS} $${_DOCKER_BUILD_ARGS} -t ... ."

    # Build with all tags
    docker build \
        $${_DOCKER_FLAGS} \
        $${_DOCKER_BUILD_ARGS} \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" \
        -t "{{GHCR_TAG_LATEST}}" \
        -t "{{GHCR_TAG_COMMIT}}" \
        . || (echo "❌ Docker build failed" && exit 1)

    if [ -n "{{MANUAL_TAG}}" ]; then \
        _MANUAL_TAG_FULL="{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        echo "   Adding manual tag: $${_MANUAL_TAG_FULL}"; \
        docker tag "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" "$${_MANUAL_TAG_FULL}"; \
    fi
    @echo "✅ Docker image built successfully."

# Build with local model & entrypoint fix.
docker_dev *ARGS:
    @echo "🐳 Building Docker DEV image (local model requested)..."
    @just prepare_docker_files || exit 1 # Prepare step first
    @just docker_build USE_LOCAL_MODEL=true {{ARGS}} # Then build
    @if [ -d "model_files" ]; then echo "   Cleaning up ./model_files..."; rm -rf ./model_files; fi
    @echo "✅ Docker DEV build process complete."

# Push GHCR tags (Requires docker login ghcr.io)
docker_push: docker_check
    @echo "⏫ Pushing images to GHCR ({{GHCR_IMAGE_BASE}})..."
    @if [[ "{{GITHUB_OWNER_REPO}}" == "hoffmann/montaigne" || "{{GITHUB_OWNER_REPO}}" == "YOUR_USERNAME/YOUR_REPO" ]]; then \
        echo "⚠️ Trying to push to default/fallback repository ('{{GITHUB_OWNER_REPO}}')."; \
        echo "   Ensure GITHUB_REPOSITORY env var is set correctly if running locally."; \
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
docker_run *ARGS: prepare_dirs docker_check
    @echo "🐳 Running default synthesis in Docker container..."
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "   ⚠️ Re-creating missing dummy input/speaker.wav for Docker run..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "   ❌ Failed to create dummy speaker.wav." && exit 1); \
    fi

    _ABS_INPUT_DIR=$$(realpath ./input)
    _ABS_OUTPUT_DIR=$$(realpath ./output)

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
docker_run_gpu *ARGS: prepare_dirs docker_check
    @echo "🐳 Running Docker container with GPU support..."
     _ABS_INPUT_DIR=$$(realpath ./input)
     _ABS_OUTPUT_DIR=$$(realpath ./output)

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

# === Main Pipeline (Refactored - Recommended) ===
# Separates Nix environment tasks from host (Docker) tasks using external script.
all:
    @echo "🚀 Starting Montaigne TTS CI Pipeline (Refactored Flow)..."

    # === Step 1: Run tasks requiring the Nix environment via script ===
    @echo "[Step 1/3] Setting up Nix environment and running Python tasks via script..."
    # Execute the dedicated script within nix develop
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash scripts/run_nix_tasks.sh \
        || (echo "❌ Pipeline failed during Nix environment tasks script." && exit 1)

    # === Step 2: Run Docker build tasks (outside Nix env, interacting with host Docker) ===
    @echo "[Step 2/3] Running Docker build tasks on host..."
    @just docker_check || exit 1
    @just lint_dockerfile || exit 1
    @echo "   Preparing Docker files for build..."
    @just prepare_docker_files || exit 1
    @echo "   Attempting Docker build (trying with local model first, --no-cache)..."
    @just docker_build USE_LOCAL_MODEL=true --no-cache || \
      (echo "   ⚠️ Build with local model failed, retrying without USE_LOCAL_MODEL=true..."; \
       just docker_build --no-cache ) || \
      (echo "❌ All Docker build attempts failed." && exit 1)
    @echo "✅ Docker build successful."

    # === Step 3: Run Docker test command (outside Nix env, using host Docker) ===
    @echo "[Step 3/3] Running Docker test command (CPU) on host..."
    @just docker_run --cpu || (echo "❌ Docker test run failed." && exit 1)
    @echo "✅ Docker test run successful."

    # Optional Cleanup after successful pipeline run on the host
    @echo "🧹 Cleaning up Docker build artifacts (optional)..."
    @if [ -d "model_files" ]; then rm -rf ./model_files; fi
    @if [ -f "entrypoint.sh" ]; then rm ./entrypoint.sh; fi

    @echo ""
    @echo "✅✅✅ Montaigne TTS pipeline ('just all') completed successfully! ✅✅✅"


# === Main Pipeline (Original Flow - Optional - Using External Script) ===
# This version uses the external script containing nested just calls etc.
all_original_flow:
    @echo "🚀 Starting Montaigne TTS pipeline (Original Flow - Using External Script)..."
    @# Execute the specific script for this flow within nix develop
    @echo "   Executing original flow script within Nix environment..."
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash scripts/run_nix_tasks_original_flow.sh \
        || (echo "❌ Pipeline execution 'all_original_flow' within Nix environment failed." && exit 1)
    @echo "✅ All tasks in 'all_original_flow' completed successfully!"

# === Ubuntu TTS Tasks (CPU-Only, No Nix/Flake required - Using External Script) ===
run_tts_tasks_ubuntu_cpu:
    @echo "🚀 Running Ubuntu CPU TTS tasks via external script..."
    @bash scripts/run_ubuntu_cpu_tasks.sh || exit 1