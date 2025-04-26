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
