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
    *   Dependency & Environment Management: `uv` + Nix Flakes
    *   Task Runner: `just`
    *   Code Formatting/Linting: `ruff`
*   **Containerization:** Includes a `Dockerfile` for building and running the application in an isolated environment.

## ⚙️ Prerequisites

Before you begin, ensure you have the following installed on your system:

1.  **Git:** For cloning the repository.
2.  **Nix:** The package manager with Flakes enabled. ([Installation Guide](https://nixos.org/download.html)).
3.  **`just`:** A handy command runner. ([Installation Guide](https://github.com/casey/just#installation)).
4.  **Docker Engine:** Required for building and running the Docker container. ([Installation Guide](https://docs.docker.com/engine/install/)).
5.  **(Highly Recommended for Performance)** **NVIDIA GPU & CUDA:** TTS (especially XTTS) and Whisper run *significantly* faster on a CUDA-enabled NVIDIA GPU.
    *   Ensure you have the appropriate NVIDIA drivers installed on your host.
    *   For Docker GPU support, you'll also need the **NVIDIA Container Toolkit**. ([Installation Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)).

## 💾 Installation & Environment Setup

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
    *   Install remaining Python dependencies (like `TTS`, `bark`, `openai-whisper`) into the venv using `uv`.
    *   Install the `montaigne` package itself in editable mode.
    ```bash
    just nix
    ```
    *The first time you run this, it might take a significant amount of time to download and build everything.* Subsequent runs will be much faster due to Nix caching.

## 🚀 Usage

Once inside the Nix development shell (`just nix`), you can use the `montaigne` CLI.

**Basic Structure:**

```bash
# Select engine (xtts or bark), provide relevant args
montaigne synthesize --engine [xtts|bark] [ENGINE-SPECIFIC ARGS] --output-file OUTPUT_WAV (--text "INPUT TEXT" | --text-file INPUT_TXT)
```

**Key Arguments:**

*   `--engine {xtts|bark}`: Selects the Text-to-Speech engine. Defaults to `xtts`.
*   `--output-file PATH` / `-o PATH` (**Required**): Path to save the generated `.wav` audio file.
*   `--text TEXT` / `-t TEXT`: Text string to synthesize. Mutually exclusive with `--text-file`.
*   `--text-file PATH` / `-f PATH`: Path to a `.txt` file containing the text. Mutually exclusive with `--text`.
*   `--language CODE` / `-l CODE`: Language code (e.g., `en`, `pt`). Defaults to `en`. (Used by XTTS directly, used by Bark for generic voice prompt if `--speaker-prompt` isn't set).
*   `--evaluate` / `-e`: Flag to enable audio quality evaluation using Whisper STT.
*   `--cpu`: Flag to force CPU use for both TTS and evaluation.

**Engine-Specific Arguments:**

*   **XTTS (`--engine xtts`):**
    *   `--speaker-wav PATH` / `-s PATH`: Path to a reference WAV file for voice cloning. (Required if `--voice-profile` is not used).
    *   `--voice-profile NAME`: Use a prebuilt voice profile (e.g., 'lula', 'trump'). See list below. (Required if `--speaker-wav` is not used).
    *   `--speed FLOAT`: Adjust playback speed. Defaults to 1.0.
*   **Bark (`--engine bark`):**
    *   `--speaker-prompt PROMPT`: Optional. Provide a Bark speaker prompt (e.g., `en_speaker_1`, `fr_speaker_0`, or a custom voice history prompt). If not provided, a generic language prompt (like `en_speaker`) might be used if available for the specified `--language`, otherwise Bark defaults.
    *   *Note:* Bark does not use `--speaker-wav`, `--voice-profile`, or `--speed`.

**Prebuilt Voice Profiles (XTTS Only):**

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
