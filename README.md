# Montaigne TTS

Montaigne is a powerful command-line tool designed for generating high-quality Text-to-Speech (TTS) audio using pluggable engines like **Coqui XTTSv2** or **Suno AI Bark**. It offers features like voice cloning (XTTS), text preprocessing for enhanced expressiveness, and optional audio quality evaluation using **OpenAI Whisper**. The project is built with Python 3.11+, managed with `uv` and Nix, provides common tasks via `just`, and includes Docker support for containerization.

<!-- Optional Badges: Add your own -->
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Python Version](https://img.shields.io/badge/python-3.11-blue.svg)
![Code Style](https://img.shields.io/badge/code%20style-ruff-blue.svg)

## Features

*   **Pluggable TTS Engines:** Choose between different TTS models:
    *   **Coqui XTTSv2:** High-quality multilingual model with voice cloning capabilities (MPL 2.0 License).
        *   **Important:** First-time use requires accepting the Coqui TTS license terms when prompted during model download.
    *   **Suno AI Bark:** Generative model with support for various languages and voice characteristics via prompts (MIT License).
*   **Voice Cloning (Zero-Shot - XTTS Only):** Clone voices using just a short (~10-30 seconds) WAV file sample of the target voice with the XTTS engine.
*   **Text Preprocessing:** Enhance expressiveness with simple markup in your input text (works with both engines):
    *   Pauses: `[p=SECONDS]` or `[pause=SECONDS]` (e.g., `[p=0.5]`) for controlling rhythm.
    *   Emphasis: Surround words or phrases with `*asterisks*` or `**double asterisks**` for subtle emphasis.
    *   Tone Placeholders: Use `[tone=NAME]text[/tone]` (e.g., `[tone=gold]...[/tone]`). *Note: Currently recognized and logged, but does not alter the synthesized voice characteristics with XTTS.* Supported placeholders: `gold`, `velvet`, `silver`, `bronze`, `neutral`.
*   **Audio Quality Evaluation:** Optionally transcribe the generated audio using OpenAI Whisper (STT) and compare it to the input text using fuzzy string matching (rapidfuzz) to get a similarity score.
*   **Command-Line Interface:** Easy-to-use CLI built with Typer.
*   **Modern Python & Tooling:**
    *   Python >=3.11,<3.12
    *   Dependency & Environment Management: `uv`
    *   Task Runner: `just`
    *   Code Formatting/Linting: `ruff`
*   **Containerization:** Includes a `Dockerfile` for building and running the application in an isolated environment.

## ⚙️ Prerequisites

Before you begin, ensure you have the following installed on your system:

1.  **Git:** For cloning the repository.
2.  **Python:** Version 3.12 or higher.
3.  **`uv`:** The fast Python package installer and resolver. ([Installation Guide](https://github.com/astral-sh/uv#installation)).
4.  **`just`:** A handy command runner. ([Installation Guide](https://github.com/casey/just#installation)).
5.  **Docker Engine:** Required for building and running the Docker container. ([Installation Guide](https://docs.docker.com/engine/install/)).
6.  **(Highly Recommended for Performance)** **NVIDIA GPU & CUDA:** XTTS and Whisper run *significantly* faster on a CUDA-enabled NVIDIA GPU.
    *   Ensure you have the appropriate NVIDIA drivers installed.
    *   For Docker GPU support, you'll also need the **NVIDIA Container Toolkit**. ([Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)).

## 💾 Installation

1.  **Clone the Repository:**
    ```bash
    git clone <your-repo-url> # Replace with your repo URL
    cd montaigne
    ```

2.  **Set up Environment & Install Dependencies:**
    Use `just` to automatically create a virtual environment (`.venv/`) and install all necessary dependencies (including development tools like `ruff` and `pytest`).
    ```bash
    just setup
    ```
    *This command might take a while, especially when downloading PyTorch, TTS, and Whisper models for the first time.*

## 🚀 Usage

The primary way to use Montaigne is through its command-line interface.

**Basic Structure:**

```bash
montaigne [OPTIONS] --output-file OUTPUT_WAV --speaker-wav SPEAKER_WAV (--text "INPUT TEXT" | --input-file INPUT_TXT)


Key Arguments:

--output-file PATH / -o PATH (Required): Path to save the generated .wav audio file.

--speaker-wav PATH / -s PATH (Required): Path to a high-quality reference .wav file (ideally 10-30 seconds, clear, mono, without background noise) of the voice you want to clone/synthesize.

--text TEXT / -t TEXT: The text string you want to convert to speech directly. Mutually exclusive with `--text-file`.

--text-file PATH / -f PATH: Path to a .txt file containing the text you want to convert to speech. Mutually exclusive with `--text`.

--language CODE / -l CODE: Language code for the TTS model (e.g., en, pt, es, fr, de, it, ru, zh-cn). Defaults to 'en'.

--speed FLOAT: Adjust the playback speed factor (e.g., 1.0 is normal, 0.9 is slower, 1.1 is faster). Defaults to 1.0.

--evaluate / -e: Flag to enable audio quality evaluation using Whisper STT after synthesis.

--cpu: Flag to force the use of CPU for both TTS and evaluation, even if a GPU is available (will be much slower).

Prebuilt Voice Profiles:
- `bolsonaro`: Jair Bolsonaro - strong, authoritative tone
- `lula`: Luiz Inácio Lula da Silva - charismatic, raspy voice  
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

**Examples:**

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

Tone Placeholders: [tone=NAME]text[/tone]

Marks sections intended for different voice tones (e.g., gold, velvet, silver, bronze, neutral).

Example: The king spoke in a [tone=gold]royal[/tone] voice.

Limitation: The current XTTS backend does not change the voice based on these tags. They are logged during preprocessing but otherwise ignored in synthesis. The voice characteristic is primarily determined by the --speaker-wav.

🛠️ Task Runner (Justfile)

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

🐳 Docker Usage

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

🧑‍💻 Development

*   **Activate Environment:** Run `just nix` to enter the configured shell.
*   **Linting/Formatting:** Use `just check` or `just format`/`just lint`.
*   **Testing:** Add tests to `tests/` and run with `just test`.

⚠️ Limitations & Caveats

*   **Tone Tags:** `[tone=...]` tags are placeholders and do not currently affect the synthesized voice for either XTTS or Bark.
*   **Speaker WAV Quality (XTTS):** Voice quality heavily depends on the `--speaker-wav` quality. Use clear, noise-free recordings.
*   **Bark Speaker Prompts:** Finding effective `--speaker-prompt` values for Bark might require experimentation. See Bark documentation/examples.
*   **Performance:** TTS and Whisper evaluation are computationally intensive. Use a CUDA GPU for significant speedup.
*   **Evaluation Accuracy:** Whisper STT is accurate but not perfect. Scores indicate similarity but may not capture all nuances.
*   **Dependencies:** The Nix flake aims for reproducibility, but complex ML dependencies can still have subtle issues.

## 📄 License

This project itself is licensed under the **MIT License**.

**Component Licenses:**

*   **Coqui TTS (XTTSv2 Model):** Licensed under **MPL 2.0**. Requires accepting terms on first use. Review MPL 2.0 for commercial/distribution details.
*   **Suno AI Bark:** Licensed under the **MIT License**.
*   **OpenAI Whisper:** Licensed under the **MIT License**.
*   Other dependencies have their own licenses (check `uv.lock`).

🙏 Acknowledgements

*   **Coqui TTS (XTTSv2):** For the powerful multilingual TTS model. ([Coqui TTS GitHub](https://github.com/coqui-ai/TTS))
*   **Suno AI Bark:** For the innovative generative TTS model. ([Bark GitHub](https://github.com/suno-ai/bark))
*   **OpenAI Whisper:** For the state-of-the-art STT model. ([Whisper GitHub](https://github.com/openai/whisper))
*   The creators of Nix, Just, uv, Ruff, Click, and other libraries used.
