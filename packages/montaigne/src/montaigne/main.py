import logging
import sys
import time
import uuid  # For generating session IDs
from enum import Enum
from pathlib import Path
from typing import Optional # Add this import

import click


# Define available engines
class EngineChoice(Enum):
    XTTS = "xtts"
    BARK = "bark"


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)-7s] [%(name)-20s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("montaigne.cli")


try:
    from .audio_utils import cleanup_files, concatenate_audio_files
    from .preprocessing import chunk_text, preprocess_text_for_tts

    # Import the new Piper-based streaming engine (now PiperStreamingTTS)
    from .streaming_tts import (  # Import new class and checks
        PiperStreamingTTS,
        run_interactive_prompt,
    )

    # Import engine classes with checks
    from .tts_engine import BarkEngine, BaseTTSEngine, XTTSv2Engine

    # from .evaluation import AudioEvaluator # Keep evaluation for batch mode TODO
    from .voice_profiles import (  # Keep profile import
        get_engine_params as get_profile_engine_params, # Renamed import
        get_voice_profile,
        get_voice_profile_config, # Import config getter
        list_voice_profiles,
    )
except ImportError as e:
    logger.critical(
        f"CRITICAL: Import error ({e}). Environment setup incomplete? (Run 'just nix' or check installations).",
        exc_info=True,
    )
    sys.exit(1)

# Global instances are tricky with multiple engines; maybe lazy load in get function
# Batch Engine instances
engine_instances = {}

# Streaming Engine (PiperStreamingTTS) is instantiated directly in the 'live' command now
# No factory needed here. Checks PIPER_AVAILABLE and SOUNDDEVICE_AVAILABLE are imported above.


def get_tts_engine(engine_type: EngineChoice, use_cuda: bool):
    """Factory function to get or create a Batch TTS engine instance."""
    engine_key = (engine_type, use_cuda)
    if engine_key not in engine_instances:
        logger.info(f"Initializing TTS Engine ({engine_type.value})...")
        try:
            if engine_type == EngineChoice.XTTS:
                if XTTSv2Engine is None:
                    raise ImportError("XTTSv2Engine not available.")
                engine_instances[engine_key] = XTTSv2Engine(use_cuda=use_cuda)
            elif engine_type == EngineChoice.BARK:
                if BarkEngine is None:
                    raise ImportError("BarkEngine not available.")
                engine_instances[engine_key] = BarkEngine(use_cuda=use_cuda)
            else:
                # Should be caught by click validation, but belt-and-suspenders
                raise ValueError(f"Unsupported engine type: {engine_type}")
        except (ImportError, RuntimeError) as e:
            logger.critical(f"Failed to initialize engine '{engine_type.value}': {e}")
            sys.exit(1)  # Exit if engine init fails
    return engine_instances[engine_key]


# No global streaming engine instance needed anymore.
# Evaluator instance can remain global or follow similar pattern if needed later
evaluator_instance = None


def get_evaluator():  # Removed unused use_cuda argument
    global evaluator_instance  # Keep evaluator logic for batch synthesize command
    if evaluator_instance is None:
        logger.info("Initializing Audio Evaluator (Whisper)...")
        # evaluator_instance = AudioEvaluator(use_cuda=use_cuda) # Commented out as import is commented
    return evaluator_instance


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
def cli():
    """🚀 Montaigne TTS: Synthesizes speech using XTTS v2 or Bark."""
    pass


@cli.command()
@click.option(
    "--engine",
    type=click.Choice([e.value for e in EngineChoice]),
    default=EngineChoice.XTTS.value,
    show_default=True,
    help="Select the TTS engine.",
)
@click.option(
    "--voice-profile",
    type=click.Choice(list_voice_profiles()),
    help="Use a predefined voice profile (XTTS only).",
)
@click.option(
    "--mode",
    type=click.Choice(["simple", "deep"]),
    default=None, # Default is handled by voice_profile_manager
    help="Voice synthesis quality mode (simple=faster, deep=better quality). Overrides profiles.toml default.",
)
@click.option(
    "--mode",
    type=click.Choice(["simple", "deep"]),
    default=None, # Default is handled by voice_profile_manager
    help="Voice synthesis quality mode (simple=faster, deep=better quality). Overrides profiles.toml default.",
)
@click.option(
    "--speaker-wav",
    "-s",
    type=click.Path(exists=True, file_okay=True, dir_okay=False, readable=True, path_type=Path),
    help="Path to a reference WAV file for voice cloning (XTTS only).",
)
# Update help text to clarify youtube ID requires internet
@click.option(
    "--speaker-youtube-id",
    help=(
        "YouTube Video ID for voice cloning (XTTS only, downloads audio). "
        "Mutually exclusive with --speaker-wav and --voice-profile."
    ),
)
@click.option("--speaker-prompt", help="Voice prompt for Bark engine (e.g., 'en_speaker_6').")
@click.option(
    "--text",
    "-t",
    help="Text to synthesize directly. Mutually exclusive with --text-file.",
)
@click.option(
    "--text-file",
    "-f",
    type=click.Path(
        exists=True,
        file_okay=True,
        dir_okay=False,
        readable=True,
        resolve_path=True,
        path_type=Path,
    ),
    help="Path to a text file containing the synthesis text.",
)
# Update help text to indicate this is for batch mode
@click.option(
    "--output-file",
    "-o",
    type=click.Path(writable=True, path_type=Path),
    required=True,
    help="Path to save the output WAV audio file.",
)
@click.option(
    "--language",
    "-l",
    default="en",
    show_default=True,
    help="Language code (e.g., en, pt). Bark uses this for generic voice selection if --speaker-prompt is not given.",
)
@click.option(
    "--speed",
    type=float,
    default=1.0,
    show_default=True,
    help="Adjust playback speed (XTTS only).",
)
@click.option("--evaluate", "-e", is_flag=True, help="Evaluate audio quality using Whisper STT.")
@click.option("--cpu", is_flag=True, help="Force CPU for TTS and evaluation.")
def synthesize(
    engine: str,
    voice_profile: str | None,
    speaker_wav: Path | None,
    speaker_youtube_id: str | None,
    speaker_prompt: str | None,
    text: str | None,
    text_file: Path | None,
    output_file: Path,
    language: str,
    speed: float,
    evaluate: bool,
    cpu: bool,
    mode: Optional[str], # Add mode parameter
):
    """Synthesizes speech from text using a selected TTS engine."""
    selected_engine_type = EngineChoice(engine)

    # --- Validation ---
    if selected_engine_type == EngineChoice.XTTS:
        # XTTS Speaker Input Validation
        speaker_inputs = sum(p is not None for p in [voice_profile, speaker_wav, speaker_youtube_id])
        if speaker_inputs == 0:
            raise click.UsageError(
                "XTTS engine requires one of: --voice-profile, --speaker-wav, or --speaker-youtube-id."
            )
        if speaker_inputs > 1:
            raise click.UsageError(
                "Options --voice-profile, --speaker-wav, and --speaker-youtube-id are mutually exclusive."
            )
        # Ensure speaker_prompt is not used with XTTS
        if speaker_prompt:
            logger.warning("--speaker-prompt is ignored when using the XTTS engine.")

    elif selected_engine_type == EngineChoice.BARK:
        if voice_profile:
            raise click.UsageError(
                "--voice-profile is not compatible with the Bark engine. Use --speaker-prompt instead."
            )
        if speaker_wav:
            raise click.UsageError(
                "--speaker-wav is not compatible with the Bark engine. Use --speaker-prompt instead."
            )
        if speed != 1.0:
            logger.warning("--speed parameter is ignored when using the Bark engine.")
        if speaker_youtube_id:
            raise click.UsageError(
                "--speaker-youtube-id is not compatible with the Bark engine. Use --speaker-prompt instead."
            )
    # Common validation
    if not (text or text_file):
        raise click.UsageError("Either --text or --text-file must be provided.")
    if text and text_file:
        raise click.UsageError("--text and --text-file are mutually exclusive.")

    # --- Engine-Specific Setup ---
    engine_params = {} # Initialize empty dict for engine-specific runtime params
    engine_display_name = selected_engine_type.value.upper()
    speaker_display_name = "Default"

    # Get engine parameters based on mode for XTTS
    if selected_engine_type == EngineChoice.XTTS:
        # Use the renamed import get_profile_engine_params
        # Fetch parameters based on the selected mode (or default from config)
        xtts_mode_params = get_profile_engine_params("xtts", mode)
        logger.info(f"Using XTTS mode '{mode or 'default'}'. Parameters: {xtts_mode_params}")
        # Add these fetched parameters to the engine_params dict that will be passed to synthesize
        engine_params.update(xtts_mode_params)
        # Note: These params (num_gpt_outputs etc.) are currently NOT used by the XTTSv2Engine.synthesize method.
        # The TTS library itself might use them internally if configured differently, or this is for future use.
        # For now, they are fetched but not directly passed in a way that affects the current synthesize call signature.

    # Moved this import here as it's now needed for the youtube download function call
    from .audio_utils import download_audio_from_youtube

    if selected_engine_type == EngineChoice.XTTS:
        # Determine the actual speaker WAV path based on provided mutually exclusive options
        actual_speaker_wav: Path

        if speaker_youtube_id:
            logger.info(f"YouTube ID provided: {speaker_youtube_id}. Attempting to download/cache audio...")
            # Call the download function from audio_utils
            downloaded_path = download_audio_from_youtube(speaker_youtube_id)
            if downloaded_path and downloaded_path.exists():
                actual_speaker_wav = downloaded_path
                speaker_display_name = f"YouTube: {speaker_youtube_id} ({actual_speaker_wav.name})"
                logger.info(f"Using speaker audio from YouTube ID '{speaker_youtube_id}' -> {actual_speaker_wav.name}")
            else:
                # Error message already logged by download_audio_from_youtube
                click.echo(
                    f"❌ Failed to get speaker audio for YouTube ID: {speaker_youtube_id}",
                    err=True,
                )
                sys.exit(1)
        elif voice_profile:
            profile_path = get_voice_profile(voice_profile)
            if not profile_path:
                sys.exit(1)  # get_voice_profile logs errors
            actual_speaker_wav = profile_path
            speaker_display_name = f"Profile: {voice_profile}"
            # Log details about the profile samples
            profile_config = get_voice_profile_config(voice_profile)
            if profile_config and profile_config.get("youtube_ids"):
                num_samples = len(profile_config["youtube_ids"])
                logger.info(
                    f"Using voice profile '{voice_profile}' ({actual_speaker_wav.name}). "
                    f"Profile defines {num_samples} sample(s). Using the first sample: "
                    f"YouTube ID '{profile_config['youtube_ids'][0]}'."
                )
            else:
                 # Fallback log if config details aren't available for some reason
                 logger.info(f"Using voice profile '{voice_profile}' ({actual_speaker_wav.name})")
        else:
            # speaker_wav must be set if voice_profile is not (validated above)
            actual_speaker_wav = speaker_wav  # type: ignore [assignment] - Click ensures it exists
            speaker_display_name = (
                f"File: {actual_speaker_wav.name if actual_speaker_wav else 'N/A'}"  # Check added for type safety
            )
            logger.info(f"Using speaker WAV file: {actual_speaker_wav.name}")

        # Common setup for XTTS once actual_speaker_wav is determined
        engine_params["speaker_wav"] = str(actual_speaker_wav)
        engine_params["speed"] = speed
    elif selected_engine_type == EngineChoice.BARK:
        engine_params["speaker_prompt"] = speaker_prompt
        speaker_display_name = f"Prompt: {speaker_prompt}" if speaker_prompt else "Generic/Default"
        logger.info(f"Using Bark engine. Speaker selection: {speaker_display_name}")

    # --- Start Process ---
    start_total_time = time.time()
    use_cuda = not cpu
    logger.info(f"--- Synthesize Command Start ({engine_display_name}) ---")
    logger.info(f"Starting Montaigne TTS process. CUDA enabled: {use_cuda}")

    # Determine input content (same as before)
    input_content: str
    source_name: str
    if text_file:  # Use text_file
        try:
            input_content = text_file.read_text("utf-8")
            source_name = text_file.name
            logger.info(f"Read {len(input_content)} chars from file: {source_name}")
        except Exception as e:
            click.echo(f"❌ Error reading text file '{text_file}': {e}", err=True)  # Updated error message
            sys.exit(1)
    else:  # text must be provided if text_file is None (validated above)
        input_content = text
        source_name = "CLI --text option"
        logger.info(f"Read {len(input_content)} chars from {source_name}.")

    if not input_content.strip():
        click.echo("❌ Error: Input text is empty.", err=True)
        sys.exit(1)

    # --- Text Chunking & Preprocessing (Applied to both engines for now) ---
    text_chunks = chunk_text(input_content)
    if not text_chunks:
        click.echo("❌ Error: Text content resulted in zero processable chunks.", err=True)
        sys.exit(1)

    processed_chunks = []
    for i, chunk in enumerate(text_chunks):
        print(f"📝 Preprocessing chunk {i + 1}/{len(text_chunks)}...")
        processed = preprocess_text_for_tts(chunk)
        logger.debug(f"Chunk {i + 1} after preprocessing: '{processed[:100]}...'")
        if processed.strip():
            processed_chunks.append(processed)
        else:
            logger.warning(f"Chunk {i + 1} became empty after preprocessing, skipping.")

    if not processed_chunks:
        click.echo("❌ Error: All text chunks became empty after preprocessing.", err=True)
        sys.exit(1)

    # --- Synthesis Loop ---
    chunk_output_files: list[Path] = []
    synthesis_failed = False
    output_dir = output_file.parent
    output_base_name = output_file.stem
    output_suffix = output_file.suffix if output_file.suffix else ".wav"  # Ensure suffix

    # Get the engine instance (lazy loaded)
    try:
        engine_instance: BaseTTSEngine = get_tts_engine(selected_engine_type, use_cuda)
    except (RuntimeError, ImportError):
        # Error logged in get_tts_engine, just exit cleanly
        sys.exit(1)

    click.echo(
        f"🎙️ Starting synthesis with {engine_display_name} for {len(processed_chunks)} chunks "
        f"(Lang: {language}, Speaker: {speaker_display_name})..."
    )

    for i, chunk_text_processed in enumerate(processed_chunks):
        chunk_output_path = output_dir / f"{output_base_name}_chunk_{i}{output_suffix}"
        chunk_output_files.append(chunk_output_path)
        click.echo(f"   Synthesizing chunk {i + 1}/{len(processed_chunks)} -> {chunk_output_path.name}")

        try:
            # Pass only relevant parameters for the selected engine
            success = engine_instance.synthesize(
                text=chunk_text_processed,
                language=language,
                output_path=chunk_output_path,
                **engine_params,  # Pass specific params like speaker_wav or speaker_prompt
            )
            if not success:
                synthesis_failed = True
                logger.error(f"Synthesis failed for chunk {i + 1}. See previous logs.")
        except Exception as e:
            synthesis_failed = True
            logger.exception(f"Error synthesizing chunk {i + 1} with {engine_display_name}")
            click.echo(f"❌ Error synthesizing chunk {i + 1}: {e}", err=True)

    # --- Concatenation, Cleanup, Evaluation (mostly unchanged) ---
    if not chunk_output_files or all(not f.exists() for f in chunk_output_files):
        click.echo("❌ Error: No audio chunks were successfully generated.", err=True)
        sys.exit(1)

    click.echo(f"\n🔗 Concatenating {len(chunk_output_files)} audio chunks into {output_file.name}...")
    # Ensure concatenation inputs actually exist before proceeding
    valid_chunk_files = [f for f in chunk_output_files if f.exists() and f.stat().st_size > 0]
    if not valid_chunk_files:
        click.echo("❌ Error: No valid audio chunks found to concatenate.", err=True)
        if chunk_output_files:
            cleanup_files(chunk_output_files)
        sys.exit(1)
    elif len(valid_chunk_files) < len(chunk_output_files):
        click.secho(
            f"⚠️ Warning: Only {len(valid_chunk_files)} out of {len(chunk_output_files)} chunks "
            "were valid for concatenation.",
            fg="yellow",
        )

    concatenation_successful = concatenate_audio_files(valid_chunk_files, output_file)

    if chunk_output_files:
        cleanup_files(chunk_output_files)

    if not concatenation_successful:
        click.echo("❌ Error: Failed to concatenate audio chunks.", err=True)
        sys.exit(1)

    synthesis_successful = concatenation_successful and not synthesis_failed

    # Evaluation
    if synthesis_successful and evaluate:
        click.echo("\n" + "📊 Starting audio evaluation (Whisper STT) on final output...")
        try:
            # Rejoin processed chunks for evaluation target
            full_processed_text = " ".join(processed_chunks)
            evaluator = get_evaluator(use_cuda)  # Reuse evaluator instance
            evaluation_result = evaluator.evaluate_audio(output_file, full_processed_text)
            if evaluation_result:
                score, transcript = evaluation_result
                click.echo(f"    Transcript Sample: '{transcript[:100].strip()}...'")
                click.echo(f"    🎯 Similarity Score (vs processed input): {score:.2f}%")
            else:
                click.secho(
                    "    ⚠️ Evaluation incomplete (possible transcription error?).",
                    fg="yellow",
                )
        except RuntimeError as e:
            click.secho(f"❌ Evaluator Error: {e}", fg="red")
        except Exception as e:
            logger.exception("Unexpected evaluation error.")
            click.secho(f"❌ Unexpected evaluation error: {e}", fg="red")
    elif not synthesis_successful:
        click.secho(
            "\n" + "⚠️ Skipping evaluation because synthesis or concatenation failed.",
            fg="yellow",
        )

    total_duration = time.time() - start_total_time
    print(f"\n✨ Montaigne ({engine_display_name}) process finished in {total_duration:.2f} seconds.")
    if not synthesis_successful:
        sys.exit(1)


# --- Live TTS Command (Using PiperStreamingTTS with HF Download) ---
@cli.command()
@click.option(
    "--piper-voice",
    "-v",
    default="en_US-amy-low",
    show_default=True,
    help="Piper voice model name from Hugging Face (e.g., 'en_US-amy-low', 'pt_BR-faber-medium').",
)
@click.option(
    "--file",
    "-f",
    type=click.File("r"),
    default=None,
    help="Read text line-by-line from FILE instead of interactive input. Use '-' for stdin.",
)
@click.option(
    "--output-dir",
    "-o",
    type=click.Path(file_okay=False, dir_okay=True, writable=True, path_type=Path),
    default="output",
    show_default=True,
    help="Directory to save generated audio files (named live_<session_id>_<prompt_count>.wav).",
)
@click.option(
    "--cpu",
    is_flag=True,
    help="Prefer CPU for Piper TTS (onnxruntime might still choose GPU).",
)
def live(piper_voice: str, file: click.File | None, output_dir: Path, cpu: bool):
    """Starts a live TTS session using Piper, downloading the specified voice."""

    # Checks for library availability are done inside PiperStreamingTTS constructor now
    use_cuda = not cpu
    session_id = uuid.uuid4()  # Generate a random UUID (uuid7 not available in Python < 3.13)
    click.echo(f"🎙️ Starting Montaigne Live TTS Session (Piper Engine - HF, CUDA Pref: {use_cuda})")
    click.echo(f"   Session ID: {session_id}")

    # Ensure output directory exists
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
        click.echo(f"💾 Saving audio prompts to: {output_dir.resolve()}")
    except OSError as e:
        click.echo(f"❌ Error creating output directory '{output_dir}': {e}", err=True)
        sys.exit(1)

    if file:
        click.echo(f"Reading input from: {'stdin' if file.name == '-' else file.name}")

    engine: PiperStreamingTTS | None = None  # Define engine variable before try block
    try:
        # Initialize the Piper engine instance
        logger.info("Initializing Piper Streaming TTS Engine...")
        engine = PiperStreamingTTS(use_cuda=use_cuda)

        # Load the specified model
        click.echo(f"Loading Piper voice model: {piper_voice}...")
        if not engine.load_model(voice_name=piper_voice):
            click.echo(
                f"❌ Failed to load Piper voice model '{piper_voice}'. Check logs.",
                err=True,
            )
            sys.exit(1)

        # --- Input Loop (File or REPL) ---
        if file:
            click.echo("\nProcessing file line by line...")
            for line in file:
                processed_text = line.strip()
                if not processed_text:
                    continue
                click.echo(f"Synthesizing: '{processed_text[:80]}...'")
                if not engine.speak(processed_text):
                    click.echo(
                        f"⚠️ Warning: Failed to synthesize/play line: '{processed_text[:80]}...'",
                        err=True,
                    )
                # speak() method now blocks until playback is finished
            click.echo("\nFile processing finished.")
        else:
            # Interactive REPL - use the dedicated function from streaming_tts
            # Pass session_id and output_dir
            run_interactive_prompt(engine, session_id, output_dir)

        # Stop is handled by run_interactive_prompt or implicitly at end of file processing

    except RuntimeError as e:
        # Catch specific RuntimeErrors from constructor (missing libs)
        click.echo(f"❌ Initialization Error: {e}", err=True)
        sys.exit(1)
    except Exception as e:
        logger.exception("Critical error during live TTS session initialization or runtime.")
        click.echo(f"❌ An unexpected error occurred: {e}", err=True)
        if engine:
            engine.stop()  # Attempt cleanup if engine was initialized
        sys.exit(1)


if __name__ == "__main__":
    cli()
