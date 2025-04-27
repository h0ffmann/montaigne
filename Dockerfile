# --- Final Image ---
# Uses uv run, eliminating the need for a separate builder stage and venv copy.
# Installs dependencies and runs directly in the final stage.
# Start from the NVIDIA CUDA runtime image
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Add metadata labels
LABEL maintainer="Matheus Hoffmann <hoffmann@poli.ufrj.br>"
LABEL description="Montaigne TTS CLI Application with CUDA Support"
LABEL version="0.1.0"

# Set environment variables for runtime
# Add /root/.local/bin for uv installation location
ENV PATH="/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
# Configure uv for PyTorch CUDA and network access
ENV UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu121"
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_NATIVE_TLS="1"

WORKDIR /app

# Set SHELL to bash with pipefail before the RUN command that includes the uv installation pipe
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install system dependencies for runtime, Python 3.11 PPA, Python 3.11, and uv
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core runtime dependencies
    ffmpeg \
    libsndfile1 \
    ca-certificates \
    # Needed for Python 3.11 PPA and uv install
    software-properties-common \
    gpg-agent \
    curl \
    # Needed if project build process requires git
    git \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    # Install Python itself
    python3.11 \
    # python3.11-venv and python3.11-dev are likely NOT needed for uv run
    # Add any other NON-PYTHON system library required by the application at runtime here
    # Install uv using pipefail (uses the SHELL defined above)
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    # Clean up apt caches and lists to reduce image size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/deadsnakes*

# Reset shell to default (optional, but good practice)
SHELL ["/bin/sh", "-c"]

# Copy project files needed for `uv run`
# Copy pyproject.toml first for better layer caching
COPY pyproject.toml ./pyproject.toml
# Copy source code
COPY src/ ./src/

# ENTRYPOINT uses `uv run` to execute the script defined in pyproject.toml[project.scripts]
# uv will handle creating an isolated environment and installing dependencies
# on the fly (using cache if available) based on pyproject.toml.
ENTRYPOINT ["uv", "run", "montaigne"]

# Default command arguments passed to the entrypoint (uv run montaigne --help)
# This runs if no arguments are provided to `docker run`.
CMD ["--help"]