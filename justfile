# -*- mode: conf -*-

# Justfile for the Montaigne TTS project
# Uses `uv` for environment and dependency management.

# === Variables ===
PROJECT_NAME := "montaigne" # Should match pyproject.toml
VENV_DIR     := ".venv"
PYTHON       := "{{VENV_DIR}}/bin/python"
UV           := "uv" # Assumes uv is in PATH

# === Default Task ===
# List available recipes by default
default:
    @just --list

# === Environment & Dependencies (Managed by UV) ===

# Create virtualenv using uv if it doesn't exist
_create_venv:
    @if [ ! -d "{{VENV_DIR}}" ]; then \
        echo "🐍 Creating virtualenv at {{VENV_DIR}} using uv..."; \
        {{UV}} venv {{VENV_DIR}} --python 3.11 || exit 1; \
        echo "✅ Virtualenv created."; \
    else \
        echo "🐍 Virtualenv already exists at {{VENV_DIR}}."; \
    fi

# Install the project in editable mode with all development dependencies
# This is the main command for setting up the development environment.
install: _create_venv
    @echo "📦 Installing project in editable mode with dev dependencies using uv..."
    @# uv should automatically detect the .venv environment
    @{{UV}} pip install -e '.[dev]'
    @echo "✅ Project installed."

# Install only production dependencies (useful for testing prod builds)
install_prod: _create_venv
    @echo "📦 Installing project with production dependencies only using uv..."
    @# uv should automatically detect the .venv environment
    @{{UV}} pip install .
    @echo "✅ Production dependencies installed."

# Alias for the main development setup
setup: install

# === Running the Application ===

# Run the Montaigne CLI application from the virtual environment
# Pass arguments after `--`, e.g., `just run -- --text "Hello" ...`
run *ARGS:
    @# First, check if the 'montaigne' command (entry point) is available via uv run
    @{{UV}} run -- {{PROJECT_NAME}} --help > /dev/null 2>&1 || (echo "❌ Command '{{PROJECT_NAME}}' not runnable via uv in venv {{VENV_DIR}}. Run 'just install'?" && exit 1)
    @echo "🚀 Running Montaigne CLI using uv..."
    @{{UV}} run {{PROJECT_NAME}} {{ARGS}}

# === Linting & Formatting (using Ruff via venv) ===

# Run Ruff linter
lint:
    @# First, check if 'ruff' is available
    @{{PYTHON}} -m ruff --version > /dev/null 2>&1 || (echo "❌ Command 'ruff' not found in venv {{VENV_DIR}}. Run 'just install'?" && exit 1)
    @echo "✨ Running Ruff linter using uv..."
    @{{UV}} run ruff check .

# Run Ruff formatter
format:
    @# First, check if 'ruff' is available
    @{{PYTHON}} -m ruff --version > /dev/null 2>&1 || (echo "❌ Command 'ruff' not found in venv {{VENV_DIR}}. Run 'just install'?" && exit 1)
    @echo "🎨 Running Ruff formatter using uv..."
    @{{UV}} run ruff format .

# Run both linter and formatter
check: lint format
    @echo "✅ Lint and format checks passed."

# === Testing (using Pytest via venv) ===

# Run tests using pytest (assumes tests are in tests/)
test:
    @# First, check if 'pytest' is available
    @{{PYTHON}} -m pytest --version > /dev/null 2>&1 || (echo "❌ Command 'pytest' not found in venv {{VENV_DIR}}. Run 'just install'?" && exit 1)
    @echo "🧪 Running tests with pytest using uv..."
    @{{UV}} run pytest tests/

# === Building the Package ===

# Build wheel and sdist using the `build` package (requires dev deps)
build_package:
    @# First, check if the 'build' module is available
    @{{PYTHON}} -m build --version > /dev/null 2>&1 || (echo "❌ Command 'build' not found in venv {{VENV_DIR}}. Run 'just install'?" && exit 1)
    @echo "📦 Building wheel and sdist..."
    @{{PYTHON}} -m build
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

# Remove the virtual environment
clean_venv:
    @echo "🧹 Removing virtual environment ({{VENV_DIR}})..."
    @rm -rf {{VENV_DIR}}

# Clean build artifacts and pycache
clean: clean_pycache clean_build
    @echo "✅ Project directories cleaned (build artifacts, pycache)."

# Clean everything including the virtual environment
clean_all: clean clean_venv
    @echo "✅ Full clean including virtualenv completed."

# === Debugging ===

# Run a simple debug/test command that verifies basic functionality
debug:
    @echo "🐛 Running debug task: Generating fresh repo-content.txt + basic synthesis..."
    @repomix . --output repo-content.txt
    @echo "🐞 Running debug/test command..."
    @mkdir -p input output
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "⚠️ No speaker.wav found in input/. Creating a dummy file (you'll need a real WAV for actual synthesis)"; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 "input/speaker.wav" 2>/dev/null || \
        (echo "❌ Could not create dummy WAV. Install ffmpeg or provide a real speaker.wav in input/"; exit 1); \
    fi
    @echo "✅ Created input/speaker.wav dummy file"
    @echo "🚀 Running simple synthesis test..."
    @{{UV}} run {{PROJECT_NAME}} synthesize \
        --text "This is a debug test [p=0.5] with *emphasis*." \
        --output-file "output/debug_output.wav" \
        --speaker-wav "input/speaker.wav" \
        --language en
    @echo "✨ Debug command completed. Check output/debug_output.wav"

# === Docker ===

# Define Docker image name and tag
DOCKER_IMAGE_NAME := "{{PROJECT_NAME}}"
DOCKER_TAG        := "latest"
DOCKER_TAG_GIT    := `git rev-parse --short HEAD`

# Build the Docker image
docker_build:
    @echo "🐳 Building Docker image {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}} (and :{{DOCKER_TAG_GIT}})..."
    @docker build -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}" -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG_GIT}}" .
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
