# --- Final Image ---
# NO LONGER USING A SEPARATE BUILDER STAGE FOR VENV
# We will install dependencies and run directly in the final stage using uv.
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
# Configure uv for PyTorch CUDA
ENV UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu121"
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_NATIVE_TLS="1" # Enable native TLS for uv

WORKDIR /app

# Install system dependencies for runtime, Python 3.11, and uv
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    ca-certificates \
    # Needed for Python 3.11 PPA and uv install
    software-properties-common \
    gpg-agent \
    curl \
    git \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.11 \
    # python3.11-venv and python3.11-dev are likely NOT needed for uv run
    # Add any other NON-PYTHON system library required by the application at runtime
    # Install uv using pipefail
    && SHELL="/bin/bash -o pipefail -c" curl -LsSf https://astral.sh/uv/install.sh | sh \
    # Clean up apt caches and lists
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/deadsnakes*

# Copy project files needed for `uv run`
COPY pyproject.toml ./pyproject.toml
COPY src/ ./src/

# ENTRYPOINT uses `uv run` to execute the script defined in pyproject.toml
# uv will handle creating an isolated environment and installing dependencies on the fly (using cache if available)
ENTRYPOINT ["uv", "run", "montaigne"]

# Default command arguments passed to the entrypoint (uv run montaigne --help)
CMD ["--help"]
