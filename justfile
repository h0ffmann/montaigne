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
    # Add specific editable paths if `.` doesn't capture everything reliably.
    # Example: @{{UV}} pip install -e ./packages/montaigne -e . --verbose
    @{{UV}} pip install -e . --verbose
    @echo "✅ Workspace packages installed."

setup: install_workspace # Alias

# Update flake and enter nix shell, then install workspace packages
nix_setup:
    @nix flake update
    @echo "Entering Nix shell and setting up workspace..."
    # Use --command to execute setup steps *within* the environment
    # Add NIXPKGS_ALLOW_BROKEN=1 if needed by your flake dependencies
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash -c ' \
        set -e; \
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
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/ model_files/ entrypoint.sh Dockerfile.bak .venv/

clean: clean_pycache clean_build
    @echo "✅ Project directories cleaned."

# Note: clean_all was identical to clean, removed alias for simplicity unless intended differently.
# clean_all: clean
#     @echo "✅ Full clean completed."

# === TTS Tasks (Run inside Nix Shell) ===
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
        # Ensure .hadolint.yaml exists or remove the volume mount if not used
        _HADOLINT_CMD="docker run --rm -i"; \
        if [ -f ".hadolint.yaml" ]; then _HADOLINT_CMD="$${_HADOLINT_CMD} -v \"$(pwd)/.hadolint.yaml:/.hadolint.yaml\""; fi; \
        _HADOLINT_CMD="$${_HADOLINT_CMD} hadolint/hadolint < Dockerfile"; \
        if ! eval $${_HADOLINT_CMD}; then \
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
    @# Using printf for potentially better cross-shell compatibility than echo lines
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
# Pass build flags like --no-cache directly. Pass build args as VAR=value.
docker_build *BUILD_FLAGS_AND_ARGS: docker_check hadolint_check
    @echo "🐳 Building Docker image..."
    _DOCKER_BUILD_ARGS=""
    _DOCKER_FLAGS=""
    _USE_LOCAL_ARG_FOUND=false
    _PREPARE_DONE=false

    # Separate flags (like --no-cache) from build-args (KEY=value)
    for arg in {{BUILD_FLAGS_AND_ARGS}}; do
        if [[ "$arg" == *=* ]]; then
           _DOCKER_BUILD_ARGS="$${_DOCKER_BUILD_ARGS} --build-arg $arg"
           if [[ "$arg" == USE_LOCAL_MODEL=true ]]; then _USE_LOCAL_ARG_FOUND=true; fi
        else
           _DOCKER_FLAGS="$${_DOCKER_FLAGS} $arg"
        fi
    done

    # Prepare local model files only if USE_LOCAL_MODEL=true is passed
    if $_USE_LOCAL_ARG_FOUND && ! $_PREPARE_DONE; then
        echo "   Build argument USE_LOCAL_MODEL=true found, preparing local files..."
        just prepare_docker_files
        _PREPARE_DONE=true # Avoid running twice if called via docker_dev
    else
       echo "   Build argument USE_LOCAL_MODEL=true not found, skipping model preparation step in build."
       # Ensure entrypoint exists even if model isn't copied (useful for consistency)
       if [ ! -f entrypoint.sh ]; then just prepare_docker_files; _PREPARE_DONE=true; fi
    fi

    echo "   Docker Build Flags: $${_DOCKER_FLAGS}"
    echo "   Docker Build Args: $${_DOCKER_BUILD_ARGS}"
    echo "   Docker Build Command: docker build $${_DOCKER_FLAGS} $${_DOCKER_BUILD_ARGS} -t ... ."

    @# Build with all tags
    # Need to run the actual docker build command now using the processed args/flags
    docker build \
        $${_DOCKER_FLAGS} \
        $${_DOCKER_BUILD_ARGS} \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" \
        -t "{{GHCR_TAG_LATEST}}" \
        -t "{{GHCR_TAG_COMMIT}}" \
        . || (echo "❌ Docker build failed" && exit 1)

    @# Add manual tag if provided via environment variable
    if [ -n "{{MANUAL_TAG}}" ]; then \
        _MANUAL_TAG_FULL="{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        echo "   Adding manual tag: $${_MANUAL_TAG_FULL}"; \
        docker tag "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" "$${_MANUAL_TAG_FULL}"; \
    fi
    @echo "✅ Docker image built successfully."

# Build with local model & entrypoint fix. Passes ARGS (like --no-cache) to docker_build
docker_dev *ARGS:
    @echo "🐳 Building Docker DEV image (local model requested)..."
    # Adds USE_LOCAL_MODEL=true and forwards any other flags/args
    @just docker_build USE_LOCAL_MODEL=true {{ARGS}}
    # Clean up copied model files only after successful build triggered by this task
    # Avoid cleaning if build failed or if run via `just docker_build USE_LOCAL_MODEL=true` directly
    @if [ -d "model_files" ]; then echo "   Cleaning up ./model_files..."; rm -rf ./model_files; fi
    @echo "✅ Docker DEV build process complete."

# Push GHCR tags (Requires docker login ghcr.io)
docker_push: docker_check
    @echo "⏫ Pushing images to GHCR ({{GHCR_IMAGE_BASE}})..."
    # Added more robust check for default repo value
    @if [[ "{{GITHUB_OWNER_REPO}}" == "hoffmann/montaigne" || "{{GITHUB_OWNER_REPO}}" == "YOUR_USERNAME/YOUR_REPO" ]]; then \
        echo "⚠️ Trying to push to default/fallback repository ('{{GITHUB_OWNER_REPO}}')."; \
        echo "   Ensure GITHUB_REPOSITORY env var is set correctly if running locally (e.g., 'export GITHUB_REPOSITORY=myuser/myrepo')."; \
        # exit 1; # Optional: Uncomment to prevent pushes to fallback repo
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
# Usage: just docker_run -- --device=cpu --some-other-arg
docker_run *ARGS: prepare_dirs docker_check
    @echo "🐳 Running default synthesis in Docker container..."
    @# Re-create dummy speaker only if absolutely missing
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "   ⚠️ Re-creating missing dummy input/speaker.wav for Docker run..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "   ❌ Failed to create dummy speaker.wav." && exit 1); \
    fi

    # Using subshell for assignment avoids polluting `just`'s env if script fails
    _ABS_INPUT_DIR=$$(realpath ./input)
    _ABS_OUTPUT_DIR=$$(realpath ./output)

    echo "   Mapping host input:  $${_ABS_INPUT_DIR} -> /app/input (ro)"
    echo "   Mapping host output: $${_ABS_OUTPUT_DIR} -> /app/output (rw)"
    echo "   Using image:         {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}"
    echo "   Command + Args:    python -m montaigne.main synthesize --text ... {{ARGS}}"

    # Pass ARGS to the python script inside the container
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
     _ABS_INPUT_DIR=$$(realpath ./input)
     _ABS_OUTPUT_DIR=$$(realpath ./output)

    echo "   Mapping host input:  $${_ABS_INPUT_DIR} -> /app/input (ro)"
    echo "   Mapping host output: $${_ABS_OUTPUT_DIR} -> /app/output (rw)"
    echo "   Using image:         {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}"
    # Assuming the default CMD is desired, passing ARGS directly to montaigne.main
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

# === Main Pipeline (Integrates User's Original Logic Flow) ===
# This version attempts to mirror the sequence from the user's original `all` task,
# running everything inside `nix develop -c`, including nested `just` calls for Docker.
# WARNING: Nested `just` calls inside `nix develop -c` can be fragile. See `all_refactored` below for an alternative.
all_original_flow:
    @echo "🚀 Starting Montaigne TTS pipeline (Original Flow)..."
    # NIXPKGS_ALLOW_BROKEN=1 might be needed depending on your flake inputs
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash -c '''
set -e # Exit script on first error within the bash sub-process

echo "--- [Nix Env] Check Environment ---"
echo "🐍 Python: $(python --version)"
echo "📦 UV: $(uv --version)"
echo "🐍 PyTorch check:"
python -c "import torch; print(f\"  Version: {torch.__version__}, CUDA Available: {torch.cuda.is_available()}\")" || echo "  PyTorch check failed or not installed yet."

echo "--- [Nix Env] Install/Update Workspace Packages ---"
# Using uv directly is often more reliable than calling `just install_workspace` nested here
uv pip install -e . --verbose
# Verify montaigne can be imported after install
echo "Verifying montaigne module..."
python -c "import montaigne; print(f\"✅ Found montaigne module: {montaigne.__file__}\")"

echo "--- [Nix Env] Generate Repomix ---"
# Requires repomix to be in the nix shell environment
repomix .

echo "--- [Nix Env] Prepare Directories & Run TTS Tasks ---"
# Calling `just` here assumes it's usable within the nix-develop -c subshell env
just prepare_dirs
# Running python directly is safer than nested `just` if Python env is the goal
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

# Docker tasks executed from within the Nix shell environment
# This relies on Docker client being accessible and correctly configured
# AND `just` being callable from within this subshell.
echo "--- [Nix Env -> Host Docker] Running Docker Tasks ---"
# Ensure docker CLI works from here if needed (it uses host daemon)
docker --version

# Prepare docker files (might copy models, create entrypoint)
echo "Preparing Docker files (via nested just)..."
just prepare_docker_files || { echo "❌ Docker file preparation failed."; exit 1; }

echo "Building Docker image (via nested just - trying local model first)..."
# Using `just` for build. Pass --no-cache and USE_LOCAL_MODEL=true as args.
# Use `command just ...` to make absolutely sure it finds `just` if PATH issues exist
command just docker_build USE_LOCAL_MODEL=true --no-cache || \
  { echo "   ⚠️ Docker build with local model failed, trying without local model..."; \
    command just docker_build --no-cache ; } || \
  { echo "❌ All Docker build attempts failed."; exit 1; }

echo "Running Docker test command (via nested just)..."
# Run docker container using CPU
command just docker_run --cpu || { echo "❌ Docker test run failed."; exit 1; }

echo "--- [Nix Env] Tasks Completed ---"
''' || (echo "❌ Pipeline execution within Nix environment failed." && exit 1)

    @echo "✅ All tasks in 'all_original_flow' completed successfully!"


# === Main Pipeline (Refactored - Recommended) ===
# Separates Nix environment tasks from host (Docker) tasks.
all: # Renamed from all_refactored to become the default 'all'
    @echo "🚀 Starting Montaigne TTS CI Pipeline (Refactored Flow)..."

    # === Step 1: Run tasks requiring the Nix environment ===
    @echo "[Step 1/3] Setting up Nix environment and running Python tasks..."
    # Use NIXPKGS_ALLOW_BROKEN=1 if required by your flake.
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash -c '''
set -e # Exit script on first error

echo "--- [Nix Env] Installing Workspace Packages ---"
# Call the dedicated workspace install task (uses uv)
just install_workspace

echo "--- [Nix Env] Running Linter and Formatter Checks ---"
just check

# Run tests (Optional, can be slow - uncomment if needed in main pipeline)
# echo "--- [Nix Env] Running Pytests ---"
# just test || { echo "❌ Tests failed"; exit 1; }

echo "--- [Nix Env] Generating Repomix ---"
just mix

echo "--- [Nix Env] Preparing Directories ---"
just prepare_dirs

echo "--- [Nix Env] Running TTS Synthesis Tasks ---"
just xtts
just bark
just yt

echo "--- [Nix Env] Tasks Completed Successfully ---"
''' || (echo "❌ Pipeline failed during Nix environment tasks." && exit 1)

    # === Step 2: Run Docker build tasks (outside Nix env, interacting with host Docker) ===
    @echo "[Step 2/3] Running Docker build tasks on host..."
    # Ensure docker is ready on the host
    @just docker_check || exit 1
    # Lint Dockerfile on the host
    @just lint_dockerfile || exit 1
    # Prepare Docker files (copy model locally, create entrypoint) on the host
    # Note: prepare_docker_files is called implicitly by `docker_build USE_LOCAL_MODEL=true` if needed
    # @just prepare_docker_files || exit 1 # Explicit call not needed due to build logic
    # Attempt build with local model, then fallback (pass --no-cache if desired for CI)
    @echo "   Attempting Docker build (trying with local model first, --no-cache)..."
    @just docker_build USE_LOCAL_MODEL=true --no-cache || \
      (echo "   ⚠️ Build with local model failed, retrying without USE_LOCAL_MODEL=true (still --no-cache)..."; \
       just docker_build --no-cache ) || \
      (echo "❌ All Docker build attempts failed." && exit 1)
    @echo "✅ Docker build successful."

    # === Step 3: Run Docker test command (outside Nix env, using host Docker) ===
    @echo "[Step 3/3] Running Docker test command (CPU)..."
    # Uses docker_run which calls prepare_dirs again (harmless) and docker_check
    @just docker_run --cpu || (echo "❌ Docker test run failed." && exit 1)
    @echo "✅ Docker test run successful."

    # Optional Cleanup after successful pipeline
    # @echo "🧹 Cleaning up build artifacts (optional)..."
    # @rm -rf ./model_files ./entrypoint.sh

    @echo ""
    @echo "✅✅✅ Montaigne TTS pipeline ('just all') completed successfully! ✅✅✅"


# Workspace commands removed as they are complex and often better handled manually
# or via dedicated project scaffolding tools. Keeping focus on uv install.

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

    @echo "🐍 Setting up Python virtual environment (.venv) using UV..."
    @command -v uv >/dev/null 2>&1 || (echo "❌ uv command not found! Install uv first (e.g., pip install uv)." && exit 1)
    @uv venv .venv --seed # Create venv
    # Note: Activating venv in Justfile scripts is tricky. Direct calls below are safer.
    # Consider adding a message: echo "ℹ️ Run 'source .venv/bin/activate' to activate the environment manually."

    @echo "📦 Installing dependencies (CPU-only PyTorch)..."
    # Use uv binary from the created venv to install into it
    @.venv/bin/uv pip install \
        torch==2.1.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cpu \
        numpy pandas scipy \
        -e . # Install editable local project into venv

    @echo "✨ Running TTS synthesis with CPU..."
    # Force CPU mode via env vars and call python from venv directly
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
    # Ensure repomix is installed in the venv first if not globally available
    # Example: .venv/bin/uv pip install repomix
    @.venv/bin/python -m repomix . # Assuming repomix installed as module

    @echo "✅ TTS tasks completed successfully in CPU-only mode! Activate env with: source .venv/bin/activate"
