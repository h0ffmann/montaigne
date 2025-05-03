import logging  # Added missing import and moved to top
import sys
import time
import uuid  # For generating session IDs
from datetime import datetime
from enum import Enum
from pathlib import Path

import click

# Moved and organized imports from lower in the file and previous diffs
from .audio_metrics import calculate_audio_metrics, generate_metrics_report
from .audio_utils import (
    YTDLP_AVAILABLE,
    cleanup_files,
    concatenate_audio_files,
    download_audio_from_youtube,
)
from .metadata_manager import MetadataManager
from .preprocessing import chunk_text, preprocess_text_for_tts
from .streaming_tts import PiperStreamingTTS, run_interactive_prompt
from .tts_engine import (
    BARK_AVAILABLE,
    TTS_AVAILABLE,
    BarkEngine,
    BaseTTSEngine,
    XTTSv2Engine,
)
from .voice_profiles import get_voice_profile, list_voice_profiles


# Define available engines
class EngineChoice(Enum):
    XTTS = "xtts"
    BARK = "bark"

logger = logging.getLogger("montaigne.cli")

# Global instances are tricky with multiple engines; maybe lazy load in get function
# Batch Engine instances
engine_instances = {} # type: ignore

# Streaming Engine (PiperStreamingTTS) is instantiated directly in the 'live' command now
# No factory needed here. Checks PIPER_AVAILABLE and SOUNDDEVICE_AVAILABLE are imported above.


def get_tts_engine(engine_type: EngineChoice, use_cuda: bool):
    """Factory function to get or create a Batch TTS engine instance."""
    engine_key = (engine_type, use_cuda)

    if engine_key not in engine_instances:
        if engine_type == EngineChoice.XTTS:
            if not TTS_AVAILABLE:
                click.echo("❌ Error: XTTS engine requires TTS library. Not available.", err=True)
                sys.exit(1)
            engine_instances[engine_key] = XTTSv2Engine(use_cuda=use_cuda)
        elif engine_type == EngineChoice.BARK:
            if not BARK_AVAILABLE:
                click.echo("❌ Error: Bark engine requires bark library. Not available.", err=True)
                sys.exit(1)
            engine_instances[engine_key] = BarkEngine(use_cuda=use_cuda)
        else:
            # Should be caught by click validation, but belt-and-suspenders
            click.echo(f"❌ Error: Unknown TTS engine: {engine_type}", err=True)
            sys.exit(1)  # Exit if engine init fails

    return engine_instances[engine_key]


# No global streaming engine instance needed anymore.
# Evaluator instance can remain global or follow similar pattern if needed later
evaluator_instance = None


def get_evaluator():  # Removed unused use_cuda argument
    """Factory function for audio evaluator."""
    global evaluator_instance
    if evaluator_instance is None:
        # evaluator_instance = AudioEvaluator(use_cuda=use_cuda) # Commented out as import is commented
        pass
    return evaluator_instance
 
 
@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.option('--log-file', type=click.Path(), help='Path to log file')
@click.option('--log-level', type=click.Choice(['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']),
              default='INFO', help='Set logging level')
def cli(log_file: str | None, log_level: str):
    """🚀 Montaigne TTS: Synthesizes speech using XTTS v2 or Bark."""
    # Setup logging at startup
    setup_logging(
        log_file=Path(log_file) if log_file else None,
        level=getattr(logging, log_level.upper())
    )
    # The logger is now configured globally
    pass


@cli.command(name="synthesize")
@click.option("--engine", type=click.Choice(["xtts", "bark"]), default="xtts", help="TTS engine to use.")
@click.option("--text", help="Text to synthesize")
@click.option("--text-file", type=click.Path(exists=True), help="Text file to synthesize")
@click.option("--language", default="pt", help="Language code (en, pt, etc)")
@click.option("--voice-profile", help="Named voice profile to use", type=click.Choice(list_voice_profiles()))
@click.option("--speaker-wav", type=click.Path(exists=True), help="Path to speaker reference audio file (for XTTS)")
@click.option("--speaker-youtube-id", type=str, help="YouTube video ID for speaker voice")
@click.option("--speaker-prompt", help="Speaker prompt (for Bark)")
@click.option("--speed", type=float, default=1.0, help="Speech speed multiplier (XTTS only)")
@click.option("--cpu", is_flag=True, help="Use CPU instead of GPU")
@click.option("--output-file", type=click.Path(), help="Output audio file path")
@click.option("--output-format", type=click.Choice(["wav", "mp3"]), default="mp3", help="Output audio format")
@click.option("--skip-preprocessors", is_flag=True, help="Skip all preprocessing steps")
@click.option("--skip-voice-preprocessing", is_flag=True, help="Skip voice preprocessing for profile voices")
@click.option("--skip-voice-isolation", is_flag=True, help="Skip voice isolation for profile voices")
@click.option("--skip-audio-processing", is_flag=True, help="Skip ALL audio processing (both input and output)")
def synthesize(
    engine: str,
    text: str,
    text_file: click.Path | None,
    language: str,
    voice_profile: str | None,
    speaker_wav: click.Path | None,
    speaker_youtube_id: str | None,
    speaker_prompt: str | None,
    speed: float,
    cpu: bool,
    output_file: click.Path | None,
    output_format: str,
    skip_preprocessors: bool,
    skip_voice_preprocessing: bool,
    skip_voice_isolation: bool,
    skip_audio_processing: bool,
):
    """Synthesizes speech from text using a selected TTS engine."""
    selected_engine_type = EngineChoice(engine)

    # --- Validation ---
    # At least text or text-file required
    if not (text or text_file):
        click.echo("❌ Error: Either --text or --text-file must be provided.", err=True)
        sys.exit(1)

    # XTTS Speaker Input Validation
    speaker_inputs = sum(p is not None for p in [voice_profile, speaker_wav, speaker_youtube_id])
    if selected_engine_type == EngineChoice.XTTS and speaker_inputs != 1:
        click.echo("❌ Error: For XTTS, exactly one speaker input is required.", err=True)
        sys.exit(1)

    # Ensure speaker_prompt is not used with XTTS
    if selected_engine_type == EngineChoice.XTTS and speaker_prompt:
        click.echo("❌ Error: --speaker-prompt is only for Bark engine.", err=True)
        sys.exit(1)

    # Common validation
    languages = ["en", "es", "fr", "de", "it", "pt", "pl", "tr", "ru", "nl", "cs", "ar", "zh", "ja", "hu"]
    if language not in languages:
        click.echo(f"❌ Error: Unsupported language '{language}'.", err=True)
        sys.exit(1)

    # --- Engine-Specific Setup ---
    engine_params = {}  # Initialize empty dict for engine-specific runtime params
    engine_display_name = selected_engine_type.value.upper()
    speaker_display_name = "Default"

    # Determine the actual speaker WAV path based on provided mutually exclusive options
    actual_speaker_wav: Path | list[Path] | None = None

    if selected_engine_type == EngineChoice.XTTS:
        # Process XTTS speaker input
        if speaker_youtube_id:
            if not YTDLP_AVAILABLE:
                click.echo("❌ Error: YouTube download not available. Install yt-dlp.", err=True)
                sys.exit(1)
            # Call the download function from audio_utils
            downloaded_path = download_audio_from_youtube(speaker_youtube_id)
            if downloaded_path is None:
                click.echo(f"❌ Error: Failed to download from YouTube ID: {speaker_youtube_id}", err=True)
                sys.exit(1)
            actual_speaker_wav = downloaded_path
            speaker_display_name = f"YouTube: {speaker_youtube_id} ({actual_speaker_wav.name})"
            # Add the downloaded path to engine_params (as string)
            engine_params["speaker_wav"] = str(actual_speaker_wav)
 
        elif voice_profile:
            # Get paths for the voice profile (can return a list)
            profile_paths = get_voice_profile(
                voice_profile, skip_preprocessing=skip_voice_preprocessing, skip_isolation=skip_voice_isolation
            )
            if not profile_paths:
                click.echo(f"❌ Error: Failed to load voice profile '{voice_profile}'", err=True)
                sys.exit(1)
            # Use the list of paths
            actual_speaker_wavs = profile_paths
            speaker_display_name = f"Profile: {voice_profile} ({len(actual_speaker_wavs)} samples)"
            # Pass the list of paths (as strings) to engine_params
            engine_params["speaker_wav"] = [str(p) for p in actual_speaker_wavs]

        elif speaker_wav:
            # Single speaker_wav file provided
            # Convert the string path from Click into a Path object
            speaker_wav_path = Path(speaker_wav) # Convert string to Path
            if not speaker_wav_path.exists():
                 # Although Click checks exists=True, add a safeguard if needed
                 logger.error(f"Speaker WAV file provided via --speaker-wav does not exist: {speaker_wav}")
                 sys.exit(1)
            actual_speaker_wav = speaker_wav_path # Assign the Path object
            speaker_display_name = f"File: {actual_speaker_wav.name}" # Now .name works
            # Pass the string representation to the engine parameters
            engine_params["speaker_wav"] = str(actual_speaker_wav)

        # Common setup for XTTS speed parameter
        engine_params["speed"] = speed

    elif selected_engine_type == EngineChoice.BARK:
        # Bark specific setup
        engine_params["speaker_prompt"] = speaker_prompt
        speaker_display_name = f"Prompt: {speaker_prompt}" if speaker_prompt else "Generic/Default"
    # otherwise language is already set for both engines in synthesize

    # --- Start Process ---
    start_total_time = time.time()
    use_cuda = not cpu

    # Determine input content (same as before)
    input_content: str
    source_name: str
    if text_file:  # Use text_file
        try:
            input_content = text_file.read_text("utf-8")
            source_name = text_file.name
        except OSError as e:
            click.echo(f"❌ Error reading text file '{text_file}': {e}", err=True)
            sys.exit(1)
    else:  # text must be provided if text_file is None (validated above)
        input_content = text
        source_name = "CLI --text option"

    click.echo(f"🔤 Input: {source_name}")

    # --- Text Chunking & Preprocessing (Applied to both engines for now) ---
    text_chunks = chunk_text(input_content)

    # Apply preprocessing if not skipped
    processed_chunks = []
    if skip_preprocessors:
        click.echo("⏭️ Skipping text preprocessing as requested")
        processed_chunks = text_chunks
    else:
        click.echo("📝 Preprocessing text...")
        for chunk in text_chunks:
            processed = preprocess_text_for_tts(chunk)
            processed_chunks.append(processed)

    # --- Synthesis Loop ---
    chunk_output_files: list[Path] = []
    synthesis_failed = False
    # Ensure output_file is a Path object before accessing attributes
    # Explicitly decode if it's bytes, then convert to Path
    if output_file is None:
        # Generate default output file name
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        language_part = language
        profile_part = voice_profile or "default"
        engine_part = engine_display_name.lower()
        model_part = "xtts_v2" if engine == "xtts" else "bark"
        default_name = f"{language_part}-{profile_part}-{engine_part}-{model_part}-{timestamp}.{output_format}"
        output_file = Path(default_name)
    elif isinstance(output_file, bytes):
        output_file = output_file.decode("utf-8")
        output_file = Path(output_file)

    output_file = Path(output_file)

    # Ensure output format is respected
    if output_file.suffix != f".{output_format}":
        output_file = output_file.with_suffix(f".{output_format}")

    output_dir = output_file.parent
    output_base_name = output_file.stem

    # Get the engine instance (lazy loaded)
    try:
        engine_instance: BaseTTSEngine = get_tts_engine(selected_engine_type, use_cuda)
    except Exception as e:
        # Error logged in get_tts_engine, just exit cleanly
        click.echo(f"❌ Engine initialization failed: {e}", err=True)
        sys.exit(1)

    click.echo(f"🎤 Generating speech with {engine_display_name} ({speaker_display_name})...")

    for i, chunk in enumerate(processed_chunks):
        if chunk.strip():  # Skip empty chunks
            chunk_output_path = output_dir / f"{output_base_name}_chunk_{i}.wav"

            # Pass only relevant parameters for the selected engine
            success = engine_instance.synthesize(
                text=chunk,
                language=language,
                output_path=chunk_output_path,
                **engine_params,  # Pass specific params like speaker_wav or speaker_prompt
            )

            if success:
                chunk_output_files.append(chunk_output_path)
            else:
                # Error already logged by the engine
                synthesis_failed = True
                break  # Don't continue if a chunk fails

    if not chunk_output_files:
        click.echo("❌ No audio chunks were successfully generated.", err=True)
        sys.exit(1)

    # --- Concatenation, Cleanup, Evaluation (mostly unchanged) ---
    click.echo(f"🔗 Combining {len(chunk_output_files)} chunks...")

    # Ensure concatenation inputs actually exist before proceeding
    valid_chunk_files = [f for f in chunk_output_files if f.exists() and f.stat().st_size > 0]

    if not valid_chunk_files:
        click.echo("❌ No valid audio chunks to concatenate.", err=True)
        cleanup_files(chunk_output_files)
        sys.exit(1)

    # Concatenate to temporary WAV file first
    temp_wav_path = output_file.with_suffix(".temp.wav")
    concatenation_successful = concatenate_audio_files(valid_chunk_files, temp_wav_path)

    if concatenation_successful:
        # If MP3 output is requested, convert WAV to MP3
        if output_format == "mp3":
            from pydub import AudioSegment

            try:
                audio = AudioSegment.from_wav(str(temp_wav_path))
                audio.export(str(output_file), format="mp3", bitrate="192k")
                # Remove temporary WAV file
                temp_wav_path.unlink()
                final_output_path = output_file
            except Exception as e:
                click.echo(f"❌ MP3 conversion failed: {e}", err=True)
                # Fall back to WAV
                temp_wav_path.rename(output_file.with_suffix(".wav"))
                final_output_path = output_file.with_suffix(".wav")
        else:
            # Use WAV directly
            temp_wav_path.rename(output_file)
            final_output_path = output_file
    else:
        cleanup_files(chunk_output_files)  # Clean up chunk files
        sys.exit(1)

    # Clean up chunk files
    cleanup_files(chunk_output_files)

    synthesis_successful = concatenation_successful and not synthesis_failed

    # Calculate audio metrics for output
    output_metrics = {}
    try:
        output_metrics = calculate_audio_metrics(final_output_path)
        # Clean potential inf/NaN values from output metrics before saving
        output_metrics = MetadataManager._clean_metadata_for_toml(output_metrics) # Use the cleaning function
    except Exception as e:
        logger.warning(f"Failed to calculate output metrics for {final_output_path.name}: {e}")
 
    # Calculate metrics for input files if applicable, with error handling
    input_metrics: dict | list = {} # Define type hint
    if actual_speaker_wav and not skip_audio_processing:
        if isinstance(actual_speaker_wav, list):
            input_metrics = []
            # Ensure we iterate over the correct variable (actual_speaker_wavs was used before, but actual_speaker_wav holds the list now)
            for path in actual_speaker_wav:
                try:
                    metrics = calculate_audio_metrics(path)
                    # Clean potential inf/NaN values from input metrics
                    cleaned_metrics = MetadataManager._clean_metadata_for_toml(metrics)
                    if cleaned_metrics:
                        input_metrics.append({"file": str(path), "metrics": cleaned_metrics})
                except Exception as e:
                    logger.warning(f"Failed to calculate input metrics for {path.name}: {e}")
        elif isinstance(actual_speaker_wav, Path):
            try:
                input_metrics = calculate_audio_metrics(actual_speaker_wav)
                # Clean potential inf/NaN values from input metrics
                input_metrics = MetadataManager._clean_metadata_for_toml(input_metrics)
            except Exception as e:
                logger.warning(f"Failed to calculate input metrics for {actual_speaker_wav.name}: {e}")
                input_metrics = {} # Reset to empty dict on failure
 
    # Evaluation (kept for compatibility)

    # Calculation time stats
    total_duration = time.time() - start_total_time

    # Create and save metadata using MetadataManager
    metadata = MetadataManager.create_metadata(
        engine=engine,
        language=language,
        output_format=output_format,
        source_name=source_name,
        input_content=input_content,
        processed_chunks=len(processed_chunks),
        voice_profile=voice_profile,
        actual_speaker_wav=actual_speaker_wav,
        speaker_youtube_id=speaker_youtube_id,
        speaker_prompt=speaker_prompt,
        input_metrics=input_metrics,
        engine_params=engine_params,
        cpu=cpu,
        skip_preprocessors=skip_preprocessors,
        skip_voice_preprocessing=skip_voice_preprocessing, # Pass flag
        skip_voice_isolation=skip_voice_isolation, # Pass flag
        skip_audio_processing=skip_audio_processing, # Pass flag
        final_output_path=final_output_path, # Pass Path object
        synthesis_successful=synthesis_successful, # Pass bool
        output_metrics=output_metrics, # Pass cleaned metrics dict
        processing_time=total_duration, # Pass float
    )

    # Save metadata to TOML file
    metadata_saved = MetadataManager.save_metadata(metadata, final_output_path)
    if metadata_saved:
        click.echo(f"💾 Metadata saved to: {MetadataManager.get_metadata_path(final_output_path)}")
    else:
        click.echo("⚠️ Warning: Failed to save metadata to TOML", err=True)

    # --- Display Results ---
    if synthesis_successful:
        click.echo(f"✅ Synthesis complete: {final_output_path}")

        # Generate and display metrics report
        metrics_report = generate_metrics_report(input_metrics, output_metrics)
        click.echo(metrics_report)

        click.echo(f"⏱️ Time taken: {total_duration:.1f}s")

        # Display metadata summary if available
        if metadata:
            click.echo("\n📋 Synthesis Summary:")
            click.echo(MetadataManager.generate_summary(metadata))
    else:
        click.echo("❌ Synthesis completed with errors.", err=True)


# --- Live TTS Command (Using PiperStreamingTTS with HF Download) ---
@cli.command(name="live")
@click.option("--piper-voice", type=str, default="en_US-amy-low", help="Piper voice model to use")
@click.option("--file", type=click.File("r"), help="Text file to process (default: interactive prompt)")
@click.option("--output-dir", type=click.Path(), default="output", help="Directory to save audio output")
@click.option("--cpu", is_flag=True, help="Use CPU instead of GPU")
def live(piper_voice: str, file: click.File | None, output_dir: click.Path, cpu: bool):
    """Starts a live TTS session using Piper, downloading the specified voice."""

    # Checks for library availability are done inside PiperStreamingTTS constructor now

    session_id = uuid.uuid4()  # Generate a random UUID (uuid7 not available in Python < 3.13)
    output_dir = Path(output_dir)
    use_cuda = not cpu

    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)
    click.echo(f"🔊 Live TTS session using voice: {piper_voice} (Session ID: {session_id})")

    engine: PiperStreamingTTS | None = None  # Define engine variable before try block
    try:
        # Initialize the Piper engine instance
        click.echo("🚀 Initializing Piper engine...")
        engine = PiperStreamingTTS(use_cuda=use_cuda)

        # Load the specified model
        if not engine.load_model(piper_voice):
            click.echo("❌ Failed to load Piper model. Exiting.", err=True)
            sys.exit(1)

        click.echo("✅ Piper engine ready!")

        # --- Input Loop (File or REPL) ---
        if file:
            # File mode: Read line by line and stream speak
            click.echo("📄 Processing text file...")
            for line_num, line in enumerate(file, 1):
                line = line.strip()
                if line:  # Skip empty lines
                    click.echo(f"\n🔊 Line {line_num}: {line[:50]}{'...' if len(line) > 50 else ''}")
                    processed_text = line.strip()
                    # speak() method now blocks until playback is finished
                    success = engine.stream_speak(processed_text, session_id, output_dir, line_num)
                    if not success:
                        click.echo(f"⚠️ Warning: Failed to synthesize line {line_num}", err=True)
            click.echo("\n✅ File processing complete!")
        else:
            # Interactive REPL - use the dedicated function from streaming_tts
            # Pass session_id and output_dir
            run_interactive_prompt(engine, session_id, output_dir)

    except Exception as e:
        click.echo(f"❌ Error: {e}", err=True)
        # Stop is handled by run_interactive_prompt or implicitly at end of file processing
    finally:
        if engine:
            engine.stop()  # Attempt cleanup if engine was initialized
        click.echo("\n👋 Goodbye!")


if __name__ == "__main__":
    cli()
