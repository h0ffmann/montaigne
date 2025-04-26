# -*- mode: conf -*-

# Justfile for the Montaigne TTS project

# Default task (optional, runs if you just type `just`)
default: run -- --help

# === Environment & Dependencies ===
# Define VENV_DIR relative to the Justfile location
VENV_DIR := ".venv"
PYTHON   := "{{VENV_DIR}}/bin/python"
UV       := "uv" # Assumes uv is in PATH

# Setup the virtual environment and install dependencies
setup: vendor_install install_editable

# Create virtualenv if it doesn't exist
create_venv:
    @if [ ! -d "{{VENV_DIR}}" ]; then \
        echo "Creating virtualenv at {{VENV_DIR}}..."; \
        {{UV}} venv {{VENV_DIR}} --python 3.12 || exit 1; \
        echo "Virtualenv created."; \
    else \
        echo "Virtualenv already exists."; \
    fi

# Install dependencies using uv pip sync (faster)
vendor_sync: create_venv
    @echo "Syncing dependencies with uv..."
    @{{UV}} pip sync pyproject.toml --python "{{VENV_DIR}}/bin/python" --require-hashes

# Install dependencies using uv pip install (alternative, more flexible for installs)
vendor_install: create_venv
    @echo "Installing dependencies with uv pip install..."
    # Install runtime and dev dependencies
    @{{UV}} pip install --python "{{VENV_DIR}}/bin/python" -r requirements.txt # Assumes you might generate one, fallback
    @{{UV}} pip install --python "{{VENV_DIR}}/bin/python" --all-extras -e . # Or use -e '.[dev]'

# Install the package in editable mode with dev extras
install_editable: create_venv
    @echo "Installing project in editable mode with dev dependencies..."
    @{{UV}} pip install --python "{{VENV_DIR}}/bin/python" -e '.[dev]'

# Alias for easier install command
install: install_editable

# === Linting & Formatting ===
lint:
    @echo "Running Ruff linter..."
    @{{PYTHON}} -m ruff check .

format:
    @echo "Running Ruff formatter..."
    @{{PYTHON}} -m ruff format .

check: lint format
    @echo "Lint and format checks passed."

# === Testing ===
# Add actual tests in a `tests/` directory later
test available=check_venv_cmd('pytest'):
    @echo "Running tests with pytest..."
    @{{PYTHON}} -m pytest tests/ # Assumes tests are in tests/

# === Running the Application ===
# Example run command - pass arguments after `--`
# Usage: just run -- --text "Hello" --output-file o.wav --speaker-wav s.wav -l en
run *ARGS: available=check_venv_cmd('montaigne')
    @echo "Running Montaigne CLI..."
    @{{PYTHON}} -m {{PROJECT_NAME}}.main {{ARGS}}

# === Building the Package ===
# Requires `build` package installed (via [dev] extras)
build available=check_venv_cmd('build'):
    @echo "Building wheel and sdist..."
    @{{PYTHON}} -m build

# === Cleaning ===
clean_pycache:
    @echo "Removing __pycache__ directories..."
    @find . -type d -name "__pycache__" -exec rm -r {} +
    @find . -type f -name "*.py[co]" -delete

clean_build:
    @echo "Removing build artifacts..."
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/

clean_venv:
    @echo "Removing virtual environment ({{VENV_DIR}})..."
    @rm -rf {{VENV_DIR}}

# Full clean including virtualenv
clean: clean_pycache clean_build
    @echo "Project directories cleaned."

# Deep clean including venv
clean_all: clean clean_venv
    @echo "Full clean including virtualenv completed."

# === Docker ===
DOCKER_IMAGE_NAME := "{{PROJECT_NAME}}"
DOCKER_TAG        := "latest"

docker_build:
    @echo "Building Docker image {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}..."
    @docker build -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}" .

# Example docker run - requires mapping input/output
# Usage: just docker_run -- --text "Docker test" --output-file /app/output/docker_out.wav --speaker-wav /app/input/speaker.wav -l en
# Make sure to `mkdir input output` and place speaker.wav in `input/` first!
docker_run *ARGS:
    @echo "Running Docker container (mapping ./input:/app/input, ./output:/app/output)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    @docker run --rm \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}} {{ARGS}}

# Helper function to check if command exists in venv
check_venv_cmd(cmd) := `{{PYTHON}} -m {{cmd}} --version > /dev/null 2>&1 || (echo "Command '{{cmd}}' not found in venv. Run 'just install'?" && exit 1)`
