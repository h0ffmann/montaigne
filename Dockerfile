# --- Stage 1: Builder ---
# Use a standard Python image for building dependencies
FROM python:3.11-slim-bookworm AS builder

# Set environment variables for build stage
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.local/bin:$PATH" # Add local bin to PATH for uv

WORKDIR /app

# Install build-time system dependencies (minimal needed)
# build-essential contains gcc, g++, make etc. needed for some wheels
# python3.11-dev is needed to build some Python extensions (like Cython based ones)
# git might be needed if a dependency is pulled from a git repo directly
# curl is needed to install uv
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3.11-dev \
    git \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install uv package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and activate virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip within the venv (good practice before installing)
RUN pip install --upgrade pip

# Copy dependency definitions
COPY pyproject.toml ./

# Install PyTorch+CUDA first using pip (more reliable for specific index)
# Pin versions exactly as in the original Dockerfile
RUN pip install --no-cache-dir \
    torch==2.1.0+cu121 \
    torchaudio==2.1.0+cu121 \
    --extra-index-url https://download.pytorch.org/whl/cu121

# Install the rest of the application dependencies using uv (potentially faster)
# uv should pick up the venv automatically. Using '.' installs from pyproject.toml
RUN uv pip install --no-cache-dir .

# Copy application source code
COPY src/ ./src/

# Install the application itself into the venv
# Use regular install, not editable (-e) for the final image artifact
RUN pip install --no-cache-dir .


# --- Stage 2: Final Image ---
# Start from the NVIDIA CUDA runtime image
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Set environment variables for runtime
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PATH="/opt/venv/bin:$PATH" \
    # Runtime GPU variables (optional if set outside container)
    # CUDA_VISIBLE_DEVICES is typically managed by the container runtime or application
    TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0" \
    FORCE_CUDA=1

WORKDIR /app

# Install runtime system dependencies
# We need python3.11 runtime, ffmpeg, libsndfile1
# The base CUDA image might have Python 3.10, so we install 3.11
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    ffmpeg \
    libsndfile1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Link python3.11 to python3 and python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Copy the virtual environment with all installed packages from the builder stage
COPY --from=builder /opt/venv /opt/venv

# Copy only the installed application code (if needed - usually venv is sufficient)
# If your pip install '.' correctly packages src, this might be optional.
# Keeping it for safety unless you verify packaging.
COPY --from=builder /app/src /app/src

# Set the default command to run the application
ENTRYPOINT ["montaigne"]

# Expose metadata
LABEL maintainer="Matheus Hoffmann <hoffmann@poli.ufrj.br>"
LABEL description="Montaigne TTS CLI Application with CUDA Support"
LABEL version="0.1.0"
