# --- Stage 1: Builder ---
# Use the NVIDIA CUDA development image as the builder base.
FROM nvidia/cuda:12.1.1-devel-ubuntu22.04 AS builder

# Set environment variables for build stage
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=off
ENV PIP_DISABLE_PIP_VERSION_CHECK=on
ENV PIP_DEFAULT_TIMEOUT=100
ENV DEBIAN_FRONTEND=noninteractive
# Set base path first
ENV PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
# Add user local bin for uv installation location
ENV PATH="/root/.local/bin:$PATH"
# Set virtual environment location
ENV VIRTUAL_ENV="/opt/venv"
# Add virtual environment bin to PATH (will be updated after python3.11 install)
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

# Install build-time system dependencies for Python 3.11 from PPA and uv build requirements
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    curl \
    libsndfile1-dev \
    # Needed if project depends on git for versions or installs
    git \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/deadsnakes*

# Update alternatives to ensure python3 points to 3.11 *within the builder*
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Install uv package manager
# Set pipefail for curl | sh command below
SHELL ["/bin/bash", "-o", "pipefail", "-c"] 
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# Reset shell to default after the pipe command
SHELL ["/bin/sh", "-c"]

# Create virtual environment using the newly installed python3.11
RUN python3.11 -m venv $VIRTUAL_ENV

# Copy dependency definition first
COPY pyproject.toml ./pyproject.toml
# Copy the src directory into the WORKDIR (/app), creating /app/src
COPY src/ /app/src/

# Install ALL python dependencies using uv into the virtual environment
RUN uv pip install --no-cache-dir \
    --python $VIRTUAL_ENV/bin/python \
    --extra-index-url https://download.pytorch.org/whl/cu121 \
    --index-strategy unsafe-best-match \
    . 

# Debugging: Verify the entrypoint script exists using 'test -f'
# Add SHELL directive to satisfy DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN echo "Checking for montaigne script in builder..." && \
    if test -f "$VIRTUAL_ENV/bin/montaigne"; then \
        echo "✅ Montaigne script found in $VIRTUAL_ENV/bin (Builder)"; \
    else \
        echo "❌ ERROR: Montaigne script NOT found in $VIRTUAL_ENV/bin (Builder)"; \
        exit 1; \
    fi
# Reset shell
SHELL ["/bin/sh", "-c"]


# --- Stage 2: Final Image ---
# Start from the NVIDIA CUDA runtime image
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Add metadata labels
LABEL maintainer="Matheus Hoffmann <hoffmann@poli.ufrj.br>"
LABEL description="Montaigne TTS CLI Application with CUDA Support"
LABEL version="0.1.0"

# Set environment variables for runtime
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV VIRTUAL_ENV="/opt/venv"
# IMPORTANT: Only the venv bin needs to be in the path for the entrypoint
ENV PATH="$VIRTUAL_ENV/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

WORKDIR /app 

# Install ONLY essential runtime system dependencies (NO UV needed here)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    ca-certificates \
    # Add any other NON-PYTHON system library required by the application at runtime
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy the entire virtual environment from the builder stage
COPY --from=builder /opt/venv /opt/venv

# Debugging: Verify the entrypoint script is present after COPY using 'test -f'
# Add SHELL directive to satisfy DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN echo "Checking for montaigne script in final stage..." && \
    if test -f "$VIRTUAL_ENV/bin/montaigne"; then \
        echo "✅ Montaigne script found in $VIRTUAL_ENV/bin (Final Stage)"; \
    else \
        echo "❌ ERROR: Montaigne script NOT found in $VIRTUAL_ENV/bin (Final Stage)"; \
        exit 1; \
    fi
# Reset shell
SHELL ["/bin/sh", "-c"]

# --- USE DIRECT ENTRYPOINT ---
ENTRYPOINT ["/opt/venv/bin/montaigne"]
