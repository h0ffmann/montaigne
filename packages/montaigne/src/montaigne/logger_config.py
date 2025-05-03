import logging
import sys
from pathlib import Path
from typing import Any

class ColoredFormatter(logging.Formatter):
    """Custom formatter with colors and emojis for better readability."""

    COLORS = {
        'DEBUG': '\x1b[36m',      # Cyan
        'INFO': '\x1b[32m',       # Green
        'WARNING': '\x1b[33m',    # Yellow
        'ERROR': '\x1b[31m',      # Red
        'CRITICAL': '\x1b[31;1m', # Bold Red
    }
    RESET = '\x1b[0m'

    EMOJIS = {
        'DEBUG': '🔍',
        'INFO': 'ℹ️ ',
        'WARNING': '⚠️ ',
        'ERROR': '❌',
        'CRITICAL': '💥',
    }

    def format(self, record: logging.LogRecord) -> str:
        # Get color for level
        color = self.COLORS.get(record.levelname, '')
        reset = self.RESET
        emoji = self.EMOJIS.get(record.levelname, '')

        # Format timestamp
        timestamp = self.formatTime(record, datefmt='%Y-%m-%d %H:%M:%S')

        # Format the message with color and emoji
        # Ensure record.name is included for context
        formatted = f"{color}{emoji} [{timestamp}] {record.levelname:<8} [{record.name}]{reset} {record.getMessage()}"

        # Add exception info if present
        if record.exc_info:
            formatted += '\n' + self.formatException(record.exc_info)

        return formatted

def setup_logging(log_file: Path | None = None, level: int = logging.INFO) -> None:
    """Configure logging for the application."""

    # Create formatter
    formatter = ColoredFormatter()

    # Create console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)

    # Create file handler if log file is specified
    handlers = [console_handler]
    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        # Use standard Formatter for file to avoid color codes
        file_formatter = logging.Formatter(
            fmt='[%(asctime)s] %(levelname)-8s [%(name)s] %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(file_formatter)
        handlers.append(file_handler)

    # Configure root logger - Set level here, handlers manage output
    logging.basicConfig(
        level=level,
        handlers=handlers,
        force=True # Override any existing basicConfig
    )

    # Set level for specific loggers if needed (optional, root level usually sufficient)
    # loggers = [
    #     'montaigne', 'montaigne.cli', 'montaigne.tts_engine', # ... etc
    # ]
    # for logger_name in loggers:
    #     logger = logging.getLogger(logger_name)
    #     logger.setLevel(level) # Ensure they respect the main level

    # Silence overly verbose loggers if necessary
    logging.getLogger("matplotlib").setLevel(logging.WARNING)
    logging.getLogger("PIL").setLevel(logging.WARNING)
    logging.getLogger("pydub").setLevel(logging.WARNING)
    logging.getLogger("yt_dlp").setLevel(logging.WARNING) # Make yt-dlp less noisy by default

    logging.info(f"Logging configured. Level: {logging.getLevelName(level)}. File: {log_file or 'None'}")
