# Stage 1: Build Environment (Optional but good practice if build deps were heavy)
# Using Python 3.12 slim version based on Debian Bookworm
FROM python:3.12-slim-bookworm AS base

# Set working directory
WORKDIR /app

# Install system dependencies needed for TTS, Whisper, PyTorch, Audio processing
# libsndfile1 is often needed for audio IO, ffmpeg for conversion/manipulation
# git might be needed if uv/pip pulls git dependencies (less common now)
# Depending on exact TTS/Whisper backends, others might be needed (e.g., espeak-ng)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Install uv using the recommended installer
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# Copy only the dependency definition first to leverage Docker cache
COPY pyproject.toml ./

# Install ONLY production dependencies using uv
# --no-dev prevents installing [dev] optional-dependencies
# Use --frozen or --require-hashes in the future if you generate a lock file
# Pin uv version if desired for stricter reproducibility: uv==X.Y.Z
RUN uv pip install --no-cache --system --no-deps -r requirements.txt # Assumes you MIGHT create one
# Prioritize installing direct dependencies defined in pyproject.toml
RUN uv pip install --no-cache --system .

# Copy the rest of the application source code
COPY src/ ./src/

# Set the default command to run the application
# Makes the container executable like: docker run <image> --text "hello" ...
ENTRYPOINT ["montaigne"]

# Expose metadata (optional)
LABEL maintainer="Your Name <your@email.com>"
LABEL description="Montaigne TTS CLI Application"
LABEL version="0.1.0"
