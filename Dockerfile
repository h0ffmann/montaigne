# --- Stage 1: Builder ---
# Use the NVIDIA CUDA development image as the builder base.
FROM nvidia/cuda:12.1.1-devel-ubuntu22.04 AS builder

# Set environment variables for build stage
# Consistent naming for VIRTUAL_ENV
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:/root/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=off
ENV PIP_DISABLE_PIP_VERSION_CHECK=on
ENV PIP_DEFAULT_TIMEOUT=100
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Install build-time system dependencies, Python 3.11 PPA, and Python itself
# Combine steps into fewer layers where logical and clean up apt lists in each RUN
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    curl \
    libsndfile1-dev \
    git \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    # Clean up apt caches and lists
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/deadsnakes*

# Update alternatives to ensure python3 points to 3.11 *within the builder*
# Useful if any build script implicitly calls 'python3'
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Install uv package manager using pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# Reset shell to default for subsequent commands if needed, although RUN creates new shell instances
SHELL ["/bin/sh", "-c"]

# Create virtual environment using the newly installed python3.11
RUN python3.11 -m venv "$VIRTUAL_ENV"

# Copy dependency definition first for better caching
COPY pyproject.toml ./pyproject.toml

# Install ALL python dependencies using uv into the virtual environment
# Ensure pyproject.toml defines the 'montaigne' console script correctly!
# Example:
# [project.scripts]
# montaigne = "your_package_name.your_module:your_main_function"
RUN uv pip install --no-cache-dir \
    --python "$VIRTUAL_ENV/bin/python" \
    --extra-index-url https://download.pytorch.org/whl/cu121 \
    --index-strategy unsafe-best-match \
    # Install the package defined in pyproject.toml located in the current directory '.'
    .

# Copy the source code *after* installing dependencies
# This layer changes only when source code changes, not dependencies
COPY src/ /app/src/

# Debugging: Verify the entrypoint script exists using explicit if/then/else
# Use bash for the if/then/else structure for robustness
SHELL ["/bin/bash", "-c"]
RUN echo "Checking for montaigne script in builder..." && \
    if test -f "$VIRTUAL_ENV/bin/montaigne"; then \
    echo "✅ Montaigne script found in $VIRTUAL_ENV/bin (Builder)"; \
    else \
    echo "❌ ERROR: Montaigne script NOT found in $VIRTUAL_ENV/bin (Builder). Check pyproject.toml [project.scripts] and uv install logs."; \
    exit 1; \
    fi
# Reset shell (optional, good practice)
SHELL ["/bin/sh", "-c"]

# --- Stage 2: Final Image ---
# Start from the NVIDIA CUDA runtime image
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Add metadata labels
LABEL maintainer="Matheus Hoffmann <hoffmann@poli.ufrj.br>"
LABEL description="Montaigne TTS CLI Application with CUDA Support"
LABEL version="0.1.0"

# Set environment variables for runtime
ENV VIRTUAL_ENV=/opt/venv
# Ensure venv bin is first in PATH for the entrypoint
ENV PATH="$VIRTUAL_ENV/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

WORKDIR /app

# Install ONLY essential runtime system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    ca-certificates \
    # Add any other NON-PYTHON system library required by the application at runtime
    # Clean up apt caches and lists
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy the entire virtual environment from the builder stage
# This includes Python, dependencies, and the entrypoint script
COPY --from=builder "$VIRTUAL_ENV" "$VIRTUAL_ENV"

# Debugging: Verify the entrypoint script is present after COPY using explicit if/then/else
# Use bash for the if/then/else structure
SHELL ["/bin/bash", "-c"]
RUN echo "Checking for montaigne script in final stage..." && \
    if test -f "$VIRTUAL_ENV/bin/montaigne"; then \
    echo "✅ Montaigne script found in $VIRTUAL_ENV/bin (Final Stage)"; \
    else \
    echo "❌ ERROR: Montaigne script NOT found in $VIRTUAL_ENV/bin (Final Stage). Problem likely occurred during build stage or COPY."; \
    exit 1; \
    fi
# Reset shell (optional, good practice)
SHELL ["/bin/sh", "-c"]

# Set the entrypoint to run the application script from the virtual environment
ENTRYPOINT ["/opt/venv/bin/montaigne"]

# Optional: Default command if needed (often ENTRYPOINT is sufficient for CLIs)
# CMD ["--help"]