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
    from .preprocessing import preprocess_text_for_tts, chunk_text # Added chunk_text
    from .tts_engine import TTSEngine
    from .evaluation import AudioEvaluator
    from .voice_profiles import list_voice_profiles, get_voice_profile
    from .audio_utils import concatenate_audio_files, cleanup_files # Added audio utils
except ImportError as e:
    logger.critical(f"CRITICAL: Import error ({e}). Did you run 'just setup' or 'uv pip install -e .[dev]'?", exc_info=True) # Updated hint
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
@click.option('--voice-profile', type=click.Choice(list_voice_profiles()), help="Use a prebuilt voice profile (e.g., 'lula', 'trump'). Mutually exclusive with --speaker-wav.")
@click.option('--speaker-wav', '-s', type=click.Path(exists=True, file_okay=True, dir_okay=False, readable=True, path_type=Path), help="Path to a reference WAV file (10-30s). Mutually exclusive with --voice-profile.")
@click.option('--text', '-t', help="Text to synthesize directly. Mutually exclusive with --text-file.")
@click.option('--text-file', '-f', type=click.Path(exists=True, file_okay=True, dir_okay=False, readable=True, resolve_path=True, path_type=Path), help="Path to a text file containing the synthesis text. Mutually exclusive with --text.")
@click.option('--output-file', '-o', type=click.Path(writable=True, path_type=Path), required=True, help="Path to save the output WAV audio file.")
@click.option('--language', '-l', default="en", show_default=True, help="Language code for TTS.")
@click.option('--speed', type=float, default=1.0, show_default=True, help="Adjust playback speed.")
@click.option('--evaluate', '-e', is_flag=True, help="Evaluate audio quality using Whisper STT.")
@click.option('--cpu', is_flag=True, help="Force CPU for TTS and evaluation.")
def synthesize(
    voice_profile: str | None,
    speaker_wav: Path | None,
    text: str | None,
    text_file: Path | None, # Renamed from input_file
    output_file: Path,
    language: str,
    speed: float,
    evaluate: bool,
    cpu: bool
):
    """Synthesizes speech from text using a speaker reference (file or profile)."""
    # --- Validation ---
    if not (voice_profile or speaker_wav):
        raise click.UsageError("Either --voice-profile or --speaker-wav must be provided.")
    if voice_profile and speaker_wav:
        raise click.UsageError("--voice-profile and --speaker-wav are mutually exclusive.")
    if not (text or text_file): # Use text_file
        raise click.UsageError("Either --text or --text-file must be provided.")
    if text and text_file: # Use text_file
        raise click.UsageError("--text and --text-file are mutually exclusive.")

    # Determine the speaker WAV path
    actual_speaker_wav: Path
    if voice_profile:
        profile_path = get_voice_profile(voice_profile)
        if not profile_path:
            # get_voice_profile logs errors, just exit
            sys.exit(1)
        actual_speaker_wav = profile_path
        logger.info(f"Using voice profile '{voice_profile}' ({actual_speaker_wav.name})")
    else:
        # If speaker_wav was provided, click already validated its existence.
        actual_speaker_wav = speaker_wav
        logger.info(f"Using speaker WAV file: {actual_speaker_wav.name}")
    # --- Start Process ---
    start_total_time = time.time()
    use_cuda = not cpu
    logger.info(f"--- Synthesize Command Start ---") # Added marker
    logger.info(f"Starting Montaigne TTS process. CUDA enabled: {use_cuda}")

    # Determine input content
    input_content: str
    source_name: str
    if text_file: # Use text_file
        try:
            input_content = text_file.read_text('utf-8')
            source_name = text_file.name
            logger.info(f"Read {len(input_content)} chars from file: {source_name}")
        except Exception as e:
            click.echo(f"❌ Error reading text file '{text_file}': {e}", err=True) # Updated error message
            sys.exit(1)
    else: # text must be provided if text_file is None (validated above)
        input_content = text
        source_name = "CLI --text option"
        logger.info(f"Read {len(input_content)} chars from {source_name}.")

    if not input_content.strip():
        click.echo("❌ Error: Input text is empty.", err=True)
        sys.exit(1)

    # --- Text Chunking & Preprocessing ---
    # Chunk the raw input first
    text_chunks = chunk_text(input_content) # Using default paragraph strategy
    if not text_chunks:
        click.echo("❌ Error: Text content resulted in zero processable chunks.", err=True)
        sys.exit(1)

    processed_chunks = []
    for i, chunk in enumerate(text_chunks):
        print(f"📝 Preprocessing chunk {i+1}/{len(text_chunks)}...");
        processed = preprocess_text_for_tts(chunk)
        logger.debug(f"Chunk {i+1} after preprocessing: '{processed[:100]}...'")
        if processed.strip():
            processed_chunks.append(processed)
        else:
            logger.warning(f"Chunk {i+1} became empty after preprocessing, skipping.")

    if not processed_chunks:
        click.echo("❌ Error: All text chunks became empty after preprocessing.", err=True)
        sys.exit(1)

    # --- Synthesis Loop ---
    chunk_output_files: list[Path] = []
    synthesis_failed = False
    output_dir = output_file.parent
    output_base_name = output_file.stem
    output_suffix = output_file.suffix # Usually .wav

    click.echo(f"🎙️ Starting synthesis of {len(processed_chunks)} chunks (Lang: {language}, Speaker: {actual_speaker_wav.name})...")

    engine = get_tts_engine(use_cuda) # Initialize engine once

    for i, chunk_text_processed in enumerate(processed_chunks):
        chunk_output_path = output_dir / f"{output_base_name}_chunk_{i}{output_suffix}"
        chunk_output_files.append(chunk_output_path)
        click.echo(f"   Synthesizing chunk {i+1}/{len(processed_chunks)} -> {chunk_output_path.name}")

        try:
            success = engine.synthesize(
                text=chunk_text_processed,
                speaker_wav=str(actual_speaker_wav),
                language=language,
                output_path=chunk_output_path,
                speed=speed
            )
            if not success:
                synthesis_failed = True
                logger.error(f"Synthesis failed for chunk {i+1}. See previous logs.")
                # Decide whether to stop or continue? Continue for now.
        except Exception as e:
            # Catch errors during individual chunk synthesis
            synthesis_failed = True
            logger.exception(f"Error synthesizing chunk {i+1}")
            click.echo(f"❌ Error synthesizing chunk {i+1}: {e}", err=True)
            # Continue to next chunk? Or break? Continue for now.

    if not chunk_output_files or all(not f.exists() for f in chunk_output_files):
         click.echo("❌ Error: No audio chunks were successfully generated.", err=True)
         sys.exit(1)

    # --- Concatenation ---
    click.echo(f"\n🔗 Concatenating {len(chunk_output_files)} audio chunks into {output_file.name}...")
    concatenation_successful = concatenate_audio_files(chunk_output_files, output_file)

    # --- Cleanup ---
    if chunk_output_files:
        cleanup_files(chunk_output_files)

    if not concatenation_successful:
        click.echo("❌ Error: Failed to concatenate audio chunks.", err=True)
        sys.exit(1) # Exit if concatenation failed

    # Determine overall success based *only* on concatenation success for now
    # A more robust check might consider if *any* chunk failed synthesis
    synthesis_successful = concatenation_successful and not synthesis_failed
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

    # --- Evaluation (on the final concatenated file) ---
    if synthesis_successful and evaluate:
        click.echo("\n" + "📊 Starting audio evaluation (Whisper STT) on final output...")
        try:
            # We need the full *original* processed text for comparison
            full_processed_text = " ".join(processed_chunks) # Rejoin for evaluation target
            evaluator = get_evaluator(use_cuda)
            evaluation_result = evaluator.evaluate_audio(output_file, full_processed_text)
            if evaluation_result:
                score, transcript = evaluation_result
                click.echo(f"    Transcript Sample: '{transcript[:100].strip()}...'")
                click.echo(f"    🎯 Similarity Score (vs processed input): {score:.2f}%")
            else:
                 click.secho("    ⚠️ Evaluation incomplete (possible transcription error?).", fg='yellow')
        except RuntimeError as e:
            click.secho(f"❌ Evaluator Error: {e}", fg='red')
        except Exception as e:
            logger.exception("Unexpected evaluation error.")
            click.secho(f"❌ Unexpected evaluation error: {e}", fg='red')
    elif not synthesis_successful:
        click.secho("\n" + "⚠️ Skipping evaluation because synthesis or concatenation failed.", fg='yellow')

    total_duration = time.time() - start_total_time
    print(f"\n✨ Montaigne process finished in {total_duration:.2f} seconds.")
    if not synthesis_successful:
        sys.exit(1)

if __name__ == "__main__":
    cli()
