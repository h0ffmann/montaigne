# -*- mode: conf -*-

# Load environment variables from .env file if it exists
set dotenv-load := true

# Justfile for the Montaigne TTS project
# Uses Nix Flake for environment and dependency management.
# Complex logic delegated to scripts/ directory.

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
    # Pass MODEL_PATH_VAR for scripts that might need it inside nix develop (like prepare_local_model if called indirectly)
    @MODEL_PATH_VAR="{{MODEL_PATH_VAR}}" NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash scripts/nix_setup.sh

# Enter nix develop shell (user should run `just install_workspace` manually if needed)
nix_shell:
    @nix flake update
    @echo "Entering Nix develop shell..."
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure

# === Linting & Formatting (Run inside Nix Shell) ===
lint:
    ruff check --force-exclude --config=ruff.toml packages/

format:
    ruff format --force-exclude --config=ruff.toml packages/

check: format lint
    @echo "✅ Lint and format checks passed."

fix:
    ruff check packages/ --fix

# === Analysis (Run inside Nix Shell) ===
# Assuming aider-analytics is installed in the venv and runnable via `python`
analytics:
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found in Nix env." && exit 1)
    @echo "📊 Running aider-analytics script directly..."
    @python packages/aider_analytics/src/aider_analytics/main.py .

# === Testing (Run inside Nix Shell) ===
# Pytest is usually a dev dependency run via python, checking PATH is fine.
test:
    @command -v pytest > /dev/null 2>&1 || (echo "❌ 'pytest' not found. Ensure it is installed (e.g., via uv pip install -e .[test]) and you are in nix develop env." && exit 1)
    @echo "🧪 Running tests with pytest..."
    @pytest packages/montaigne/tests/ # Update test path if tests were moved

# === Cleaning ===
clean_pycache:
    @echo "🧹 Removing __pycache__ directories and .pyc files..."
    @find . \( -type d -name "__pycache__" -o -type f -name "*.py[co]" \) -delete

clean_build:
    @echo "🧹 Removing build artifacts..."
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/ model_files/ entrypoint.sh Dockerfile.bak .venv/
    @echo "   (Note: Scripts in scripts/ dir are not removed by clean)"

clean: clean_pycache clean_build
    @echo "✅ Project directories cleaned."

# === TTS Tasks (Run inside Nix Shell) ===
# Simple python/ffmpeg calls, kept inline
prepare_dirs:
    @echo "📁 Preparing directories and sample audio..."
    @mkdir -p input output
    @command -v ffmpeg > /dev/null 2>&1 || (echo "❌ 'ffmpeg' not found in Nix env." && exit 1)
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ Creating sample speaker.wav file..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "❌ Failed to create speaker.wav." && exit 1); \
    fi

xtts: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found in Nix env." && exit 1)
    @echo "✨ Running XTTS synthesis..."
    @python -m montaigne.main synthesize \
        --output-file output/xtts_output.wav \
        --speaker-wav input/speaker.wav \
        --language en \
        --text "This is a test with XTTS."

bark: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found in Nix env." && exit 1)
    @echo "🐾 Running Bark synthesis..."
    @python -m montaigne.main synthesize \
        --engine bark \
        --text "Hello from the Bark engine." \
        --language en \
        --output-file output/bark_en_default.wav

yt: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found in Nix env." && exit 1)
    @echo "▶️ Running XTTS with YouTube speaker..."
    @python -m montaigne.main synthesize \
        --engine xtts \
        --speaker-youtube-id "dQw4w9WgXcQ" \
        --text "Testing YouTube download." \
        --language en \
        --output-file output/yt_test.wav

# === Debugging Tasks (Run inside Nix Shell) ===
# Simple python calls, kept inline
debug: prepare_dirs
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found in Nix env." && exit 1)
    @echo "🐛 Running debug XTTS synthesis (CPU)..."
    @python -m montaigne.main synthesize \
        --output-file output/debug_output.wav \
        --speaker-wav input/speaker.wav \
        --language en \
        --text "This is a debug test with *emphasis*." \
        --cpu

debug_gpu:
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' not found in Nix env." && exit 1)
    @echo "🐛 Checking PyTorch CUDA availability..."
    @python -c "import torch; print(f'---> Torch Version: {torch.__version__}\n---> CUDA Available: {torch.cuda.is_available()}\n---> Device Count: {torch.cuda.device_count()}')"

# === Docker Tasks ===
# Simple check, keep inline
docker_check:
    @echo "🔍 Checking Docker setup..."
    @if ! command -v docker >/dev/null 2>&1; then \
        echo "❌ Docker command not found. Is it installed and in PATH?"; exit 1; \
    fi
    @if ! docker info >/dev/null 2>&1; then \
        echo "❌ Docker daemon is not running or permission issue."; \
        echo "   Try: sudo systemctl start docker && sudo usermod -aG docker \$$USER && newgrp docker"; exit 1; \
    fi
    @echo "✅ Docker is ready: $$(docker --version)"

# Uses external script for Docker fallback for hadolint
hadolint_check:
    @echo "🔍 Checking Dockerfile with hadolint..."
    @if command -v hadolint >/dev/null 2>&1; then \
        echo "   Using local hadolint (from Nix env)..."; \
        hadolint Dockerfile || { echo "❌ Local hadolint check failed."; exit 1; }; \
    else \
        bash scripts/hadolint_docker.sh || exit 1; \
    fi
    @echo "✅ Dockerfile passed linting checks."

# Delegate to scripts, passing MODEL_PATH_VAR explicitly
prepare_local_model:
    @MODEL_PATH_VAR="{{MODEL_PATH_VAR}}" bash scripts/prepare_local_model.sh || exit 1

prepare_docker_files: prepare_local_model # Run model prep first
    bash scripts/prepare_docker_files.sh || exit 1

docker_build *BUILD_FLAGS_AND_ARGS: docker_check hadolint_check
    # Ensure docker files are ready (run prepare_docker_files before this task if needed)
    # Pass needed variables as environment variables PRECEDING the command
    @MODEL_PATH_VAR="{{MODEL_PATH_VAR}}" \
     DOCKER_IMAGE_NAME="{{DOCKER_IMAGE_NAME}}" \
     DOCKER_TAG_LATEST="{{DOCKER_TAG_LATEST}}" \
     DOCKER_TAG_GIT="{{DOCKER_TAG_GIT}}" \
     GITHUB_OWNER_REPO="{{GITHUB_OWNER_REPO}}" \
     GHCR_IMAGE_BASE="{{GHCR_IMAGE_BASE}}" \
     GHCR_TAG_LATEST="{{GHCR_TAG_LATEST}}" \
     GHCR_TAG_COMMIT="{{GHCR_TAG_COMMIT}}" \
     MANUAL_TAG="{{MANUAL_TAG}}" \
     bash scripts/build_docker.sh {{BUILD_FLAGS_AND_ARGS}} || exit 1

# Call prepare script first, then build script
docker_dev *ARGS:
    @echo "🐳 Building Docker DEV image (local model requested)..."
    @just prepare_docker_files || exit 1 # Prepare step first
    @just docker_build USE_LOCAL_MODEL=true {{ARGS}} # Then build
    @if [ -d "model_files" ]; then echo "   Cleaning up ./model_files..."; rm -rf ./model_files; fi
    @echo "✅ Docker DEV build process complete."

docker_push: docker_check
    # Pass needed variables as environment variables PRECEDING the command
    @GITHUB_OWNER_REPO="{{GITHUB_OWNER_REPO}}" \
     GHCR_IMAGE_BASE="{{GHCR_IMAGE_BASE}}" \
     GHCR_TAG_LATEST="{{GHCR_TAG_LATEST}}" \
     GHCR_TAG_COMMIT="{{GHCR_TAG_COMMIT}}" \
     MANUAL_TAG="{{MANUAL_TAG}}" \
     bash scripts/push_docker.sh || exit 1

# Run container - Simplified using direct realpath and single docker run
docker_run *ARGS: prepare_dirs docker_check
    @echo "🐳 Running default synthesis in Docker container..."
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "   ⚠️ Re-creating missing dummy input/speaker.wav..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        { echo "   ❌ Failed to create dummy speaker.wav."; exit 1; }; \
    fi
    @echo "   Mapping host input:  $(realpath ./input) -> /app/input (ro)"
    @echo "   Mapping host output: $(realpath ./output) -> /app/output (rw)"
    @echo "   Using image:         {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}"
    @echo "   Command + Args:    python -m montaigne.main synthesize --text ... {{ARGS}}"
    @docker run --rm \
        -v "$(realpath ./input):/app/input:ro" \
        -v "$(realpath ./output):/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        python -m montaigne.main synthesize \
        --text "Docker container test run via 'just docker_run'." \
        --output-file /app/output/docker_output.wav \
        --speaker-wav /app/input/speaker.wav \
        --language en \
        {{ARGS}} || { echo "❌ Docker run failed"; exit 1; }
    @echo "✅ Docker synthesis complete. Check output/docker_output.wav"

docker_run_gpu *ARGS: prepare_dirs docker_check
    @echo "🐳 Running Docker container with GPU support..."
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "   ⚠️ Re-creating missing dummy input/speaker.wav..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        { echo "   ❌ Failed to create dummy speaker.wav."; exit 1; }; \
    fi
    @echo "   Mapping host input:  $(realpath ./input) -> /app/input (ro)"
    @echo "   Mapping host output: $(realpath ./output) -> /app/output (rw)"
    @echo "   Using image:         {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}"
    @echo "   Command + Args:    python -m montaigne.main {{ARGS}}"
    @docker run --rm --gpus all \
        -v "$(realpath ./input):/app/input:ro" \
        -v "$(realpath ./output):/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        python -m montaigne.main \
        {{ARGS}} || { echo "❌ Docker GPU run failed"; exit 1; }
    @echo "✅ Docker GPU run complete."

lint_dockerfile: hadolint_check # Alias for clarity
    @echo "✅ Dockerfile linting step completed."

# Generate repomix (Simple command, keep inline)
mix:
    @command -v repomix > /dev/null 2>&1 || \
     (echo "❌ 'repomix' not found. Is it in Nix packages or installable via uv tool run?"; exit 1)
    @echo "👾 Generating repomix..."
    # Decide how repomix is run: directly (if in Nix PATH) or via uv?
    @repomix .
    # Alternative: @{{UV}} tool run repomix -- .
    @echo "✅ Repomix generated."

# === Individual TTS Tasks (Run inside Nix Shell) ===
# These are called by run_nix_tts_tasks or the 'all' pipeline script
run_nix_tts_tasks: prepare_dirs xtts bark yt
    @echo "✅ All Nix TTS tasks completed."

# === Main Pipeline (Refactored - Recommended) ===
all:
    @echo "🚀 Starting Montaigne TTS CI Pipeline (Refactored Flow)..."
    # === Step 1: Run Nix environment tasks via script ===
    @echo "[Step 1/3] Setting up Nix environment and running Python tasks via script..."
    # This script should internally use `just check`, `just mix` etc.
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash scripts/run_nix_tasks.sh \
        || { echo "❌ Pipeline failed during Nix environment tasks script."; exit 1; }

    # === Step 2: Run Docker build tasks on host ===
    @echo "[Step 2/3] Running Docker build tasks on host..."
    @just docker_check || exit 1
    @just lint_dockerfile || exit 1
    @echo "   Preparing Docker files for build..."
    @just prepare_docker_files || exit 1
    @echo "   Attempting Docker build (trying local model first, --no-cache)..."
    @just docker_build USE_LOCAL_MODEL=true --no-cache || \
      (echo "   ⚠️ Build with local model failed, retrying without..."; \
       just docker_build --no-cache ) || \
      { echo "❌ All Docker build attempts failed."; exit 1; }
    @echo "✅ Docker build successful."

    # === Step 3: Run Docker test command (inside Nix env to ensure ffmpeg for prepare_dirs) ===
    @echo "[Step 3/3] Running Docker test command (CPU) inside Nix env..."
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure --command bash -c "just docker_run --cpu" || { echo "❌ Docker test run failed."; exit 1; }
    @echo "✅ Docker test run successful."

    # Optional Cleanup
    @echo "🧹 Cleaning up Docker build artifacts (optional)..."
    @if [ -d "model_files" ]; then rm -rf ./model_files; fi
    @if [ -f "entrypoint.sh" ]; then rm ./entrypoint.sh; fi

    @echo ""
    @echo "✅✅✅ Montaigne TTS pipeline ('just all') completed successfully! ✅✅✅"

# === Ubuntu TTS Tasks (CPU-Only, No Nix/Flake required) ===
run_tts_tasks_ubuntu_cpu:
    @echo "🚀 Running Ubuntu CPU TTS tasks via external script..."
    bash scripts/run_ubuntu_cpu_tasks.sh || exit 1

# Removed all_original_flow task as it was complex and less preferred
# Removed workspace_add_pkg task
