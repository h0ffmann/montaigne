# Temporary copy stage to make files available during RUN install step
# This avoids invalidating the RUN layer cache if only source code changes
FROM ubuntu:22.04 as file_copier
WORKDIR /tmp/project_files
COPY pyproject.toml ./
COPY src/ ./src/

# --- Final Image ---
# Installs dependencies during build for efficiency.
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
# Configure uv for PyTorch CUDA and network access (still needed for build stage)
ENV UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu121"
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_NATIVE_TLS="1"

WORKDIR /app
# Create the license marker file in the home directory (/root)
RUN touch /root/.TTS_LICENSE_ACCEPTED

# Set SHELL to bash with pipefail for robust installation commands
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# CORRECT: Copy files from the builder stage *before* the RUN command that needs them
COPY --from=file_copier /tmp/project_files /tmp/project_files

# Install system dependencies, Python 3.11, uv, AND application dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core runtime dependencies required by the application/TTS/Whisper
    ffmpeg \
    libsndfile1 \
    ca-certificates \
    # Needed temporarily for Python PPA and uv install
    software-properties-common \
    gpg-agent \
    curl \
    # Add Python 3.11 PPA
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    # Install Python itself
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    # Needed for potential C extensions during pip install
    build-essential \
    pkg-config \
    # Install uv
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    # --- Install Python Dependencies using uv ---
    # CORRECT: Use 'cp' (a shell command) to copy files *already copied* into the build context
    && cp /tmp/project_files/pyproject.toml /app/pyproject.toml \
    && cp -r /tmp/project_files/src /app/src \
    # Now, install the project and its dependencies defined in pyproject.toml
    # This installs dependencies into the system Python environment within the container
    && uv pip install --system --no-cache --python /usr/bin/python3.11 /app \
    # --- Clean up ---
    # Remove temporary build files
    && rm -rf /tmp/project_files \
    # Remove packages only needed for build/install phase
    && apt-get purge -y --auto-remove \
        software-properties-common gpg-agent curl build-essential pkg-config \
        python3.11-dev \
    # Clean up apt caches and lists
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/deadsnakes*

# Copy the rest of the project files AFTER installing dependencies
# This assumes they might be needed at runtime but not for installation itself.
# If they are needed for install, adjust the RUN sequence above.
# COPY . /app # You might not need to copy everything if install worked

# Reset shell to default (good practice)
SHELL ["/bin/sh", "-c"]

# Set the default entrypoint to run the installed script
ENTRYPOINT ["montaigne"]

# Default command arguments (now passed to 'montaigne' entrypoint)
# Providing '--help' is still a reasonable default if no args are given
CMD ["--help"]
