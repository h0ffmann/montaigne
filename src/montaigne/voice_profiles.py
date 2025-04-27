from pathlib import Path
from typing import Optional
import requests
import logging
import os

logger = logging.getLogger(__name__)

VOICE_PROFILES = {
    "bolsonaro": {
        "name": "Jair Bolsonaro",
        "description": "Former Brazilian president - strong, authoritative tone",
        "url": "https://example.com/voices/bolsonaro.wav",  # Replace with actual URL
        "local_path": "voices/bolsonaro.wav"
    },
    "lula": {
        "name": "Luiz Inácio Lula da Silva",
        "description": "Brazilian president - charismatic, raspy voice",
        "url": "https://example.com/voices/lula.wav",
        "local_path": "voices/lula.wav"
    },
    "supla": {
        "name": "Supla",
        "description": "Brazilian musician - distinctive rock voice",
        "url": "https://example.com/voices/supla.wav",
        "local_path": "voices/supla.wav"
    },
    "serginho": {
        "name": "Serginho Malandro",
        "description": "Brazilian TV personality - playful, energetic tone",
        "url": "https://example.com/voices/serginho.wav",
        "local_path": "voices/serginho.wav"
    },
    "bonner": {
        "name": "William Bonner",
        "description": "Brazilian news anchor - clear, professional tone",
        "url": "https://example.com/voices/bonner.wav",
        "local_path": "voices/bonner.wav"
    },
    "marilia": {
        "name": "Marília Gabriela",
        "description": "Brazilian journalist - sophisticated, articulate tone",
        "url": "https://example.com/voices/marilia.wav",
        "local_path": "voices/marilia.wav"
    },
    "bk": {
        "name": "BK (Rapper)",
        "description": "Brazilian rapper - urban, rhythmic speech pattern",
        "url": "https://example.com/voices/bk.wav",
        "local_path": "voices/bk.wav"
    },
    "maria_rita": {
        "name": "Maria Rita",
        "description": "Brazilian singer - smooth, melodic voice",
        "url": "https://example.com/voices/maria_rita.wav",
        "local_path": "voices/maria_rita.wav"
    },
    "clarice": {
        "name": "Clarice Lispector",
        "description": "Brazilian writer - thoughtful, philosophical tone",
        "url": "https://example.com/voices/clarice.wav",
        "local_path": "voices/clarice.wav"
    }
}

def get_voice_profile(profile_name: str, download_dir: str = "voices") -> Optional[Path]:
    """Get path to voice profile WAV file, downloading if needed."""
    if profile_name not in VOICE_PROFILES:
        return None
        
    profile = VOICE_PROFILES[profile_name]
    voice_path = Path(download_dir) / profile["local_path"]
    
    if not voice_path.exists():
        logger.info(f"Downloading voice profile: {profile['name']}")
        os.makedirs(download_dir, exist_ok=True)
        try:
            response = requests.get(profile["url"], stream=True)
            response.raise_for_status()
            with open(voice_path, "wb") as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            logger.info(f"Voice profile downloaded to: {voice_path}")
        except Exception as e:
            logger.error(f"Failed to download voice profile: {e}")
            return None
            
    return voice_path

def list_voice_profiles() -> list[str]:
    """Return list of available voice profile names."""
    return list(VOICE_PROFILES.keys())
