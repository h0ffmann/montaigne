#!/bin/bash

# --- Configuração ---
PROJECT_NAME="montaigne"
PYTHON_SRC_DIR="src/${PROJECT_NAME}"
PYTHON_VERSION_REQ="==3.11" # ATUALIZADO para Python 3.11

# --- Verificação Preliminar ---
if [ -d "$PROJECT_NAME" ]; then
  echo "❌ Erro: O diretório '$PROJECT_NAME' já existe. Remova-o ou escolha outro nome."
  exit 1
fi

echo "🚀 Iniciando a criação do projeto '$PROJECT_NAME' (Python ${PYTHON_VERSION_REQ})..."

# --- Criação da Estrutura de Diretórios ---
echo "    📁 Criando estrutura de diretórios..."
mkdir -p "$PROJECT_NAME/$PYTHON_SRC_DIR"
cd "$PROJECT_NAME" || exit # Entra no diretório do projeto

# --- Criação dos Arquivos de Configuração e Código ---

# 1. pyproject.toml (Python 3.12, dev dependencies)
echo "    📄 Gerando pyproject.toml..."
cat << 'EOF' > pyproject.toml
[project]
name = "montaigne"
version = "0.1.0"
description = "CLI tool for TTS (XTTS) with text preprocessing (pauses, emphasis, tone tags) and evaluation (Whisper)."
authors = [{ name = "Matheus Hoffmann", email = "hoffmann[at]poli.ufrj.br" }]
requires-python = "==3.11"
dependencies = [
    "typer[all]>=0.9.0,<1.0.0",
    "TTS>=0.22.0",           # >=0.22.0 recomendado para compatibilidade Python >3.10
    "torch>=2.1.0",          # Verificar compatibilidade PyTorch com Python 3.12 e TTS
    "torchaudio>=2.1.0",
    "openai-whisper>=20231117",
    "rapidfuzz>=3.0.0",
]

[project.optional-dependencies]
dev = [
    "ruff>=0.1.0",    # Linter/Formatter
    "pytest>=7.0.0",  # Testing framework (adicionar testes depois)
    "build>=0.10.0",  # Para construir pacotes (wheels/sdists)
]

[project.scripts]
montaigne = "montaigne.main:app"

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[tool.ruff] # Configuração Ruff básica
line-length = 88
select = ["E", "F", "W", "I", "N", "C4", "UP", "ARG", "B"] # Seleção razoável de regras
ignore = ["B008"] # Exemplo: ignora B008 (Function call XYZ...) se for comum com Typer

[tool.ruff.format]
quote-style = "double"
EOF

# 2. src/montaigne/__init__.py (Vazio)
echo "    📄 Gerando src/${PROJECT_NAME}/__init__.py..."
touch "${PYTHON_SRC_DIR}/__init__.py"

# 3. src/montaigne/preprocessing.py (Sem mudanças desde a última versão com tones)
echo "    📄 Gerando src/${PROJECT_NAME}/preprocessing.py..."
cat << 'EOF' > "${PYTHON_SRC_DIR}/preprocessing.py"
import re
import logging

logger = logging.getLogger(__name__)
SUPPORTED_TONES = ["gold", "velvet", "silver", "bronze", "neutral"]

def preprocess_text_for_tts(text: str) -> str:
    processed_text = text
    original_for_logging = text[:150]

    # 1. Processar Tones: Registrar e Remover Tags
    def tone_replacer(match):
        tone = match.group(1).lower()
        content = match.group(2)
        if tone not in SUPPORTED_TONES:
            logger.warning(f"Unsupported tone '{tone}'. Using neutral. Text: '{content[:50]}...'")
            return content
        else:
            logger.info(f"Detected tone tag: [{tone}] for text: '{content[:50]}...'")
            return content # Remove as tags [tone]...[/tone]
    processed_text = re.sub(r'\[tone=([a-zA-Z]+)\](.*?)\[/tone\]', tone_replacer, processed_text, flags=re.IGNORECASE | re.DOTALL)

    # 2. Ênfase: Adiciona vírgulas
    processed_text = re.sub(r'\*\*(.*?)\*\*', r', \1 ,', processed_text, flags=re.DOTALL)
    processed_text = re.sub(r'\*(.*?)\*', r', \1 ,', processed_text, flags=re.DOTALL)

    # 3. Pausas: Converte para pontuação
    def pause_replacer(match):
        try:
            duration = float(match.group(1))
            if duration <= 0.1: return ""
            elif duration <= 0.4: return ","
            elif duration <= 0.8: return ". "
            else: return ". . ."
        except ValueError:
            logger.warning(f"Invalid pause format: {match.group(0)}. Skipping.")
            return ""
    processed_text = re.sub(r'\[(?:p|pause)=(\d+(?:\.\d+)?)\]', pause_replacer, processed_text, flags=re.IGNORECASE)

    # 4. Limpeza Final
    processed_text = re.sub(r'\s+', ' ', processed_text)
    processed_text = re.sub(r'\s*([,.!?])\s*', r'\1 ', processed_text)
    processed_text = re.sub(r'([,.!?]\s*){2,}', r'\1 ', processed_text)
    processed_text = processed_text.replace(' .', '.').replace(' ,', ',')
    processed_text = processed_text.strip()

    logger.info(f"Original text sample: '{original_for_logging}...'")
    logger.info(f"Processed text sample: '{processed_text[:150]}...'")
    return processed_text
EOF

# 4. src/montaigne/tts_engine.py (Sem mudanças funcionais)
echo "    📄 Gerando src/${PROJECT_NAME}/tts_engine.py..."
cat << 'EOF' > "${PYTHON_SRC_DIR}/tts_engine.py"
import logging
import torch
from TTS.api import TTS
from pathlib import Path
import time
import warnings

logger = logging.getLogger(__name__)
XTTS_MODEL_NAME = "tts_models/multilingual/multi-dataset/xtts_v2"

class TTSEngine:
    def __init__(self, use_cuda: bool = True):
        self.device = "cuda" if use_cuda and torch.cuda.is_available() else "cpu"
        logger.info(f"Initializing TTS engine on device: {self.device}")
        if self.device == "cpu":
            logger.warning("CUDA not available/selected. TTS inference will be slow.")
        self.model = self._load_model()

    def _load_model(self):
        try:
            start_time = time.time()
            # Suppress specific UserWarnings if necessary during model loading
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                model = TTS(model_name=XTTS_MODEL_NAME, progress_bar=True).to(self.device)
            end_time = time.time()
            logger.info(f"TTS model '{XTTS_MODEL_NAME}' loaded in {end_time - start_time:.2f} seconds.")
            return model
        except Exception as e:
            logger.exception(f"Failed to load TTS model: {XTTS_MODEL_NAME}")
            raise RuntimeError(f"Could not initialize TTS model '{XTTS_MODEL_NAME}'. Check logs, dependencies, Python version compatibility with PyTorch/TTS.") from e

    def synthesize(self, text: str, speaker_wav: str, language: str, output_path: Path, speed: float = 1.0):
        if not Path(speaker_wav).is_file():
            logger.error(f"Speaker reference file not found: {speaker_wav}")
            raise FileNotFoundError(f"Speaker reference file not found: {speaker_wav}")

        logger.info(f"Synthesizing audio to: {output_path.name}")
        logger.info(f"Params: Lang={language}, Speed={speed}, Speaker={Path(speaker_wav).name}")
        logger.debug(f"Full Text Length: {len(text)} chars")

        try:
            start_time = time.time()
            self.model.tts_to_file(
                text=text, speaker_wav=str(speaker_wav), language=language,
                file_path=str(output_path), speed=speed, split_sentences=True
            )
            end_time = time.time()
            logger.info(f"Synthesis complete in {end_time - start_time:.2f} seconds.")
            print(f"✅ Audio successfully saved to: {output_path}")
            return True
        except Exception as e:
            logger.exception(f"TTS synthesis failed")
            print(f"❌ Error during TTS synthesis: {e}")
            if output_path.exists():
                try: output_path.unlink(missing_ok=True) # Py 3.8+
                except OSError: pass
            return False
EOF

# 5. src/montaigne/evaluation.py (Sem mudanças funcionais)
echo "    📄 Gerando src/${PROJECT_NAME}/evaluation.py..."
cat << 'EOF' > "${PYTHON_SRC_DIR}/evaluation.py"
import logging
import whisper
import rapidfuzz
from pathlib import Path
import torch
import time
import warnings

logger = logging.getLogger(__name__)
WHISPER_MODEL_NAME = "base"

class AudioEvaluator:
    def __init__(self, use_cuda: bool = True):
        self.device = "cuda" if use_cuda and torch.cuda.is_available() else "cpu"
        logger.info(f"Initializing Whisper STT model ({WHISPER_MODEL_NAME}) on device: {self.device}")
        if self.device == "cpu":
             logger.warning("CUDA not available/selected. Whisper STT evaluation will run on CPU.")
        self.model = self._load_model()

    def _load_model(self):
        try:
            start_time = time.time()
            # Suppress potential UserWarnings from Whisper/PyTorch internals
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                model = whisper.load_model(WHISPER_MODEL_NAME, device=self.device)
            end_time = time.time()
            logger.info(f"Whisper model ({WHISPER_MODEL_NAME}) loaded in {end_time - start_time:.2f} seconds.")
            return model
        except Exception as e:
            logger.exception(f"Failed to load Whisper model: {WHISPER_MODEL_NAME}")
            raise RuntimeError(f"Could not initialize Whisper STT model '{WHISPER_MODEL_NAME}'. Check dependencies, model download path.") from e

    def evaluate_audio(self, audio_path: Path, target_text: str) -> tuple[float, str] | None:
        if not audio_path.is_file():
            logger.error(f"Evaluation failed: Audio file not found at {audio_path}")
            return None

        logger.info(f"Evaluating audio quality: Transcribing {audio_path.name}...")
        try:
            start_time = time.time()
            result = self.model.transcribe(str(audio_path), fp16=(self.device == 'cuda'))
            transcribed_text = result["text"]
            end_time = time.time()
            logger.info(f"Transcription finished in {end_time - start_time:.2f} seconds.")

            if not transcribed_text:
                 logger.warning("Whisper returned an empty transcription.")
                 return 0.0, ""

            norm_transcribed = transcribed_text.lower().strip()
            norm_target = target_text.lower().strip()
            similarity_score = rapidfuzz.fuzz.ratio(norm_target, norm_transcribed)
            logger.info(f"Evaluation Similarity Score: {similarity_score:.2f}%")

            return similarity_score, transcribed_text

        except Exception as e:
            logger.exception(f"Whisper transcription failed for {audio_path.name}")
            print(f"❌ Error during Whisper transcription: {e}")
            return None
EOF

# 6. src/montaigne/main.py (Sem mudanças funcionais significativas, apenas nome/log)
echo "    📄 Gerando src/${PROJECT_NAME}/main.py..."
# Conteúdo idêntico à última versão em termos de lógica da CLI.
cat << 'EOF' > "${PYTHON_SRC_DIR}/main.py"
import typer
from pathlib import Path
import logging
import sys
import time

logging.basicConfig(
    level=logging.INFO, format='%(asctime)s [%(levelname)-7s] [%(name)-20s] %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("montaigne.cli")

try:
    from .preprocessing import preprocess_text_for_tts
    from .tts_engine import TTSEngine
    from .evaluation import AudioEvaluator
except ImportError as e:
    logger.critical(f"CRITICAL: Import error ({e}). Did you install with 'uv pip install -e .[dev]'?", exc_info=True)
    sys.exit(1)

tts_engine_instance = None
evaluator_instance = None

def get_tts_engine(use_cuda: bool):
    global tts_engine_instance
    if tts_engine_instance is None:
        logger.info("Initializing TTS Engine (XTTS)...")
        tts_engine_instance = TTSEngine(use_cuda=use_cuda)
    return tts_engine_instance

def get_evaluator(use_cuda: bool):
    global evaluator_instance
    if evaluator_instance is None:
        logger.info("Initializing Audio Evaluator (Whisper)...")
        evaluator_instance = AudioEvaluator(use_cuda=use_cuda)
    return evaluator_instance

app = typer.Typer(name="montaigne", help="""🚀 Montaigne TTS: Synthesizes speech using XTTS...""", pretty_exceptions_show_locals=False)

@app.command()
def synthesize(
    text: str = typer.Option(None, "--text", "-t", help="Text to synthesize directly."),
    input_file: Path = typer.Option(None, "--input-file", "-i", help="Path to a text file.", exists=True, file_okay=True, dir_okay=False, readable=True, resolve_path=True),
    output_file: Path = typer.Option(..., "--output-file", "-o", help="Path to save the output WAV audio file.", writable=True, resolve_path=True),
    speaker_wav: Path = typer.Option(..., "--speaker-wav", "-s", help="Path to a reference WAV file.", exists=True, file_okay=True, dir_okay=False, readable=True, resolve_path=True),
    language: str = typer.Option("en", "--language", "-l", help="Language code for TTS."),
    speed: float = typer.Option(1.0, "--speed", help="Adjust playback speed."),
    evaluate: bool = typer.Option(False, "--evaluate", "-e", help="Evaluate audio quality using Whisper STT."),
    cpu: bool = typer.Option(False, "--cpu", help="Force CPU for TTS and evaluation.")
):
    start_total_time = time.time()
    use_cuda = not cpu
    logger.info(f"Starting Montaigne TTS process. CUDA enabled: {use_cuda}")

    if not (text or input_file) or (text and input_file): print("❌ Error: Provide either --text OR --input-file."); raise typer.Exit(code=1)

    input_content: str; source_name: str
    if input_file:
        try: input_content = input_file.read_text('utf-8'); source_name = input_file.name; logger.info(f"Read {len(input_content)} chars from: {source_name}")
        except Exception as e: print(f"❌ Error reading {input_file}: {e}"); raise typer.Exit(code=1)
    else: input_content = text; source_name = "CLI"; logger.info(f"Read {len(input_content)} chars from {source_name}.")

    if not input_content.strip(): print("❌ Error: Input text is empty."); raise typer.Exit(code=1)

    print("📝 Preprocessing text..."); processed_text = preprocess_text_for_tts(input_content)
    if not processed_text.strip(): print("❌ Error: Text empty after preprocessing."); raise typer.Exit(code=1)

    print(f"🎙️ Starting synthesis (Lang: {language}, Speaker: {speaker_wav.name}, Target: {output_file.name})..."); synthesis_successful = False
    try:
        engine = get_tts_engine(use_cuda); synthesis_successful = engine.synthesize(text=processed_text, speaker_wav=str(speaker_wav), language=language, output_path=output_file, speed=speed)
    except FileNotFoundError as e: print(f"❌ Error: {e}"); raise typer.Exit(code=1)
    except RuntimeError as e: print(f"❌ TTS Engine Error: {e}"); raise typer.Exit(code=1)
    except Exception: raise typer.Exit(code=1)

    if synthesis_successful and evaluate:
        print("\n" + "📊 Starting audio evaluation (Whisper STT)...")
        try:
            evaluator = get_evaluator(use_cuda); evaluation_result = evaluator.evaluate_audio(output_file, processed_text)
            if evaluation_result: score, transcript = evaluation_result; print(f"    Transcript Sample: '{transcript[:100].strip()}...'"); print(f"    🎯 Similarity: {score:.2f}%")
            else: print("    ⚠️ Evaluation incomplete (transcription error?).")
        except RuntimeError as e: print(f"❌ Evaluator Error: {e}")
        except Exception as e: logger.exception("Unexpected evaluation error."); print(f"❌ Unexpected eval error: {e}")
    elif not synthesis_successful: print("\n" + "⚠️ Skipping evaluation (synthesis failed).")

    total_duration = time.time() - start_total_time
    print(f"\n✨ Montaigne process finished in {total_duration:.2f} seconds.")
    if not synthesis_successful: raise typer.Exit(code=1)

if __name__ == "__main__":
    app()
EOF

# --- NOVO: Criação do Justfile ---
echo "    🚀 Gerando Justfile (para tarefas comuns)..."
cat << 'EOF' > Justfile
# -*- mode: conf -*-

# Justfile for the Montaigne TTS project

# Default task (optional, runs if you just type `just`)
default: run -- --help

# === Environment & Dependencies ===
# Define VENV_DIR relative to the Justfile location
VENV_DIR := ".venv"
PYTHON   := "{{VENV_DIR}}/bin/python"
UV       := "uv" # Assumes uv is in PATH

# Setup the virtual environment and install dependencies
setup: vendor_install install_editable

# Create virtualenv if it doesn't exist
create_venv:
    @if [ ! -d "{{VENV_DIR}}" ]; then \
        echo "Creating virtualenv at {{VENV_DIR}}..."; \
        {{UV}} venv {{VENV_DIR}} --python 3.11 || exit 1; \
        echo "Virtualenv created."; \
    else \
        echo "Virtualenv already exists."; \
    fi

# Install dependencies using uv pip sync (faster)
vendor_sync: create_venv
    @echo "Syncing dependencies with uv..."
    @{{UV}} pip sync pyproject.toml --python "{{VENV_DIR}}/bin/python" --require-hashes

# Install dependencies using uv pip install (alternative, more flexible for installs)
vendor_install: create_venv
    @echo "Installing dependencies with uv pip install..."
    # Install runtime and dev dependencies
    @{{UV}} pip install --python "{{VENV_DIR}}/bin/python" -r requirements.txt # Assumes you might generate one, fallback
    @{{UV}} pip install --python "{{VENV_DIR}}/bin/python" --all-extras -e . # Or use -e '.[dev]'

# Install the package in editable mode with dev extras
install_editable: create_venv
    @echo "Installing project in editable mode with dev dependencies..."
    @{{UV}} pip install --python "{{VENV_DIR}}/bin/python" -e '.[dev]'

# Alias for easier install command
install: install_editable

# === Linting & Formatting ===
lint:
    @echo "Running Ruff linter..."
    @{{PYTHON}} -m ruff check .

format:
    @echo "Running Ruff formatter..."
    @{{PYTHON}} -m ruff format .

check: lint format
    @echo "Lint and format checks passed."

# === Testing ===
# Add actual tests in a `tests/` directory later
test available=check_venv_cmd('pytest'):
    @echo "Running tests with pytest..."
    @{{PYTHON}} -m pytest tests/ # Assumes tests are in tests/

# === Running the Application ===
# Example run command - pass arguments after `--`
# Usage: just run -- --text "Hello" --output-file o.wav --speaker-wav s.wav -l en
run *ARGS: available=check_venv_cmd('montaigne')
    @echo "Running Montaigne CLI..."
    @{{PYTHON}} -m {{PROJECT_NAME}}.main {{ARGS}}

# === Building the Package ===
# Requires `build` package installed (via [dev] extras)
build available=check_venv_cmd('build'):
    @echo "Building wheel and sdist..."
    @{{PYTHON}} -m build

# === Cleaning ===
clean_pycache:
    @echo "Removing __pycache__ directories..."
    @find . -type d -name "__pycache__" -exec rm -r {} +
    @find . -type f -name "*.py[co]" -delete

clean_build:
    @echo "Removing build artifacts..."
    @rm -rf build/ dist/ *.egg-info/ htmlcov/ .coverage* .pytest_cache/

clean_venv:
    @echo "Removing virtual environment ({{VENV_DIR}})..."
    @rm -rf {{VENV_DIR}}

# Full clean including virtualenv
clean: clean_pycache clean_build
    @echo "Project directories cleaned."

# Deep clean including venv
clean_all: clean clean_venv
    @echo "Full clean including virtualenv completed."

# === Docker ===
DOCKER_IMAGE_NAME := "{{PROJECT_NAME}}"
DOCKER_TAG        := "latest"

docker_build:
    @echo "Building Docker image {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}..."
    @docker build -t "{{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}}" .

# Example docker run - requires mapping input/output
# Usage: just docker_run -- --text "Docker test" --output-file /app/output/docker_out.wav --speaker-wav /app/input/speaker.wav -l en
# Make sure to `mkdir input output` and place speaker.wav in `input/` first!
docker_run *ARGS:
    @echo "Running Docker container (mapping ./input:/app/input, ./output:/app/output)..."
    @mkdir -p ./input ./output # Ensure host directories exist
    @docker run --rm \
        -v "$(pwd)/input:/app/input:ro" \
        -v "$(pwd)/output:/app/output:rw" \
        {{DOCKER_IMAGE_NAME}}:{{DOCKER_TAG}} {{ARGS}}

# Helper function to check if command exists in venv
check_venv_cmd(cmd) := `{{PYTHON}} -m {{cmd}} --version > /dev/null 2>&1 || (echo "Command '{{cmd}}' not found in venv. Run 'just install'?" && exit 1)`
EOF

# --- NOVO: Criação do Dockerfile ---
echo "    🐳 Gerando Dockerfile..."
cat << 'EOF' > Dockerfile
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
EOF

# --- Criação do .gitignore (sem mudanças) ---
echo "    📄 Gerando .gitignore..."
# (Conteúdo do .gitignore omitido para brevidade - use a versão anterior)
cat << EOF > .gitignore
# Ambientes Virtuais e Dependências Locais
.venv/
venv/
ENV/
env/
*/.venv/
*/venv/
*/ENV/
*/env/
lib/
lib64/
include/
share/
pip-wheel-metadata/

# Python cache/compiled files
__pycache__/
*.py[cod]
*$py.class

# Distribution / packaging
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST

# PyInstaller
*.manifest
*.spec

# Jupyter Notebook
.ipynb_checkpoints

# Unit test / coverage reports
htmlcov/
.tox/
.nox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
*.py,cover
.hypothesis/
.pytest_cache/
cover/

# Type checking
.mypy_cache/
.pyre/
.pytype/

# IDEs and Editors
.vscode/
.idea/
*.suo
*.ntvs*
*.njsproj
*.sln
*.sw?

# macOS
.DS_Store

# Logs e Dados Temporários/Saída
logs/
*.log
*.log.*
*.wav
*.mp3
output.*
output/
results/
*.pt
*.onnx
input/

# Outros
*.bak
*.tmp
uv.lock # uv lock file
EOF

# --- Instruções Finais Atualizadas ---
echo ""
echo "✅ Projeto '$PROJECT_NAME' (Python ${PYTHON_VERSION_REQ}) criado com sucesso!"
echo "   Inclui Justfile e Dockerfile."
echo ""
echo "➡️  Próximos Passos:"
echo ""
echo "1.  **Instale Ferramentas Externas (se não as tiver):**"
echo "    -   **Just:** Task runner. Veja: https://github.com/casey/just#installation"
echo "    -   **Docker:** Containerization engine. Veja: https://docs.docker.com/engine/install/"
echo "    -   **Git:** Controle de versão."
echo ""
echo "2.  **Navegue até o diretório do projeto:**"
echo "    cd ${PROJECT_NAME}"
echo ""
echo "3.  **(Recomendado) Revise `pyproject.toml`:**"
echo "    -   Verifique as versões das dependências (PyTorch/TTS com Python 3.12)."
echo "    -   Preencha 'authors'."
echo ""
echo "4.  **Use `Just` para configurar o ambiente e instalar dependências:**"
echo "    just setup  # Cria .venv e instala tudo (pode demorar!)"
echo "    # Alternativa: just vendor_install"
echo "    # Ative o venv manualmente se precisar: source .venv/bin/activate"
echo ""
echo "5.  **Use `Just` para tarefas comuns:**"
echo "    just run -- --help  # Ver ajuda da CLI"
echo "    just lint           # Checar código com Ruff"
echo "    just format         # Formatar código com Ruff"
echo "    just build          # Criar pacote (wheel/sdist)"
echo "    just clean          # Limpar arquivos gerados (sem o venv)"
echo "    just clean_all      # Limpar tudo (incluindo venv)"
echo ""
echo "6.  **Teste a CLI (Exemplo):**"
echo "    # (Certifique-se que 'referencia.wav' existe ou ajuste o caminho)"
echo "    just run -- --text \"Teste [p=0.3] com Justfile e Docker.\" \\"
echo "               --output-file saida_just.wav \\"
echo "               --speaker-wav caminho/para/referencia.wav \\"
echo "               --language pt --evaluate"
echo ""
echo "7.  **Docker - Construir a Imagem:**"
echo "    just docker_build  # Ou: docker build -t ${PROJECT_NAME} ."
echo ""
echo "8.  **Docker - Rodar o Contêiner:**"
echo "    # Crie diretórios input/output no seu host"
echo "    mkdir -p input output"
echo "    # Coloque seu speaker wav em ./input/ (ex: ./input/speaker.wav)"
echo "    # Rode, mapeando os volumes (substitua speaker.wav e texto)"
echo "    just docker_run -- --text \"Rodando [p=0.5] dentro do Docker!\" \\"
echo "                       --output-file /app/output/docker_output.wav \\"
echo "                       --speaker-wav /app/input/speaker.wav \\"
echo "                       --language pt --evaluate"
echo "    # O áudio gerado estará em ./output/docker_output.wav no seu host."
echo ""
echo "    **IMPORTANTE (Docker & GPU):** A imagem Docker gerada é **CPU-only** por padrão."
echo "    Para usar GPU, você precisa do NVIDIA Container Toolkit instalado no host Docker"
echo "    e rodar o contêiner com a flag '--gpus all', por exemplo:"
echo "    docker run --rm --gpus all \\"
echo "               -v \"\$(pwd)/input:/app/input:ro\" \\"
echo "               -v \"\$(pwd)/output:/app/output:rw\" \\"
echo "               ${PROJECT_NAME}:latest --text \"Teste GPU...\" ..."
echo ""
echo "--- Instruções Git e GitHub (Repositório Privado) ---"
echo ""
echo "9.  Inicialize Git, adicione, commite:"
echo "    git init -b main && git add . && git commit -m \"feat: Initial project setup with Python 3.12, Justfile, Docker\""
echo ""
echo "10. Crie Repo Privado no GitHub (https://github.com/new):"
echo "    - Nome: ${PROJECT_NAME}"
echo "    - Privado, SEM README/gitignore/license."
echo ""
echo "11. Conecte e envie:"
echo "    git remote add origin SEU_URL_GITHUB_AQUI"
echo "    git push -u origin main"
echo ""
echo "🎉 Pronto! Explore os comandos do Justfile e o Dockerfile."

# --- Finalização ---
exit 0
