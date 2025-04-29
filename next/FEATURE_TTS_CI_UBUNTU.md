# Ubuntu TTS Tasks with Official UV GitHub Action

This document outlines how to implement a GitHub Action workflow for running TTS tasks on Ubuntu without relying on Nix or flake.nix, using the official `astral-sh/setup-uv` GitHub Action.

## 1. Create New GitHub Action Workflow

Create a new file `.github/workflows/ubuntu-tts-tasks.yml` with the following content:

```yaml
name: Run TTS Tasks (Ubuntu - CPU Only)

on:
  push:
    branches:
      - master
  pull_request:
    branches:
      - master
  workflow_dispatch:
    inputs:
      debug_enabled:
        description: 'Run with tmate debugging enabled (bool)'
        required: false
        default: false
        type: boolean

jobs:
  run-tts-on-ubuntu:
    runs-on: ubuntu-latest
    env:
      # Ensure CPU-only mode for PyTorch/TTS
      CUDA_VISIBLE_DEVICES: ""
      USE_CUDA: "0"
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Setup Python 3.11
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
          cache: 'pip'
      
      - name: Install system dependencies
        run: |
          sudo apt-get update
          # Install system-level dependencies (no CUDA libraries)
          sudo apt-get install -y --no-install-recommends \
            ffmpeg \
            libsndfile1 \
            libportaudio2 \
            libasound2-dev \
            libgl1 \
            build-essential \
            pkg-config
      
      - name: Install UV
        uses: astral-sh/setup-uv@v6
        with:
          version: "0.6.17"  # Pin to a specific version
          enable-cache: true # Enable caching for faster runs
      
      - name: Install Just
        uses: extractions/setup-just@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Run TTS Tasks via Just (CPU-only)
        run: just run_tts_tasks_ubuntu_cpu
      
      - name: Setup tmate session for debugging
        if: failure() && github.event.inputs.debug_enabled == 'true'
        uses: mxschmitt/action-tmate@v3
        timeout-minutes: 15
```

## 2. Update Justfile with New Command

Add the following command to your `justfile`:

```makefile
# === Ubuntu TTS Tasks (CPU-Only, No Nix/Flake required) ===
run_tts_tasks_ubuntu_cpu:
    @echo "🚀 Running TTS tasks on Ubuntu (CPU-only, No Nix required)..."
    
    # Ensure directories exist
    @mkdir -p input output
    
    # Create dummy speaker.wav if it doesn't exist
    @if [ ! -f "input/speaker.wav" ]; then \
        echo "🔊 Creating sample speaker.wav file..."; \
        ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav; \
    fi
    
    # Create virtual environment
    @echo "🐍 Setting up Python environment..."
    @uv venv .venv
    
    # Enforce CPU-only mode through environment variables
    @export CUDA_VISIBLE_DEVICES="" && \
    export USE_CUDA="0" && \
    export FORCE_CPU="1" && \
    
    # Install dependencies (explicitly CPU-only PyTorch)
    @echo "📦 Installing dependencies (CPU-only PyTorch)..."
    @. .venv/bin/activate && \
        uv pip install \
            torch==2.1.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cpu \
            numpy pandas scipy \
            click==8.1.8 \
            requests'>=2.31.0' \
            TTS==0.22.0 \
            openai-whisper==20240930 \
            rapidfuzz==3.13.0 \
            pydub'>=0.25.0' \
            yt-dlp'>=2023.0.0' \
            soundfile'>=0.12.1' \
            matplotlib'>=3.5.0' \
            sounddevice'>=0.4.5' \
            transformers'>=4.0.0' \
            accelerate'>=0.20.0' \
            huggingface-hub'>=0.20.0' \
            piper-tts'>=1.2.0' \
            'suno-bark @ git+https://github.com/suno-ai/bark.git' \
            -e .
    
    # Run TTS tasks with explicit CPU flag
    @echo "✨ Running TTS synthesis with CPU..."
    @. .venv/bin/activate && \
        CUDA_VISIBLE_DEVICES="" USE_CUDA="0" \
        python -m montaigne.main synthesize \
            --cpu \
            --output-file output/debug_output.wav \
            --speaker-wav input/speaker.wav \
            --language en \
            --text "This is a debug test with emphasis."
    
    @echo "✨ Running Bark synthesis with CPU..."
    @. .venv/bin/activate && \
        CUDA_VISIBLE_DEVICES="" USE_CUDA="0" \
        python -m montaigne.main synthesize \
            --engine bark \
            --cpu \
            --text "Hello from the Bark engine on Ubuntu." \
            --language en \
            --output-file output/bark_ubuntu_test.wav
    
    # Generate repomix output
    @echo "👾 Generate repomix output..."
    @. .venv/bin/activate && repomix .
    
    @echo "✅ TTS tasks completed successfully in CPU-only mode!"
```

## 3. Create Local Setup Script for Ubuntu (Optional)

For local development, create a `setup-ubuntu-cpu.sh` script:

```bash
#!/bin/bash
set -e

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

echo "🚀 Setting up Montaigne TTS environment on Ubuntu (CPU-only)"

# Install required system packages
echo "📦 Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ffmpeg \
  libsndfile1 \
  libportaudio2 \
  libasound2-dev \
  libgl1 \
  build-essential \
  pkg-config \
  python3.11 \
  python3.11-venv \
  python3-pip \
  curl \
  git

# Install Just if not already installed
if ! command_exists just; then
  echo "📦 Installing Just command runner..."
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"
fi

# Install UV if not already installed
if ! command_exists uv; then
  echo "📦 Installing UV package manager..."
  curl --proto '=https' --tlsv1.2 -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

# Create directories and sample files
mkdir -p input output

# Create a dummy speaker.wav if it doesn't exist
if [ ! -f "input/speaker.wav" ]; then
  echo "🔊 Creating sample speaker.wav file..."
  ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -ac 1 -ar 16000 input/speaker.wav
fi

# Add CPU-only environment variables to shell profile
echo "" >> ~/.bashrc
echo "# Montaigne TTS CPU-only environment variables" >> ~/.bashrc
echo "export CUDA_VISIBLE_DEVICES=\"\"" >> ~/.bashrc
echo "export USE_CUDA=\"0\"" >> ~/.bashrc
echo "export FORCE_CPU=\"1\"" >> ~/.bashrc

echo "✅ Setup complete! You can now run:"
echo "   just run_tts_tasks_ubuntu_cpu"
echo ""
echo "⚠️ NOTE: CPU-only environment variables have been added to your ~/.bashrc"
echo "   You may need to restart your shell or run 'source ~/.bashrc'"
```

Make the script executable:
```bash
chmod +x setup-ubuntu.sh
```

## 4. Implementation Notes

### Key Benefits of Using the Official UV Action

1. **Official Support**: The `astral-sh/setup-uv` action is officially maintained by Astral and provides robust support for UV in GitHub Actions.

2. **Integrated Caching**: The action includes built-in caching support, which can dramatically speed up your workflow execution times by preserving the UV cache across runs.

3. **Version Pinning**: You can pin to a specific version of UV to ensure consistent behavior across workflow runs.

4. **Simplified Setup**: Compared to manual installation, the action handles downloading, installing, and adding UV to the PATH automatically.

### CPU-Only Implementation

This implementation is strictly CPU-only for several reasons:

1. **Compatibility**: Ensures the workflow runs on standard GitHub-hosted runners without special hardware requirements
2. **Reliability**: Prevents potential issues with GPU detection or utilization in CI environments
3. **Consistency**: Guarantees reproducible results regardless of the execution environment

The CPU-only approach is enforced through multiple mechanisms:

1. **Environment variables**: Setting `CUDA_VISIBLE_DEVICES=""` and `USE_CUDA="0"`
2. **PyTorch CPU build**: Installing explicitly from the CPU-only PyTorch package index
3. **Command-line flags**: Using the `--cpu` flag with all TTS commands

This comprehensive approach ensures that even if GPU hardware were somehow available, the workflow would still use CPU-only processing.

## 5. Usage

### GitHub Actions

The workflow will run automatically on:
- Push to master branch
- Pull requests to master branch
- Manual triggers via GitHub Actions UI

### Local Development (CPU-Only)

1. Run the CPU-only setup script:
   ```bash
   ./setup-ubuntu-cpu.sh
   ```

2. Run the CPU-only TTS tasks:
   ```bash
   just run_tts_tasks_ubuntu_cpu
   ```

3. Verify CPU-only mode is active:
   ```bash
   . .venv/bin/activate && python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
   ```
   This should output: `CUDA available: False`