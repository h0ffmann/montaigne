# Temporary copy stage to make files available during RUN install step
FROM ubuntu:22.04 as file_copier
WORKDIR /tmp/project_files
COPY pyproject.toml ./
COPY src/ ./src/

# Add build arg to control model source
ARG USE_LOCAL_MODEL=false

# Model download stage - only used if local model isn't available
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04 as model_downloader
WORKDIR /model_download

# Install minimal Python environment to download the model
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-setuptools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set license agreement and install only TTS
ENV COQUI_TOS_AGREED=1
RUN pip3 install --no-cache-dir TTS

# Create a Python script to pre-download the model
RUN echo 'import os\n\
    import torch\n\
    from TTS.utils.manage import ModelManager\n\
    # Removed torch._C._set_default_weights_only_false_for_speed()\n\
    # Ensure license agreement is set\n\
    os.environ["COQUI_TOS_AGREED"] = "1"\n\
    # Pre-download model\n\
    print("Attempting to download model with ModelManager...")\n\
    manager = ModelManager()\n\
    model_path, config_path, model_item = manager.download_model("tts_models/multilingual/multi-dataset/xtts_v2")\n\
    print(f"Downloaded model to {os.path.dirname(model_path)}")' > download_model.py

# Run the script to download the model
RUN python3 download_model.py

# Final Image
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Add metadata labels
LABEL maintainer="Matheus Hoffmann <hoffmann@poli.ufrj.br>"
LABEL description="Montaigne TTS CLI Application with CUDA Support"
LABEL version="0.1.0"

# Set environment variables for runtime
ENV PATH="/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
# ENV UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu121" # REMOVIDO para usar a versão especificada abaixo
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_NATIVE_TLS="1"
ENV COQUI_TOS_AGREED=1

WORKDIR /app

# Set SHELL to bash with pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy files from the builder stage
COPY --from=file_copier /tmp/project_files /tmp/project_files

# Install system dependencies & Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essential runtime libs
    ffmpeg \
    libsndfile1 \
    ca-certificates \
    # Needed for adding PPA
    software-properties-common \
    gpg-agent \
    # Utilities needed during build
    curl \
    git \
    build-essential \
    pkg-config \
    # Clean apt lists immediately after installs
    && rm -rf /var/lib/apt/lists/* \
    # Add PPA for modern Python
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    # Install Python 3.11 from PPA
    && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    # Clean apt lists again after PPA installs
    && rm -rf /var/lib/apt/lists/*

# --- Install uv directly ---
ARG UV_VERSION=0.6.17 # Define uv version
ARG TARGETARCH # Docker provides this, e.g., amd64, arm64
# Map Docker's TARGETARCH to uv's target triple format
RUN ARCH=$TARGETARCH && \
    if [ "$ARCH" = "amd64" ]; then UV_TARGET="x86_64-unknown-linux-gnu"; \
    elif [ "$ARCH" = "arm64" ]; then UV_TARGET="aarch64-unknown-linux-gnu"; \
    else echo "Unsupported architecture: $ARCH for uv" && exit 1; fi && \
    echo "Downloading uv ${UV_VERSION} for ${UV_TARGET}..." && \
    curl -LsSf -o /tmp/uv.tar.gz "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_TARGET}.tar.gz" && \
    tar -xzf /tmp/uv.tar.gz -C /tmp && \
    mv /tmp/uv-${UV_TARGET}/uv /usr/local/bin/uv && \
    chmod +x /usr/local/bin/uv && \
    # Verify uv installation
    uv --version && \
    # Clean up download
    rm -rf /tmp/uv.tar.gz /tmp/uv-${UV_TARGET}

# --- Continue with your Dockerfile ---

# Create directory for the model
RUN mkdir -p /root/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2/

# Copy local model files if they exist, otherwise use downloaded model
ARG USE_LOCAL_MODEL
COPY model_files/ /tmp/model_files/
RUN if [ "$USE_LOCAL_MODEL" = "true" ] && [ -f "/tmp/model_files/model.pth" ]; then \
    echo "Using local model files" && \
    cp -r /tmp/model_files/* /root/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2/; \
    else \
    echo "Using downloaded model" && \
    # Ensure target directory exists even if model_downloader stage failed or was skipped
    mkdir -p /root/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2/ && \
    # Use cp --from only if source exists, otherwise log warning
    if [ -d /model_download/root/.local/share/tts ]; then \
    echo "Copying from model_downloader stage..." && \
    cp -r --from=model_downloader /root/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2/* /root/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2/; \
    else \
    echo "Warning: Model downloader stage artifacts not found. Model will download at runtime."; \
    fi; \
    fi && \
    rm -rf /tmp/model_files

# Install application (Simplified cleanup logic)
# Instala PyTorch e Torchaudio correspondentes ao CUDA 12.1 primeiro
RUN TORCH_URL="https://download.pytorch.org/whl/cu121" \
    && echo "Installing specific PyTorch version (2.5.1+cu121)..." \
    && uv pip install --system --no-cache --python /usr/bin/python3.11 \
       --find-links ${TORCH_URL} \
       "torch==2.5.1+cu121" \
       "torchaudio==2.5.1+cu121" \
    # Agora instala a aplicação local, uv deve detectar torch/torchaudio já instalados
    && cp /tmp/project_files/pyproject.toml /app/pyproject.toml \
    && cp -r /tmp/project_files/src /app/src \
    && echo "Installing application using uv..." && uv pip install --system --no-cache --python /usr/bin/python3.11 /app \
    # Limpa arquivos temporários de build e pacotes desnecessários
    && echo "Cleaning up build environment..." && rm -rf /tmp/project_files \
    && apt-get purge -y --auto-remove \
    git curl software-properties-common gpg-agent \
    build-essential pkg-config python3.11-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/deadsnakes* \
    && echo "Cleanup complete."

# Reset shell to default
SHELL ["/bin/sh", "-c"]

# Add entrypoint script for PyTorch security fixes
COPY entrypoint.sh /app/entrypoint.sh
# Ensure entrypoint is executable - add RUN chmod +x after COPY in your prepare_docker_files just task or here
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]

# Add CMD here if you want a default command, e.g.,
# CMD ["montaigne", "--help"]


