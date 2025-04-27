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


def chunk_text(text: str, max_chunk_len: int = 250, strategy: str = "paragraph") -> list[str]:
    """
    Splits text into chunks suitable for TTS processing.

    Args:
        text: The input text string.
        max_chunk_len: Approximate maximum character length for each chunk.
                       XTTSv2 limit is ~200-250 depending on language/complexity.
        strategy: The chunking strategy ('paragraph' supported for now).

    Returns:
        A list of text chunks.
    """
    chunks = []
    if strategy == "paragraph":
        # Split by double newlines, preserving single newlines within paragraphs
        paragraphs = re.split(r'\n\s*\n', text)
        for i, para in enumerate(paragraphs):
            para = para.strip()
            if not para:
                continue
            # Basic check: if paragraph is too long, log a warning for now.
            # Future: Implement sentence splitting within long paragraphs.
            if len(para) > max_chunk_len * 1.5: # Allow some leeway
                 logger.warning(f"Paragraph {i+1} significantly exceeds max_chunk_len ({len(para)} chars). Consider sentence splitting. Content: '{para[:100]}...'")
            # Even if long, add it as one chunk for now with paragraph strategy
            chunks.append(para)

    else:
        logger.warning(f"Unsupported chunking strategy '{strategy}'. Defaulting to single chunk.")
        chunks.append(text) # Fallback

    logger.info(f"Split text into {len(chunks)} chunks using '{strategy}' strategy.")
    return chunks
