import click
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

@click.group(context_settings={'help_option_names': ['-h', '--help']})
def cli():
    """🚀 Montaigne TTS: Synthesizes speech using XTTS v2 with voice cloning."""
    pass

@cli.command()
@click.option('--text', '-t', help="Text to synthesize directly.")
@click.option('--input-file', '-i', type=click.Path(exists=True, file_okay=True, dir_okay=False, readable=True, path_type=Path), help="Path to a text file.")
@click.option('--output-file', '-o', type=click.Path(writable=True, path_type=Path), required=True, help="Path to save the output WAV audio file.")
@click.option('--speaker-wav', '-s', type=click.Path(exists=True, file_okay=True, dir_okay=False, readable=True, path_type=Path), required=True, help="Path to a reference WAV file.")
@click.option('--language', '-l', default="en", show_default=True, help="Language code for TTS.")
@click.option('--speed', type=float, default=1.0, show_default=True, help="Adjust playback speed.")
@click.option('--evaluate', '-e', is_flag=True, help="Evaluate audio quality using Whisper STT.")
@click.option('--cpu', is_flag=True, help="Force CPU for TTS and evaluation.")
def synthesize(
    voice_profile: str,
    text: str,
    input_file: Path,
    output_file: Path,
    speaker_wav: Path,
    language: str,
    speed: float,
    evaluate: bool,
    cpu: bool
):
    # Handle voice profile if specified
    if voice_profile:
        profile_path = get_voice_profile(voice_profile)
        if not profile_path:
            click.echo(f"❌ Could not load voice profile: {voice_profile}", err=True)
            sys.exit(1)
        speaker_wav = profile_path
    start_total_time = time.time()
    use_cuda = not cpu
    logger.info(f"Starting Montaigne TTS process. CUDA enabled: {use_cuda}")

    if not (text or input_file) or (text and input_file):
        raise click.UsageError("Provide either --text OR --input-file, but not both.")

    input_content: str; source_name: str
    if input_file:
        try: input_content = input_file.read_text('utf-8'); source_name = input_file.name; logger.info(f"Read {len(input_content)} chars from: {source_name}")
        except Exception as e: 
            click.echo(f"❌ Error reading {input_file}: {e}", err=True)
            sys.exit(1)
    else: input_content = text; source_name = "CLI"; logger.info(f"Read {len(input_content)} chars from {source_name}.")

    if not input_content.strip():
        click.echo("❌ Error: Input text is empty.", err=True)
        sys.exit(1)

    print("📝 Preprocessing text..."); processed_text = preprocess_text_for_tts(input_content)
    if not processed_text.strip():
        click.echo("❌ Error: Text empty after preprocessing.", err=True)
        sys.exit(1)

    print(f"🎙️ Starting synthesis (Lang: {language}, Speaker: {speaker_wav.name}, Target: {output_file.name})..."); synthesis_successful = False
    try:
        engine = get_tts_engine(use_cuda); synthesis_successful = engine.synthesize(text=processed_text, speaker_wav=str(speaker_wav), language=language, output_path=output_file, speed=speed)
    except FileNotFoundError as e:
        click.echo(f"❌ Error: {e}", err=True)
        sys.exit(1)
    except RuntimeError as e:
        click.echo(f"❌ TTS Engine Error: {e}", err=True)
        sys.exit(1)
    except Exception as e:
        logger.exception("Unexpected error during synthesis")
        click.echo(f"❌ Unexpected error: {e}", err=True)
        sys.exit(1)

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
    if not synthesis_successful:
        sys.exit(1)

if __name__ == "__main__":
    cli()
