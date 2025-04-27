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
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
SHELL ["/bin/sh", "-c"]

# Create virtual environment using the newly installed python3.11
RUN python3.11 -m venv $VIRTUAL_ENV

# Copy dependency definition first
COPY pyproject.toml ./pyproject.toml
# COPY uv.lock ./uv.lock # Uncomment if you use uv.lock

# Copy the src directory into the WORKDIR (/app), creating /app/src
COPY src/ /app/src/

# Install ALL python dependencies using uv into the virtual environment
RUN uv pip install --no-cache-dir \
    # NOTE: Removed --system flag. When installing with explicit --python,
    # uv correctly targets the specified venv.
    --python $VIRTUAL_ENV/bin/python \
    --extra-index-url https://download.pytorch.org/whl/cu121 \
    --index-strategy unsafe-best-match \
    . 

# Debugging: Verify script exists in the builder's venv bin
RUN echo "Contents of $VIRTUAL_ENV/bin (Builder):" && ls -l $VIRTUAL_ENV/bin


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
# Prioritize venv bin AND user local bin (where uv might be installed if kept)
ENV PATH="$VIRTUAL_ENV/bin:/root/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin" # Expanded PATH

# ---- CHANGE WORKDIR ----
WORKDIR /work # Change working directory to avoid conflict with mounted volumes

# Install runtime system dependencies AND UV
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    ca-certificates \
    curl \
    # Install uv requires curl
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install uv in the final stage
# Using /usr/local/bin to avoid needing /root/.local/bin in PATH for execution if installed as root
# Or install as root and ensure /root/.local/bin is in PATH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
SHELL ["/bin/sh", "-c"]

# Copy the entire virtual environment from the builder stage
COPY --from=builder /opt/venv /opt/venv
# Copy pyproject.toml so uv run can find the script definition
COPY --from=builder /app/pyproject.toml ./pyproject.toml

# Optional: Copy source if using `uv run python src/main.py...` instead of script name
# COPY --from=builder /app/src/ ./src/

# Debugging: Check uv path and venv contents in final stage
RUN which uv
# --- NO Debugging ls in final stage for production ---

# Execute uv run FROM the location of pyproject.toml
# ENTRYPOINT ["uv", "-- CWD=/app", "run", "montaigne"] <-- CWD isn't a uv arg
# Better approach: invoke uv directly with knowledge of its context
# ENTRYPOINT ["/root/.local/bin/uv", "run", "--manifest-path", "/app/pyproject.toml", "montaigne"]
ENTRYPOINT ["uv", "run", "--manifest-path", "/app/pyproject.toml", "montaigne"] # Assuming uv is now in standard path via ENV
