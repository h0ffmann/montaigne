# Montaigne TTS

Montaigne is a powerful command-line tool designed for generating high-quality Text-to-Speech (TTS) audio using the advanced **Coqui XTTSv2** model. It offers features like voice cloning from short audio samples, text preprocessing for enhanced expressiveness, and optional audio quality evaluation using **OpenAI Whisper**. The project is built with Python 3.12+, managed with `uv`, provides common tasks via `just`, and includes Docker support for containerization.

<!-- Optional Badges: Add your own -->
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Python Version](https://img.shields.io/badge/python-3.11-blue.svg)
![Code Style](https://img.shields.io/badge/code%20style-ruff-blue.svg)

## Features

*   **High-Quality TTS:** Leverages the multilingual Coqui XTTSv2 model (MPL 2.0 License) for natural-sounding speech generation.
    *   **Important:** First-time use of the TTS model requires accepting the Coqui TTS license terms when prompted during model download.
*   **Voice Cloning (Zero-Shot):** Clone voices using just a short (~10-30 seconds) WAV file sample of the target voice.
*   **Text Preprocessing:** Enhance expressiveness with simple markup in your input text:
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

Examples:

Synthesize from direct text:

# Example using Portuguese ('pt')
# Make sure referencia_voz.wav exists
montaigne synthesize --text "Olá mundo! [p=0.5] Este é um teste *simples*." \
                     -o output/saida_simples.wav \
                     -s input/referencia_voz.wav \
                     -l pt

Synthesize from a file and evaluate the result:

# Assuming input/entrada.txt and input/speaker_ref.wav exist
montaigne synthesize --text-file input/entrada.txt \
                     -o output/saida_avaliada.wav \
                     -s input/speaker_ref.wav \
                     -l en \
                     --evaluate

Synthesize with tone placeholders and slower speed:

montaigne --text "This [tone=gold]sounds premium[/tone], maybe. [p=0.8] And *this* is slower." \
          --output-file output/premium_slow.wav \
          --speaker-wav input/speaker_premium.wav \
          --language en \
          --speed 0.85
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END
Text Preprocessing Markup

You can embed simple tags in your input text (--text or in the --input-file) to influence the TTS output:

Pauses: [p=FLOAT] or [pause=FLOAT]

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

The Justfile included provides convenient shortcuts for common development tasks. Install just if you haven't already.

just setup: Creates the virtualenv and installs all dependencies (runtime + dev).

just install: Ensures the package is installed in editable mode with dev dependencies (runs uv pip install -e '.[dev]').

just run -- [ARGS...]: Runs the montaigne CLI. Pass arguments after --.

Example: `just run -- synthesize -t "Hello" -o output/out.wav -s input/ref.wav`

just lint: Checks code style using Ruff.

just format: Formats code using Ruff.

just check: Runs both lint and format.

test: Runs tests using pytest (assumes tests are in a tests/ directory). *Currently requires setting up tests.*

build_package: Builds the Python package (wheel and sdist) into the dist/ directory using the `build` tool.

just test: Runs tests using pytest (assumes tests are in a tests/ directory).

clean: Removes build artifacts and __pycache__.

clean_venv: Removes the `.venv` directory.
just clean: Removes build artifacts and __pycache__.

just clean_all: Runs clean and also removes the .venv directory.

just debug: Runs repomix to generate `repo-content.txt` and then performs a simple synthesis test run (useful for testing basic setup).

just docker_build: Builds the Docker image (tags as montaigne:latest and montaigne:<git-hash>).

just docker_run -- [ARGS...]: Runs a default synthesis task inside a Docker container (CPU only). Mounts ./input and ./output directories. Pass extra Montaigne args after `--`.

just docker_run_gpu -- [ARGS...]: Runs the application inside a Docker container with GPU support (requires NVIDIA Container Toolkit on host). Mounts ./input and ./output. You must provide the full `synthesize` command and arguments after `--`.

🐳 Docker Usage

You can build and run Montaigne within a Docker container for portability and dependency isolation.

**1. Build the Image:**

Build the image using `just`:
```bash
just docker_build
```

This command builds an image tagged as montaigne:latest and montaigne:<git-short-hash>. Dependencies are installed during this build process.

**2. Prepare Input/Output Directories:**

When running Montaigne in Docker, you need to explicitly map directories from your host machine to the container using the `-v` flag. The container expects:

*   Input files (like `--speaker-wav` or `--text-file`) to be in a directory mapped to `/app/input` inside the container.
*   Output files (specified by `--output-file`) to be written to a directory mapped to `/app/output` inside the container.

Create these directories on your host if they don't exist:
```bash
mkdir -p input output
# Copy your required input files (e.g., your speaker reference) here:
cp /path/to/your/speaker_reference.wav ./input/my_speaker.wav
cp /path/to/your/input_script.txt ./input/my_script.txt
```

**3. Running the Container**

**Important:** When specifying file paths as arguments (`--speaker-wav`, `--text-file`, `--output-file`) to Montaigne inside Docker, you must use the container's internal paths (e.g., `/app/input/my_speaker.wav`, `/app/output/result.wav`), not your host machine paths (`./input/my_speaker.wav`).

**Running the Default Test (CPU):**
The `just docker_run` command now runs a basic synthesis test using CPU:
```bash
just docker_run
# This will create output/docker_default_run_output.wav on your host
```
It uses a generated test tone if `input/speaker.wav` isn't found on the host. You can pass extra Montaigne arguments after `--`:
```bash
# Example: Evaluate the default run and use Portuguese
just docker_run -- --evaluate --language pt
```

**Running a Custom Synthesis (CPU):**
To run a specific synthesis, provide the `synthesize` command and arguments directly to `docker run` (or use `just docker_run -- ...` overriding defaults).
```bash
# Example using docker run directly
docker run --rm \
    -v "$(pwd)/input:/app/input:ro" \
    -v "$(pwd)/output:/app/output:rw" \
    montaigne:latest \
    synthesize \
      --text-file /app/input/my_script.txt \
      --speaker-wav /app/input/my_speaker.wav \
      --output-file /app/output/custom_output.wav \
      --language en \
      --evaluate \
      --cpu
```
The generated file `custom_output.wav` will appear in your host's `./output` directory.

**Running with GPU Support:**
Requires the NVIDIA Container Toolkit installed on your host. Use the `just docker_run_gpu` recipe, passing the full command you want to run after `--`:
```bash
# Example: Synthesize using the GPU and a custom speaker
just docker_run_gpu -- synthesize \
    --text "Running faster with the GPU!" \
    --output-file /app/output/gpu_output.wav \
    --speaker-wav /app/input/my_speaker.wav \
    --language en
```
Or use `docker run` directly with the `--gpus all` flag:
```bash
docker run --rm --gpus all \
    -v "$(pwd)/input:/app/input:ro" \
    -v "$(pwd)/output:/app/output:rw" \
    montaigne:latest \
    synthesize \
      # Your synthesize arguments here using /app/input and /app/output paths
```

🧑‍💻 Development

Install Dev Dependencies: Ensure you've run `just setup` or `just install`.

Activate Environment: source .venv/bin/activate (or equivalent for your OS).

Linting/Formatting: Use just check or just format/just lint.

Testing: Add tests to the tests/ directory and run with just test.

⚠️ Limitations & Caveats

Tone Tags: As mentioned, [tone=...] tags are placeholders and do not currently affect the synthesized XTTS voice. Voice characteristics depend entirely on the --speaker-wav.

Speaker WAV Quality: The quality and characteristics of the generated voice heavily depend on the quality of the --speaker-wav file. Use clear, noise-free recordings.

Performance: TTS and especially Whisper STT evaluation are computationally intensive. Using a CUDA-enabled GPU is highly recommended for reasonable performance. CPU execution will be significantly slower.

Evaluation Accuracy: Whisper STT is very accurate but not perfect. The similarity score provides an indication of quality but might not capture nuances perfectly. Highly stylized speech or poor audio quality might lead to lower scores.

Dependencies: Compatibility between specific versions of Python, PyTorch, CUDA, and Coqui TTS can sometimes be tricky. The versions in pyproject.toml are starting points.

## 📄 License

This project itself is licensed under the **MIT License** - see the `LICENSE` file for details. (You'll need to create this file and confirm if MIT is correct).

**Component Licenses:**

*   **Coqui TTS (XTTSv2 Model):** The underlying TTS model is provided by Coqui and is licensed under the **Mozilla Public License 2.0 (MPL 2.0)**. Usage requires accepting their terms upon first model download. Please review the MPL 2.0 license terms, especially regarding distribution and modifications if you plan to redistribute or use this commercially.
*   **OpenAI Whisper:** The Whisper model used for evaluation is provided by OpenAI and has its own license terms (typically MIT).
*   Other dependencies have their own respective licenses (check `pyproject.toml` and `uv.lock`).

🙏 Acknowledgements

Coqui TTS (XTTSv2): For the powerful underlying TTS model. (Coqui TTS GitHub)

OpenAI Whisper: For the state-of-the-art Speech-to-Text model used in evaluation. (OpenAI Whisper GitHub)

The creators of Click, uv, Just, Ruff, and other libraries used in this project.
