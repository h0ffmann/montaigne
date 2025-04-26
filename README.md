# Montaigne TTS 🚀

Montaigne is a powerful command-line tool designed for generating high-quality Text-to-Speech (TTS) audio using the advanced **Coqui XTTSv2** model. It offers features like voice cloning from short audio samples, text preprocessing for enhanced expressiveness, and optional audio quality evaluation using **OpenAI Whisper**. The project is built with Python 3.12+, managed with `uv`, provides common tasks via `just`, and includes Docker support for containerization.

<!-- Optional Badges: Add your own -->
<!-- ![License](https://img.shields.io/badge/License-MIT-blue.svg) -->
<!-- ![Python Version](https://img.shields.io/badge/python-3.12+-blue.svg) -->
<!-- ![Build Status](...) -->
<!-- ![Code Style](https://img.shields.io/badge/code%20style-ruff-black.svg) -->

## ✨ Features

*   **High-Quality TTS:** Leverages the multilingual Coqui XTTSv2 model for natural-sounding speech generation.
*   **Voice Cloning (Zero-Shot):** Clone voices using just a short (~10-30 seconds) WAV file sample of the target voice.
*   **Text Preprocessing:** Enhance expressiveness with simple markup in your input text:
    *   Pauses: `[p=SECONDS]` or `[pause=SECONDS]` (e.g., `[p=0.5]`) for controlling rhythm.
    *   Emphasis: Surround words or phrases with `*asterisks*` or `**double asterisks**` for subtle emphasis.
    *   Tone Placeholders: Use `[tone=NAME]text[/tone]` (e.g., `[tone=gold]...[/tone]`). *Note: Currently recognized and logged, but does not alter the synthesized voice characteristics with XTTS.* Supported placeholders: `gold`, `velvet`, `silver`, `bronze`, `neutral`.
*   **Audio Quality Evaluation:** Optionally transcribe the generated audio using OpenAI Whisper (STT) and compare it to the input text using fuzzy string matching (rapidfuzz) to get a similarity score.
*   **Command-Line Interface:** Easy-to-use CLI built with Typer.
*   **Modern Tooling:**
    *   Python 3.12+
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

--text TEXT / -t TEXT: The text string you want to convert to speech directly.

--input-file PATH / -i PATH: Path to a .txt file containing the text you want to convert to speech. Use either --text or `--input-file*.

--language CODE / -l CODE: Language code for the TTS model (e.g., en, pt, es, fr, de, it, ru, zh-cn). Defaults to en.

--speed FLOAT: Adjust the playback speed factor (e.g., 1.0 is normal, 0.9 is slower, 1.1 is faster). Defaults to 1.0.

--evaluate / -e: Flag to enable audio quality evaluation using Whisper STT after synthesis.

--cpu: Flag to force the use of CPU for both TTS and evaluation, even if a GPU is available (will be much slower).

Examples:

Synthesize from direct text:

# Make sure referencia_voz.wav exists
montaigne -t "Olá mundo! [p=0.5] Este é um teste *simples*." -o saida_simples.wav -s ./referencia_voz.wav -l pt
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

Synthesize from a file and evaluate the result:

# Assuming entrada.txt and speaker_ref.wav exist
montaigne -i entrada.txt -o saida_avaliada.wav -s ./speaker_ref.wav -l en --evaluate
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

Synthesize with tone placeholders and slower speed:

montaigne --text "This [tone=gold]sounds premium[/tone], maybe. [p=0.8] And *this* is slower." \
          --output-file premium_slow.wav \
          --speaker-wav ./speaker_premium.wav \
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

Example: just run -- -t "Hello" -o out.wav -s ref.wav

just lint: Checks code style using Ruff.

just format: Formats code using Ruff.

just check: Runs both lint and format.

just test: Runs tests using pytest (assumes tests are in a tests/ directory).

just build: Builds the Python package (wheel and sdist) into the dist/ directory.

just clean: Removes build artifacts and __pycache__.

just clean_all: Runs clean and also removes the .venv directory.

just docker_build: Builds the Docker image (tags as montaigne:latest and montaigne:<git-hash>).

just docker_run -- [ARGS...]: Runs the application inside a Docker container (CPU only by default). Mounts ./input and ./output directories.

just docker_run_gpu -- [ARGS...]: Runs the application inside a Docker container with GPU support (requires NVIDIA Container Toolkit on host). Mounts ./input and ./output.

🐳 Docker Usage

You can build and run Montaigne within a Docker container for portability.

Build the Image:

just docker_build
# Or: docker build -t montaigne .
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

Prepare Input/Output Directories:
The Docker container expects input files (like the speaker WAV) to be in a directory mapped to /app/input and writes output files to a directory mapped to /app/output.

mkdir -p input output
cp /path/to/your/speaker.wav ./input/ # Copy your reference wav here
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

Run the Container (CPU):

# Example: Synthesize text and save to ./output/docker_out_cpu.wav on the host
just docker_run -- \
    --text "Hello from inside the Docker container!" \
    --output-file /app/output/docker_out_cpu.wav \
    --speaker-wav /app/input/speaker.wav \
    --language en \
    --evaluate
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END

The output file will appear in the ./output directory on your host machine.

Run the Container (GPU):
Requires the NVIDIA Container Toolkit to be installed on your Docker host.

# Example: Synthesize using the GPU
just docker_run_gpu -- \
    --text "Running much faster with the GPU!" \
    --output-file /app/output/docker_out_gpu.wav \
    --speaker-wav /app/input/speaker.wav \
    --language en
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END
🧑‍💻 Development

Install Dev Dependencies: Ensure you've run just setup or just install.

Activate Environment: source .venv/bin/activate (or equivalent for your OS).

Linting/Formatting: Use just check or just format/just lint.

Testing: Add tests to the tests/ directory and run with just test.

⚠️ Limitations & Caveats

Tone Tags: As mentioned, [tone=...] tags are placeholders and do not currently affect the synthesized XTTS voice. Voice characteristics depend entirely on the --speaker-wav.

Speaker WAV Quality: The quality and characteristics of the generated voice heavily depend on the quality of the --speaker-wav file. Use clear, noise-free recordings.

Performance: TTS and especially Whisper STT evaluation are computationally intensive. Using a CUDA-enabled GPU is highly recommended for reasonable performance. CPU execution will be significantly slower.

Evaluation Accuracy: Whisper STT is very accurate but not perfect. The similarity score provides an indication of quality but might not capture nuances perfectly. Highly stylized speech or poor audio quality might lead to lower scores.

Dependencies: Compatibility between specific versions of Python, PyTorch, CUDA, and Coqui TTS can sometimes be tricky. The versions in pyproject.toml are starting points.

📄 License

(Specify your chosen license here - e.g., MIT, Apache 2.0)

This project is licensed under the MIT License - see the LICENSE file for details (you'll need to create this file).

🙏 Acknowledgements

Coqui TTS (XTTSv2): For the powerful underlying TTS model. (Coqui TTS GitHub)

OpenAI Whisper: For the state-of-the-art Speech-to-Text model used in evaluation. (OpenAI Whisper GitHub)

The creators of Typer, uv, Just, Ruff, and other libraries used in this project.

IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
IGNORE_WHEN_COPYING_END