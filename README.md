# Montaigne TTS

Montaigne is a command-line tool for generating Text-to-Speech (TTS) audio using different engines. It supports:

*   **Batch Synthesis:** Generate audio files using **Coqui XTTSv2** (with voice cloning) or **Suno AI Bark**.
*   **Live Synthesis:** Real-time text-to-speech playback using **Piper TTS** (downloads models from Hugging Face).
*   **Text Preprocessing:** Enhance expressiveness with simple markup (pauses, emphasis).
*   **Audio Evaluation:** Optionally evaluate generated audio quality using **OpenAI Whisper**.

The project uses Python 3.11+, `uv` + Nix for environment management, `just` for tasks, and includes Docker support.

<!-- Badges -->
[![Docker CI](https://github.com/h0ffmann/montaigne/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/h0ffmann/montaigne/actions/workflows/docker-publish.yml)(https://github.com/h0ffmann/montaigne/actions/workflows/docker-publish.yml)
[![Python CI](https://github.com/h0ffmann/montaigne/actions/workflows/tts-tasks-ubuntu.yml/badge.svg)](https://github.com/h0ffmann/montaigne/actions/workflows/tts-tasks-ubuntu.yml)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Python Version](https://img.shields.io/badge/python-3.11-blue.svg)
![Code Style](https://img.shields.io/badge/code%20style-ruff-blue.svg)

## Prerequisites

Before you begin, ensure you have the following installed on your system:

1.  **Git:** For cloning the repository.
2.  **Nix:** The package manager with Flakes enabled. ([Installation Guide](https://nixos.org/download.html)).
3.  **`just`:** A handy command runner. ([Installation Guide](https://github.com/casey/just#installation)).
4.  **Docker Engine:** Required for building and running the Docker container. ([Installation Guide](https://docs.docker.com/engine/install/)).
5.  **(Highly Recommended for Performance)** **NVIDIA GPU & CUDA:** TTS (especially XTTS) and Whisper run *significantly* faster on a CUDA-enabled NVIDIA GPU.
    *   Ensure you have the appropriate NVIDIA drivers installed on your host.
    *   For Docker GPU support, you'll also need the **NVIDIA Container Toolkit**. ([Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)).
    *   **FFmpeg:** Required for audio processing (`yt-dlp`, `pydub`). Included in Nix env/Docker. Install manually otherwise (`sudo apt install ffmpeg`, `brew install ffmpeg`).

## Installation & Environment Setup

This project uses **Nix Flakes** to manage the development environment, ensuring reproducible builds and handling complex dependencies like PyTorch with CUDA.

1.  **Clone the Repository:**
    ```bash
    git clone <your-repo-url> # Replace with your repo URL
    cd montaigne
    ```

2.  **Enter the Development Environment:**
    Use `just nix` (or `nix develop --impure`) to enter the Nix shell. This command will:
    *   Download and build all Nix-managed dependencies (Python, PyTorch+CUDA, core libraries, etc.) based on `flake.nix`.
    *   Automatically create/activate a Python virtual environment (`.venv/`) using `uv`.
    *   Install remaining Python dependencies (like `TTS`, `bark`, `openai-whisper`, `yt-dlp`) into the venv using `uv`.
    *   Install the `montaigne` package itself in editable mode.
    ```bash
    just nix
    ```
    *The first time you run this, it might take a significant amount of time.* Subsequent runs are faster due to caching.

## Usage

Once inside the Nix development shell (`just nix`), you can use the `montaigne` CLI.

The main commands are `synthesize` (for batch file generation) and `live` (for real-time playback).

### Batch Synthesis (`synthesize`)

```bash
# Basic structure
montaigne synthesize --engine [xtts|bark] [ENGINE-ARGS] -o OUTPUT.WAV (-t "INPUT TEXT" | -f INPUT.TXT) [OTHER-ARGS]
```

**Common Arguments:**

*   `--engine {xtts|bark}`: TTS engine (default: `xtts`).
*   `--output-file PATH` / `-o PATH` (**Required**): Output WAV file path.
*   `--text TEXT` / `-t TEXT`: Input text string.
*   `--text-file PATH` / `-f PATH`: Input text file path.
*   `--language CODE` / `-l CODE`: Language code (default: `en`).
*   `--evaluate` / `-e`: Evaluate audio quality using Whisper STT.
*   `--cpu`: Force CPU use for TTS and evaluation.

**Engine-Specific Arguments (`synthesize`):**

*   **XTTS (`--engine xtts`):** (Requires one speaker input)
    *   `--speaker-wav PATH` / `-s PATH`: Path to reference WAV for voice cloning.
    *   `--voice-profile NAME`: Use a prebuilt voice profile (see list below).
    *   `--speaker-youtube-id ID`: YouTube video ID for voice cloning (downloads audio).
    *   `--speed FLOAT`: Adjust playback speed (default: 1.0).

*   **Bark (`--engine bark`):**
    *   `--speaker-prompt PROMPT`: Optional Bark speaker prompt (e.g., `en_speaker_1`).

**Prebuilt Voice Profiles (XTTS `synthesize` only):**

*   `bolsonaro`: Jair Bolsonaro - strong, authoritative tone
*   `lula`: Luiz Inácio Lula da Silva - charismatic, raspy voice  
- `supla`: Supla - distinctive rock voice
- `serginho`: Serginho Malandro - playful, energetic tone
- `bonner`: William Bonner - clear, professional news anchor
- `marilia`: Marília Gabriela - sophisticated, articulate
- `bk`: BK (Rapper) - urban, rhythmic speech pattern
- `maria_rita`: Maria Rita - smooth, melodic singing voice
- `clarice`: Clarice Lispector - thoughtful, philosophical tone
- `abujamra`: Luiz Fernando Abujamra - deep, dramatic voice
- `ponde`: L.F. Ponde - slow, reflective philosophical tone
- `paulo_francis`: Paulo Francis - sophisticated, critical journalist
- `millor`: Millôr Fernandes - witty, ironic humorist
- `djavan`: Djavan - smooth, melodic musical voice
- `trump`: Donald Trump - distinctive, assertive tone
- `obama`: Barack Obama - calm, measured, charismatic tone
- `snowden`: Edward Snowden - clear, deliberate, slightly nasal tone
- `cillian`: Cillian Murphy - soft-spoken, intense Irish actor
- `rust_cohle`: Matthew McConaughey (Rust Cohle) - Southern drawl, philosophical

**`synthesize` Examples:**

1.  **Synthesize using XTTS with a speaker file:**
    ```bash
    # Ensure input/referencia_voz.wav exists
    montaigne synthesize --engine xtts -s input/referencia_voz.wav -t "Olá mundo!" -l pt -o output/xtts_pt.wav
    ```

2.  **Synthesize using XTTS with a voice profile and evaluate:**
    ```bash
    # Ensure input/trump_speech.txt exists
    montaigne synthesize --engine xtts --voice-profile trump -f input/trump_speech.txt -l en -o output/xtts_trump.wav --evaluate
    ```

3.  **Synthesize using Bark with English default voice:**
    ```bash
    montaigne synthesize --engine bark -t "Hello from the Bark engine. It sounds different!" -l en -o output/bark_en_default.wav
    ```

4.  **Synthesize using Bark with a specific French speaker prompt:**
    ```bash
    montaigne synthesize --engine bark --speaker-prompt fr_speaker_5 -t "Bonjour, ceci est un test avec Bark." -l fr -o output/bark_fr_speaker5.wav
    ```

5.  **Synthesize using XTTS with a YouTube video as speaker:**
    ```bash
    montaigne synthesize --engine xtts --speaker-youtube-id "dQw4w9WgXcQ" -t "Never gonna give you up." -l en -o output/xtts_youtube_rick.wav
    ```

### Live Synthesis (`live`)

This command uses the **Piper TTS** engine for real-time playback. It downloads voice models from Hugging Face Hub.

```bash
# Basic structure
montaigne live --piper-voice VOICE_NAME [--file INPUT_TXT | INTERACTIVE] [--cpu]
```

**Arguments:**

*   `--piper-voice VOICE_NAME` / `-v VOICE_NAME`: Piper voice model name from Hugging Face (e.g., `en_US-amy-low`, `pt_BR-faber-low`). Default: `en_US-amy-low`.
*   `--file PATH` / `-f PATH`: Read text line-by-line from a file instead of interactive input. Use `-` for stdin.
*   `--cpu`: Prefer CPU for Piper TTS.

**`live` Examples:**

1.  **Interactive session with default English voice:**
    ```bash
    montaigne live
    ```

2.  **Interactive session with a specific Portuguese voice:**
    ```bash
    montaigne live --piper-voice pt_BR-faber-medium
    ```

3.  **Read from a file:**
    ```bash
    echo "Hello from Piper." | montaigne live --file -
    # or
    montaigne live --file input/my_lines.txt
    ```

### Text Preprocessing Markup

You can embed simple tags in your input text (`--text` or in the `--text-file`) to influence the TTS output:

*   **Pauses:** `[p=FLOAT]` or `[pause=FLOAT]`

Adds a pause of approximately FLOAT seconds.

Example: Wait for it... [p=1.5] Done.

Implementation: Approximated by converting to punctuation (,, ., ...) which XTTS uses for rhythm.

Emphasis: *word* or **phrase**

Provides subtle emphasis.

Example: This is **really** important.

Implementation: Adds commas around the emphasized text (, really , important ,) to slightly alter rhythm.

*   **Tone Placeholders:** `[tone=NAME]text[/tone]`
    *   Marks sections for different tones (e.g., `gold`, `velvet`).
    *   **Limitation:** Currently logged but does not alter the synthesized voice.

## Task Runner (Justfile)

The `Justfile` provides convenient shortcuts for common development tasks. Ensure `just` is installed. Run these commands *after* entering the Nix shell (`just nix`).

*   `just --list`: Show all available commands.
*   `just run -- [ARGS...]`: Runs the `montaigne` CLI. Pass arguments after `--`.
    *   Example: `just run -- synthesize --engine bark -t "Hello" -o output/out.wav`
*   `just lint`: Checks code style using Ruff.
*   `just format`: Formats code using Ruff.
*   `just check`: Runs both lint and format.
*   `just test`: Runs tests using pytest (assumes tests are in `tests/`).
*   `just build_package`: Builds the Python package (wheel and sdist) into `dist/`.
*   `just clean`: Removes build artifacts and `__pycache__`.
*   `just clean_all`: Runs `clean`.
*   `just debug`: Performs a simple XTTS synthesis test run (CPU).
*   `just debug_gpu`: Checks PyTorch CUDA availability.
*   `just docker_build`: Builds the Docker image.
*   `just docker_run -- [ARGS...]`: Runs a default XTTS synthesis task inside Docker (CPU).
*   `just docker_run_gpu -- [ARGS...]`: Runs the application inside Docker with GPU support.
*   `just docker_check`: Checks Docker daemon status and NVIDIA runtime availability.

## Docker Usage

You can build and run Montaigne within a Docker container. Build the image first (requires Docker):

```bash
just docker_build
```
This builds an image tagged `montaigne:latest` and `montaigne:<git-short-hash>`.

**2. Prepare Input/Output Directories:**
Create `./input` and `./output` directories on your host. Place necessary input files (like speaker WAVs for XTTS) in `./input`.
```bash
mkdir -p input output
# Example: cp /path/to/your/speaker.wav ./input/
```

**3. Running the Container:**
Map your host directories to `/app/input` (read-only) and `/app/output` (read-write) inside the container. **Use container paths** (e.g., `/app/input/speaker.wav`) in your command arguments.

*   **Default XTTS Test (CPU):**
    ```bash
    just docker_run
    # Creates output/docker_default_run_output.wav on host.
    # Uses a dummy speaker file if input/speaker.wav is missing.
    ```
*   **Custom Synthesis (CPU):**
    ```bash
    # Example: Run Bark engine via docker run directly
    docker run --rm \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        montaigne:latest \
        synthesize --engine bark \
          --text "Hello from Docker and Bark." \
          --output-file /app/output/bark_docker_output.wav \
          --language en --cpu
    ```
*   **Running with GPU Support:** (Requires NVIDIA Container Toolkit on host)
    ```bash
    # Example: Synthesize using XTTS with GPU via just
    just docker_run_gpu -- synthesize --engine xtts \
        --text "Running faster with the GPU!" \
        --output-file /app/output/gpu_xtts_output.wav \
        --speaker-wav /app/input/my_speaker.wav \
        --language en
    ```
    Or use `docker run --gpus all ...` directly.

## Development

*   **Activate Environment:** Run `just nix` to enter the configured shell.
*   **Linting/Formatting:** Use `just check` or `just format`/`just lint`.
*   **Testing:** Add tests to `tests/` and run with `just test`.

## Limitations & Caveats

*   **Tone Tags:** `[tone=...]` tags are placeholders and do not currently affect the synthesized voice for either XTTS or Bark.
*   **Speaker WAV Quality (XTTS):** Voice quality heavily depends on the `--speaker-wav` quality. Use clear, noise-free recordings.
*   **Bark Speaker Prompts:** Finding effective `--speaker-prompt` values for Bark might require experimentation. See Bark documentation/examples.
*   **Performance:** TTS and Whisper evaluation are computationally intensive. Use a CUDA GPU for significant speedup.
*   **Evaluation Accuracy:** Whisper STT is accurate but not perfect. Scores indicate similarity but may not capture all nuances.
*   **Dependencies:** The Nix flake aims for reproducibility, but complex ML dependencies can have subtle issues.
*   **YouTube Download:** Dependent on `yt-dlp` and `ffmpeg`. Quality limited by source. Audio saved in `output-youtube/`.
*   **Piper Live Mode:** Requires `sounddevice` for playback and `huggingface-hub` for model downloads. Sentence splitting (`stream_speak`) is basic.

## License

This project itself is licensed under the **MIT License**.

**Component Licenses:**

*   **Coqui TTS (XTTSv2 Model):** Licensed under **MPL 2.0**. Requires accepting terms on first use. Review MPL 2.0 for commercial/distribution details.
*   **Suno AI Bark:** MIT License.
*   **OpenAI Whisper:** MIT License.
*   **Piper TTS:** Apache 2.0 License (check specific voice model licenses on HF Hub).
*   **yt-dlp:** Unlicense.
*   Other dependencies have their own licenses (check `uv.lock`).

## Acknowledgements

*   **Coqui TTS (XTTSv2):** For the powerful multilingual TTS model. ([Coqui TTS GitHub](https://github.com/coqui-ai/TTS))
*   **Suno AI Bark:** For the innovative generative TTS model. ([Bark GitHub](https://github.com/suno-ai/bark))
*   **OpenAI Whisper:** For the state-of-the-art STT model. ([Whisper GitHub](https://github.com/openai/whisper))
*   **Piper TTS / Rhasspy:** For the efficient local TTS engine. ([Piper GitHub](https://github.com/rhasspy/piper))
*   The creators of Nix, Just, uv, Ruff, Click, and other libraries used.
