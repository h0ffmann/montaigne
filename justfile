# -*- mode: conf -*-

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


# === Running the Application ===

# Run the Montaigne CLI application using the Python from the Nix environment
# Pass arguments after `--`, e.g., `just run -- --text "Hello" ...`
run *ARGS:
    @# Check if python is available in the Nix shell
    @command -v python > /dev/null 2>&1 || (echo "❌ 'python' command not found. Are you inside 'nix develop'?" && exit 1)
    @echo "🚀 Running Montaigne CLI using Nix Python..."
    @python -m {{PROJECT_NAME}}.main {{ARGS}}

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
      --text "This is a debug test [p=0.5] with *emphasis*." \
      --output-file output/debug_output.wav \
      --speaker-wav input/speaker.wav \
      --language en \
      --cpu; \
  else \
    echo "❌ No virtualenv found. Run 'just nix' first"; \
  fi

# Run a simple debug command that verifies Torch CUDA functionality using Nix Python
debug_gpu:
    python -c 'import torch; print(f"PyTorch: {torch.__version__}"); print(f"CUDA Available: {torch.cuda.is_available()}"); print(f"Device Count: {torch.cuda.device_count()}")'



# === Docker ===

# Define Docker image name and tag
DOCKER_IMAGE_NAME := PROJECT_NAME # Assign the value of PROJECT_NAME directly
DOCKER_TAG        := "latest"
DOCKER_TAG_GIT    := `git rev-parse --short HEAD`

# Build the Docker image
# Pass extra args like --no-cache after --, e.g., `just docker_build -- --no-cache`
docker_build *ARGS:
    @echo "🐳 Building Docker image {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}} (and :{{DOCKER_TAG_GIT}})..."
    @docker build {{ARGS}} -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}" -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" .
    @echo "✅ Docker image built."

# Run the application inside a Docker container (CPU only)
# Mounts ./input (read-only) and ./output (read-write) directories.
# Usage: just docker_run -- --text "Docker test" --output-file /app/output/out.wav ...
docker_run *ARGS:
    @echo "🐳 Running Docker container (CPU)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    @docker run --rm \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}" {{ARGS}}

# Run the application inside a Docker container with GPU support
# Requires NVIDIA Container Toolkit on the host.
# Usage: just docker_run_gpu -- --text "GPU test" --output-file /app/output/out_gpu.wav ...
docker_run_gpu *ARGS:
    @echo "🐳 Running Docker container (GPU)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    @docker run --rm --gpus all \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}" {{ARGS}}

# Run a debug synthesis inside a Docker container (CPU)
docker_debug:
    @echo "🐳 Running debug synthesis inside Docker container (CPU)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ No speaker.wav found in input/. Creating a dummy file for the test."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav 2>/dev/null || \
        (echo "❌ Could not create dummy WAV. Is ffmpeg installed on the host?"; exit 1); \
    fi
    @docker run --rm \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}" \
        synthesize \
          --text "This is a debug test [p=0.5] with *emphasis*." \
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
            echo "Docker compose: $$(docker-compose --version)"; \
            if docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then \
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
