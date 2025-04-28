# -*- mode: conf -*-

# Load environment variables from .env file if it exists
set dotenv-load := true

# Justfile for the Montaigne TTS project
# Uses Nix Flake for environment and dependency management.

# === Variables ===
PROJECT_NAME := "montaigne" # Should match pyproject.toml
# VENV_DIR and PYTHON are no longer needed as Nix manages the environment
UV           := "uv" # Keep uv command available if needed for other tasks

# === Default Task ===
# List available recipes by default
default:
    @just --list

# === Environment & Dependencies (Managed by Nix Flake) ===

# Setup/Install - Dependencies are now managed by the Nix flake
install:
    @echo "🐍 Python dependencies are managed by the Nix flake."
    @echo "✅ Environment should be ready when inside 'nix develop'."

# Alias for setup
setup: install


nix:
    @nix flake update
    @NIXPKGS_ALLOW_BROKEN=1 nix develop --impure


# === Linting & Formatting (using Ruff from Nix env) ===

# Run Ruff linter
lint:
    @# Check if ruff is available in the Nix shell
    @command -v ruff > /dev/null 2>&1 || (echo "❌ 'ruff' command not found. Is it included in flake.nix and are you inside 'nix develop'?" && exit 1)
    @echo "✨ Running Ruff linter..."
    @ruff check .

# Run Ruff formatter
format:
    @# Check if ruff is available in the Nix shell
    @command -v ruff > /dev/null 2>&1 || (echo "❌ 'ruff' command not found. Is it included in flake.nix and are you inside 'nix develop'?" && exit 1)
    @echo "🎨 Running Ruff formatter..."
    @ruff format .

# Run both linter and formatter
check: lint format
    @echo "✅ Lint and format checks passed."

# === Testing (using Pytest from Nix env) ===

# Run tests using pytest (assumes tests are in tests/)
test:
    @# Check if pytest is available in the Nix shell
    @command -v pytest > /dev/null 2>&1 || (echo "❌ 'pytest' command not found. Is it included in flake.nix and are you inside 'nix develop'?" && exit 1)
    @echo "🧪 Running tests with pytest..."
    @pytest tests/

# === Building the Package ===

# Build wheel and sdist using the `build` package (requires dev deps from Nix)
build_package:
    @# Check if python and build are available
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' command not found. Are you inside 'nix develop'?" && exit 1)
    @python -m build --version > /dev/null 2>&1 || (echo "❌ 'build' module not found. Is python311Packages.build in flake.nix?" && exit 1)
    @echo "📦 Building wheel and sdist..."
    @python -m build
    @echo "✅ Build artifacts are in dist/"

# === Cleaning ===

# Remove Python cache files
clean_pycache:
    @echo "🧹 Removing __pycache__ directories and .pyc files..."
    @find . -type d -name "__pycache__" -exec rm -r {} +
    @find . -type f -name "*.py[co]" -delete

# Remove build artifacts
clean_build:
    @echo "🧹 Removing build artifacts (build/, dist/, *.egg-info/)..."
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/

# Clean build artifacts and pycache
clean: clean_pycache clean_build
    @echo "✅ Project directories cleaned (build artifacts, pycache)."

# Clean everything (build artifacts, pycache)
clean_all: clean
    @echo "✅ Full clean completed."

# === Debugging ===

debug:
  @echo "🐍 Provide edits in DIFF format, please."
  @echo "🐛 Running debug task..."
  @repomix . --output repo-content.txt
  @echo "🔍 Testing montaigne installation..."
  @mkdir -p input output
  @if [ ! -f "input/speaker.wav" ]; then \
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
    echo "❌ Could not create test WAV file"; \
  fi
  @if [ -d ".venv" ]; then \
    source .venv/bin/activate && \
    python -c "import montaigne" && \
    python -m montaigne.main synthesize \
      --output-file output/debug_output.wav \
      --speaker-wav input/speaker.wav \
      --language en; \
  else \
    echo "❌ No virtualenv found. Run 'just nix' first"; \
  fi

bark:
    @echo "🐾 Running Bark synthesis..."
    @python -m montaigne.main synthesize --engine bark -t "Hello from the Bark engine. It sounds different!" -l en -o output/bark_en_default.wav

bark_pt:
    @echo "🐾 Running Bark synthesis (Portuguese)..."
    @python -m montaigne.main synthesize --engine bark -t "Olá meu amigo, tudo bem meu amigo? Abraços." -l pt -o output/bark_pt_default.wav

yt:
    @echo "▶️ Running XTTS synthesis with YouTube speaker..."
    # Ensure quotes are correctly passed if running directly
    @python -m montaigne.main synthesize --engine xtts --speaker-youtube-id "dQw4w9WgXcQ" -t "Testing YouTube download." -l en -o output/yt_test.wav


# Run a simple debug command that verifies Torch CUDA functionality using Nix Python
debug_gpu:
    python -c 'import torch; print(f"PyTorch: {torch.__version__}"); print(f"CUDA Available: {torch.cuda.is_available()}"); print(f"Device Count: {torch.cuda.device_count()}")'

all:
    @echo "Running 'nix develop' to set up environment and execute tasks..."
    @# Execute subsequent just commands *inside* the Nix shell
    @# Use direct python calls inside nix develop to avoid nested just/quoting issues
    @nix develop --impure --command bash -c ' \
        echo "=== Inside Nix Shell ===";\
        echo "Running: debug synthesis (python -m montaigne.main ...)";\
        mkdir -p input output;\
        if [ ! -f "input/speaker.wav" ]; then ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null; fi;\
        python -m montaigne.main synthesize --output-file output/debug_output.wav --speaker-wav input/speaker.wav --language en -t "This is a debug test [p=0.5] with *emphasis*." && \
        echo "Running: bark synthesis (python -m montaigne.main ...)"; \
        python -m montaigne.main synthesize --engine bark -t "Hello from the Bark engine. It sounds different!" -l en -o output/bark_en_default.wav && \
        echo "Running: YouTube speaker synthesis (python -m montaigne.main ...)";\
        python -m montaigne.main synthesize --engine xtts --speaker-youtube-id "dQw4w9WgXcQ" -t "Testing YouTube download." -l en -o output/yt_test.wav && \
        echo "=== Nix Shell Tasks Complete ===";\
        exit 0;\
    '
    @# Run Docker tasks OUTSIDE the Nix shell if they don't rely on Nix env specifics
    @echo "=== Running Docker Tasks (Outside Nix Shell) ==="
    @just docker_dev
    @just docker_run

# === Docker ===

# Define core Docker details
# PROJECT_NAME is defined at the top level
DOCKER_TAG_LATEST := "latest"
DOCKER_TAG_GIT    := `git rev-parse --short HEAD`
# Define local image name (without registry)
DOCKER_IMAGE_NAME := PROJECT_NAME

# --- GHCR Specific Variables ---
# Get OWNER/REPO, fallback for local runs (replace if needed)
# GITHUB_REPOSITORY env var is set automatically in GitHub Actions
# Use env_or_default when available in `just`, otherwise simple `env`:
GITHUB_OWNER_REPO := env('GITHUB_REPOSITORY', "YOUR_USERNAME/YOUR_REPO") # REPLACE FALLBACK
# Define the full base image path for GHCR using concatenation
GHCR_IMAGE_BASE   := "ghcr.io/" + GITHUB_OWNER_REPO + "/" + DOCKER_IMAGE_NAME # Use project name in path
# Standard GHCR tags
GHCR_TAG_LATEST   := GHCR_IMAGE_BASE + ":" + DOCKER_TAG_LATEST
GHCR_TAG_COMMIT   := GHCR_IMAGE_BASE + ":" + DOCKER_TAG_GIT

# --- Manual Tag Handling ---
MANUAL_TAG        := env('MANUAL_TAG', '') # Read manual tag from env, default to empty
# Define full GHCR manual tag only if MANUAL_TAG is not empty
# We'll construct this within the recipe conditionally

# Build the Docker image, including tags for local use and GHCR
# If MANUAL_TAG is set via env, also tag with that for GHCR
docker_build *ARGS:
    @echo "🐳 Linting Dockerfile..."
    @command -v hadolint > /dev/null && hadolint Dockerfile --ignore DL3008 || echo "ℹ️ Hadolint not found, skipping lint."

    @echo "🐳 Building Docker image..."
    @echo "   Standard Tags:"
    @echo "     Local:  {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}, {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}"
    @echo "     GHCR:   {{GHCR_TAG_LATEST}}, {{GHCR_TAG_COMMIT}}"

    @# Warn if using fallback repository
    @test {{GITHUB_OWNER_REPO}} != "YOUR_USERNAME/YOUR_REPO" || echo "⚠️ Using fallback GITHUB_REPOSITORY. Set env var or run from Actions for correct GHCR tagging."

    @# Construct and perform the main build command directly
    @echo "Executing Docker Build Command..."
    @docker build {{ARGS}} \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" \
        -t "{{GHCR_TAG_LATEST}}" \
        -t "{{GHCR_TAG_COMMIT}}" \
        .

    @# Conditionally add the manual tag *after* the build succeeds
    @if [ -n "{{MANUAL_TAG}}" ]; then \
        _GHCR_TAG_MANUAL="{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        echo "   Manual Tag (GHCR): $${_GHCR_TAG_MANUAL}"; \
        echo "   Applying manual tag..."; \
        docker tag "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" "$${_GHCR_TAG_MANUAL}"; \
    else \
        echo "   No manual tag provided."; \
    fi
    @echo "✅ Docker image built."


# Push the GHCR-tagged images (latest, commit, and manual if set)
docker_push:
    @echo "⏫ Pushing GHCR images..."
    @# Check if GITHUB_REPOSITORY fallback is being used and fail if so
    @test {{GITHUB_OWNER_REPO}} != "YOUR_USERNAME/YOUR_REPO" || (echo "❌ Cannot push using fallback GITHUB_REPOSITORY. Run from GitHub Actions or set env var GITHUB_REPOSITORY=owner/repo." && exit 1)

    @# Push standard tags
    @echo "   Pushing GHCR Tag: {{GHCR_TAG_LATEST}}"
    @docker push "{{GHCR_TAG_LATEST}}"
    @echo "   Pushing GHCR Tag: {{GHCR_TAG_COMMIT}}"
    @docker push "{{GHCR_TAG_COMMIT}}"

    @# Conditionally push the manual tag
    @if [ -n "{{MANUAL_TAG}}" ]; then \
        _GHCR_TAG_MANUAL="{{GHCR_IMAGE_BASE}}:{{MANUAL_TAG}}"; \
        echo "   Pushing GHCR Manual Tag: $${_GHCR_TAG_MANUAL}"; \
        docker push "$${_GHCR_TAG_MANUAL}"; \
    else \
        echo "   No manual tag to push."; \
    fi
    @echo "✅ Images pushed to GHCR."

# Run a simple synthesis task inside a Docker container (CPU only) by default
# Uses the locally tagged image.
# Pass other Montaigne args after --, e.g., `just docker_run -- --language pt ...`
docker_run *ARGS:
    @echo "🐳 Running default synthesis task in Docker container (CPU)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    # Ensure a dummy speaker wav exists for the default run
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ No speaker.wav found in input/. Creating a dummy file for the test run."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav > /dev/null 2>&1 || \
        (echo "❌ Could not create dummy WAV. Is ffmpeg installed on the host?"; exit 1); \
    fi
    @docker run --rm \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        synthesize \
          --text "This is a default test run [p=0.5] inside Docker." \
          --output-file /app/output/docker_default_run_output.wav \
          --speaker-wav /app/input/speaker.wav \
          --language en \
        {{ARGS}} # Pass any additional user arguments here

# Run the application inside a Docker container with GPU support
# Uses the locally tagged image.
# Usage: just docker_run_gpu -- synthesize --text "GPU test" ...
docker_run_gpu *ARGS:
    @echo "🐳 Running Docker container (GPU)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    @docker run --rm --gpus all \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" {{ARGS}} # Requires user to pass 'synthesize' and all args

# Run a debug synthesis inside a Docker container (CPU)
# Uses the locally tagged image.
docker_debug:
    @echo "🐳 Running explicit debug synthesis inside Docker container (CPU)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ No speaker.wav found in input/. Creating a dummy file for the test."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "❌ Could not create dummy WAV. Is ffmpeg installed on the host?"; exit 1); \
    fi
    @docker run --rm \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_LATEST}}" \
        synthesize \
          --text "This is an explicit docker debug test [p=0.5] with *emphasis*." \
          --output-file /app/output/docker_debug_output.wav \
          --speaker-wav /app/input/speaker.wav \
          --language en \
          --cpu
    @echo "✅ Docker debug synthesis finished. Check output/docker_debug_output.wav"

# Check Docker status and provide helpful messages
docker_check:
    @echo "🔍 Checking Docker setup..."
    @if command -v docker >/dev/null 2>&1; then \
        if docker info >/dev/null 2>&1; then \
            echo "✅ Docker is working correctly!"; \
            echo "Docker version: $$(docker --version)"; \
            echo "Docker compose: $$(docker-compose --version || echo 'not found')"; \
            if docker info 2>/dev/null | grep -qE "Runtimes:.*nvidia"; then \
                echo "✅ NVIDIA runtime available for GPU support"; \
            else \
                echo "⚠️ NVIDIA runtime not found - needed for GPU in containers"; \
            fi; \
        else \
            echo "❌ Docker daemon is not running or permission issue"; \
            echo "Try:"; \
            echo "  sudo systemctl start docker"; \
            echo "  sudo usermod -aG docker $$USER && newgrp docker"; \
        fi; \
    else \
        echo "❌ Docker not installed or not in PATH"; \
    fi

docker_dev:
    @sh build-with-local-model.sh
    @just docker_build -- --build-arg USE_LOCAL_MODEL=true
    @rm -rf ./model_files
