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
