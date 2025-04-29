# Montaigne BFF Architecture Implementation

This document outlines the implementation plan for adding a modern Backend-for-Frontend (BFF) architecture to the Montaigne TTS project, creating a web-based interface to the powerful TTS capabilities.

## 1. Project Structure

### 1.1 Directory Structure

```
montaigne-bff/
├── pyproject.toml         # Root workspace configuration
├── uv.lock                # Shared lock file for Python dependencies
├── justfile               # Updated with BFF-specific tasks
├── packages/
│   ├── montaigne/         # Existing montaigne codebase (core module)
│   │   └── ...            # (unchanged)
│   └── cicero/            # FastAPI backend (new)
│       ├── pyproject.toml
│       ├── src/
│       │   └── cicero/
│       │       ├── __init__.py
│       │       ├── main.py
│       │       ├── api/
│       │       │   ├── __init__.py
│       │       │   ├── endpoints/
│       │       │   │   ├── __init__.py
│       │       │   │   ├── tts.py
│       │       │   │   └── streaming.py
│       │       │   └── models/
│       │       │       ├── __init__.py
│       │       │       └── requests.py
│       │       ├── config/
│       │       │   ├── __init__.py
│       │       │   └── settings.py
│       │       └── services/
│       │           ├── __init__.py
│       │           └── tts_service.py
│       └── tests/
│           └── ...
└── burke/                 # Frontend application (new)
    ├── index.html
    ├── package.json
    ├── tsconfig.json
    ├── vite.config.ts
    └── src/
        ├── main.tsx
        ├── App.tsx
        ├── pages/
        │   ├── Home.tsx
        │   ├── BatchTTS.tsx
        │   └── StreamingTTS.tsx
        ├── components/
        │   ├── VoiceSelector.tsx
        │   ├── AudioPlayer.tsx
        │   ├── TextEditor.tsx
        │   ├── EngineSelector.tsx
        │   ├── StreamingPanel.tsx
        │   └── ui/
        │       ├── Button.tsx
        │       ├── Input.tsx
        │       └── ...
        ├── services/
        │   ├── api.ts
        │   ├── audioService.ts
        │   └── websocketService.ts
        └── assets/
            ├── styles/
            └── images/
```

## 2. Python Workspace Configuration (uv)

### 2.1 Root Configuration

Create a workspace root `pyproject.toml` to manage the Python-based packages:

```toml
[project]
name = "montaigne-bff"
version = "0.1.0"
description = "Montaigne TTS Backend for Frontend Architecture"
authors = [{ name = "Matheus Hoffmann", email = "hoffmann@poli.ufrj.br" }]
requires-python = ">=3.11,<3.12"
dependencies = []

[tool.uv.workspace]
members = ["packages/*"]

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"
```

### 2.2 Cicero Backend Configuration

Create a new `pyproject.toml` for the Cicero backend:

```toml
[project]
name = "cicero"
version = "0.1.0"
description = "FastAPI backend for the Montaigne TTS system"
authors = [{ name = "Matheus Hoffmann", email = "hoffmann@poli.ufrj.br" }]
requires-python = ">=3.11,<3.12"
dependencies = [
    "fastapi>=0.108.0",
    "uvicorn>=0.27.0",
    "pydantic>=2.5.0",
    "websockets>=12.0.0",
    "python-multipart>=0.0.7",
]

[project.optional-dependencies]
dev = [
    "ruff==0.11.7",
    "pytest==8.3.5",
    "httpx>=0.26.0",  # For FastAPI testing
]

[tool.uv.sources]
montaigne = { workspace = true }

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project.scripts]
cicero = "cicero.main:run"

[tool.ruff]
line-length = 88
select = ["E", "F", "W", "I", "N", "C4", "UP", "ARG", "B"]
ignore = ["B008"]

[tool.ruff.format]
quote-style = "double"
```

## 3. FastAPI Backend (Cicero) Implementation

### 3.1 Main Application Entry Point

**`packages/cicero/src/cicero/main.py`**:

```python
import logging
import sys
import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from cicero.api.endpoints import tts, streaming
from cicero.config.settings import get_settings

logger = logging.getLogger("cicero")

def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    settings = get_settings()
    
    app = FastAPI(
        title="Cicero API",
        description="Backend API for Montaigne TTS",
        version="0.1.0",
    )
    
    # Configure CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Exception handler
    @app.exception_handler(Exception)
    async def generic_exception_handler(request: Request, exc: Exception):
        logger.error(f"Unhandled exception: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"detail": "An unexpected error occurred."}
        )
    
    # Include routers
    app.include_router(tts.router, prefix="/api/tts", tags=["TTS"])
    app.include_router(streaming.router, prefix="/api/streaming", tags=["Streaming"])
    
    @app.get("/health")
    async def health_check():
        """Health check endpoint."""
        return {"status": "healthy"}
    
    return app

app = create_app()

def run():
    """Run the application with uvicorn server."""
    settings = get_settings()
    uvicorn.run(
        "cicero.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.RELOAD,
        log_level=settings.LOG_LEVEL.lower(),
    )

if __name__ == "__main__":
    run()
```

### 3.2 Configuration

**`packages/cicero/src/cicero/config/settings.py`**:

```python
import logging
import os
from functools import lru_cache
from typing import List

from pydantic import field_validator
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    """Application settings."""
    
    # API Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    RELOAD: bool = False
    LOG_LEVEL: str = "INFO"
    
    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:5173"]  # Vite dev server default port
    
    # TTS Configuration
    DEFAULT_ENGINE: str = "xtts"
    DEFAULT_LANGUAGE: str = "en"
    AUDIO_OUTPUT_DIR: str = "output"
    SPEAKER_WAV_DIR: str = "input"
    
    @field_validator("LOG_LEVEL")
    def validate_log_level(cls, v):
        allowed = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in allowed:
            raise ValueError(f"LOG_LEVEL must be one of {allowed}")
        return v.upper()
    
    class Config:
        env_prefix = "CICERO_"
        case_sensitive = True

@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()
```

### 3.3 TTS Endpoint

**`packages/cicero/src/cicero/api/endpoints/tts.py`**:

```python
import os
import uuid
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, File, Form, HTTPException, UploadFile, BackgroundTasks
from fastapi.responses import FileResponse

from cicero.api.models.requests import TTSRequest
from cicero.config.settings import get_settings
from cicero.services.tts_service import TTSService

router = APIRouter()
tts_service = TTSService()
settings = get_settings()

@router.get("/engines")
async def get_available_engines() -> List[str]:
    """Get list of available TTS engines."""
    return tts_service.get_available_engines()

@router.get("/voices")
async def get_available_voices() -> List[dict]:
    """Get list of available voice profiles."""
    return tts_service.get_available_voices()

@router.post("/synthesize")
async def synthesize_speech(
    background_tasks: BackgroundTasks,
    request: TTSRequest,
) -> dict:
    """Synthesize speech from text."""
    try:
        # Generate a unique job ID
        job_id = str(uuid.uuid4())
        
        # Create async task for synthesis
        output_path = await tts_service.synthesize(
            text=request.text,
            engine=request.engine,
            language=request.language,
            voice_profile=request.voice_profile,
            speaker_wav=request.speaker_wav,
            output_path=os.path.join(settings.AUDIO_OUTPUT_DIR, f"{job_id}.wav")
        )
        
        # Add cleanup task for later
        background_tasks.add_task(
            tts_service.cleanup, output_path, delay_seconds=3600  # Clean up after 1 hour
        )
        
        # Return job details
        return {
            "job_id": job_id,
            "status": "complete",
            "output_url": f"/api/tts/audio/{job_id}",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/upload-speaker")
async def upload_speaker_file(
    file: UploadFile = File(...),
) -> dict:
    """Upload a speaker reference file."""
    try:
        # Generate a unique filename
        file_id = str(uuid.uuid4())
        file_ext = os.path.splitext(file.filename)[1]
        filename = f"{file_id}{file_ext}"
        
        # Ensure directory exists
        os.makedirs(settings.SPEAKER_WAV_DIR, exist_ok=True)
        file_path = os.path.join(settings.SPEAKER_WAV_DIR, filename)
        
        # Save the uploaded file
        with open(file_path, "wb") as f:
            contents = await file.read()
            f.write(contents)
        
        return {
            "file_id": file_id,
            "filename": filename,
            "path": file_path,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/audio/{job_id}")
async def get_audio_file(job_id: str):
    """Get the audio file for a completed job."""
    file_path = os.path.join(settings.AUDIO_OUTPUT_DIR, f"{job_id}.wav")
    
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Audio file not found")
        
    return FileResponse(
        path=file_path,
        media_type="audio/wav",
        filename=f"tts_{job_id}.wav"
    )
```

### 3.4 Streaming Endpoint

**`packages/cicero/src/cicero/api/endpoints/streaming.py`**:

```python
import asyncio
import logging
import os
import uuid
from pathlib import Path
from typing import List

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from pydub import AudioSegment

from cicero.config.settings import get_settings
from cicero.services.tts_service import TTSService

router = APIRouter()
tts_service = TTSService()
settings = get_settings()
logger = logging.getLogger("cicero.streaming")

# Store active connections
active_connections: List[WebSocket] = []

@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for streaming TTS."""
    await websocket.accept()
    active_connections.append(websocket)
    
    session_id = str(uuid.uuid4())
    logger.info(f"New WebSocket connection: {session_id}")
    
    try:
        # Send initial connection confirmation
        await websocket.send_json({
            "type": "connection_established",
            "session_id": session_id
        })
        
        while True:
            # Wait for messages from the client
            data = await websocket.receive_json()
            message_type = data.get("type", "")
            
            if message_type == "tts_request":
                # Extract TTS parameters
                text = data.get("text", "")
                engine = data.get("engine", settings.DEFAULT_ENGINE)
                language = data.get("language", settings.DEFAULT_LANGUAGE)
                voice_profile = data.get("voice_profile")
                
                if not text:
                    await websocket.send_json({
                        "type": "error",
                        "message": "Text cannot be empty"
                    })
                    continue
                
                # Notify client that processing has started
                await websocket.send_json({
                    "type": "processing_started",
                    "text": text
                })
                
                # Process TTS request
                try:
                    # Generate audio in a separate thread to avoid blocking
                    output_path = await tts_service.synthesize_streaming(
                        text=text,
                        engine=engine,
                        language=language,
                        voice_profile=voice_profile,
                        session_id=session_id
                    )
                    
                    # Stream the audio data
                    await stream_audio_file(websocket, output_path)
                    
                    # Notify client that processing is complete
                    await websocket.send_json({
                        "type": "processing_complete"
                    })
                    
                except Exception as e:
                    logger.error(f"Error processing TTS request: {e}", exc_info=True)
                    await websocket.send_json({
                        "type": "error",
                        "message": str(e)
                    })
                    
            elif message_type == "ping":
                # Respond to ping messages
                await websocket.send_json({
                    "type": "pong",
                    "timestamp": data.get("timestamp")
                })
                
            else:
                # Handle unknown message types
                await websocket.send_json({
                    "type": "error",
                    "message": f"Unknown message type: {message_type}"
                })
                
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: {session_id}")
    except Exception as e:
        logger.error(f"WebSocket error: {e}", exc_info=True)
    finally:
        # Clean up connection
        if websocket in active_connections:
            active_connections.remove(websocket)
        logger.info(f"WebSocket connection closed: {session_id}")

async def stream_audio_file(websocket: WebSocket, file_path: str, chunk_size: int = 4096):
    """Stream an audio file to the client in chunks."""
    try:
        # Load the audio file
        audio = AudioSegment.from_wav(file_path)
        
        # Convert to bytes
        audio_bytes = audio.raw_data
        
        # Send audio metadata
        await websocket.send_json({
            "type": "audio_metadata",
            "format": "wav",
            "channels": audio.channels,
            "sample_rate": audio.frame_rate,
            "sample_width": audio.sample_width,
            "duration_ms": len(audio),
            "total_bytes": len(audio_bytes)
        })
        
        # Stream audio data in chunks
        for i in range(0, len(audio_bytes), chunk_size):
            chunk = audio_bytes[i:i+chunk_size]
            await websocket.send_bytes(chunk)
            
            # Simulate real-time streaming with a small delay
            await asyncio.sleep(0.05)
            
    except Exception as e:
        logger.error(f"Error streaming audio: {e}", exc_info=True)
        await websocket.send_json({
            "type": "error",
            "message": f"Error streaming audio: {str(e)}"
        })
```

### 3.5 API Models

**`packages/cicero/src/cicero/api/models/requests.py`**:

```python
from typing import Optional

from pydantic import BaseModel, Field

class TTSRequest(BaseModel):
    """Request model for TTS synthesis."""
    text: str = Field(..., description="Text to synthesize")
    engine: str = Field("xtts", description="TTS engine to use (xtts or bark)")
    language: str = Field("en", description="Language code")
    voice_profile: Optional[str] = Field(None, description="Voice profile name")
    speaker_wav: Optional[str] = Field(None, description="Path to speaker reference WAV file")
    speed: float = Field(1.0, description="Speech speed multiplier")
```

### 3.6 TTS Service

**`packages/cicero/src/cicero/services/tts_service.py`**:

```python
import asyncio
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import List, Optional, Dict

# Import core montaigne modules
from montaigne.tts_engine import XTTSv2Engine, BarkEngine
from montaigne.preprocessing import preprocess_text_for_tts, chunk_text
from montaigne.voice_profiles import list_voice_profiles, get_voice_profile
from montaigne.audio_utils import concatenate_audio_files, cleanup_files

logger = logging.getLogger("cicero.tts_service")
executor = ThreadPoolExecutor(max_workers=2)  # Limit concurrent TTS processes

class TTSService:
    """Service for TTS operations."""
    
    def __init__(self):
        """Initialize the TTS service."""
        self.engines = {}
        self.output_dir = Path("output")
        self.output_dir.mkdir(exist_ok=True)
        
    def get_engine(self, engine_type: str, use_cuda: bool = True):
        """Get or create a TTS engine instance."""
        engine_key = (engine_type, use_cuda)
        
        if engine_key not in self.engines:
            if engine_type == "xtts":
                self.engines[engine_key] = XTTSv2Engine(use_cuda=use_cuda)
            elif engine_type == "bark":
                self.engines[engine_key] = BarkEngine(use_cuda=use_cuda)
            else:
                raise ValueError(f"Unsupported engine type: {engine_type}")
                
        return self.engines[engine_key]
    
    def get_available_engines(self) -> List[str]:
        """Get list of available TTS engines."""
        return ["xtts", "bark"]
    
    def get_available_voices(self) -> List[dict]:
        """Get list of available voice profiles."""
        profile_names = list_voice_profiles()
        profiles = []
        
        for name in profile_names:
            profiles.append({
                "id": name,
                "name": name.capitalize(),
                "type": "profile"
            })
            
        return profiles
    
    async def synthesize(
        self,
        text: str,
        engine: str = "xtts",
        language: str = "en",
        voice_profile: Optional[str] = None,
        speaker_wav: Optional[str] = None,
        output_path: str = "output/output.wav",
        use_cuda: bool = True,
    ) -> str:
        """
        Synthesize speech from text.
        
        Args:
            text: Text to synthesize
            engine: TTS engine to use
            language: Language code
            voice_profile: Voice profile name
            speaker_wav: Path to speaker reference WAV file
            output_path: Path to save output audio
            use_cuda: Whether to use CUDA acceleration
            
        Returns:
            Path to the output audio file
        """
        # Run TTS in a separate thread to avoid blocking
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            executor,
            self._synthesize_speech,
            text, engine, language, voice_profile, speaker_wav, output_path, use_cuda
        )
        return result
    
    def _synthesize_speech(
        self,
        text: str,
        engine: str,
        language: str,
        voice_profile: Optional[str],
        speaker_wav: Optional[str],
        output_path: str,
        use_cuda: bool,
    ) -> str:
        """Internal synchronous implementation of speech synthesis."""
        try:
            start_time = time.time()
            logger.info(f"Starting TTS synthesis with {engine} engine")
            
            # Ensure output directory exists
            output_file = Path(output_path)
            output_file.parent.mkdir(parents=True, exist_ok=True)
            
            # Get engine instance
            engine_instance = self.get_engine(engine, use_cuda)
            
            # Prepare engine parameters
            engine_params = {}
            
            if engine == "xtts":
                # Determine speaker input
                if voice_profile:
                    speaker_wav_path = get_voice_profile(voice_profile)
                    if not speaker_wav_path:
                        raise ValueError(f"Voice profile not found: {voice_profile}")
                    engine_params["speaker_wav"] = speaker_wav_path
                elif speaker_wav:
                    engine_params["speaker_wav"] = Path(speaker_wav)
                else:
                    raise ValueError("Speaker WAV or voice profile required for XTTS")
            elif engine == "bark":
                # Optional speaker prompt for Bark
                if voice_profile:
                    engine_params["speaker_prompt"] = voice_profile
            
            # Preprocess and chunk text
            processed_text = preprocess_text_for_tts(text)
            text_chunks = chunk_text(processed_text)
            
            # Synthesize each chunk
            chunk_output_files = []
            for i, chunk in enumerate(text_chunks):
                chunk_output_path = output_file.parent / f"{output_file.stem}_chunk_{i}.wav"
                
                success = engine_instance.synthesize(
                    text=chunk,
                    language=language,
                    output_path=chunk_output_path,
                    **engine_params
                )
                
                if not success:
                    raise RuntimeError(f"Failed to synthesize chunk {i}")
                    
                chunk_output_files.append(chunk_output_path)
            
            # Concatenate chunks
            if len(chunk_output_files) > 1:
                concatenate_audio_files(chunk_output_files, output_file)
                # Clean up chunk files
                cleanup_files(chunk_output_files)
            elif len(chunk_output_files) == 1:
                # Just rename the single chunk file
                chunk_output_files[0].rename(output_file)
            
            duration = time.time() - start_time
            logger.info(f"TTS synthesis completed in {duration:.2f}s")
            
            return str(output_file)
            
        except Exception as e:
            logger.error(f"TTS synthesis failed: {e}", exc_info=True)
            raise
    
    async def synthesize_streaming(
        self,
        text: str,
        engine: str = "xtts",
        language: str = "en",
        voice_profile: Optional[str] = None,
        session_id: str = "session",
    ) -> str:
        """
        Synthesize speech for streaming.
        Similar to regular synthesis but optimized for streaming context.
        """
        # Create a unique output path for this streaming session
        output_path = f"output/stream_{session_id}_{int(time.time())}.wav"
        
        # Use the regular synthesis method
        return await self.synthesize(
            text=text,
            engine=engine,
            language=language,
            voice_profile=voice_profile,
            output_path=output_path,
            use_cuda=True,  # Always use CUDA for streaming if available
        )
    
    async def cleanup(self, file_path: str, delay_seconds: int = 0):
        """
        Clean up generated audio files after a delay.
        
        Args:
            file_path: Path to the file to clean up
            delay_seconds: Delay in seconds before cleanup
        """
        if delay_seconds > 0:
            await asyncio.sleep(delay_seconds)
            
        path = Path(file_path)
        if path.exists():
            try:
                path.unlink()
                logger.debug(f"Cleaned up file: {file_path}")
            except Exception as e:
                logger.error(f"Failed to clean up file {file_path}: {e}")
```

## 4. Frontend (Burke) Implementation with Vite + React + TypeScript

### 4.1 Package Configuration

**`burke/package.json`**:

```json
{
  "name": "burke",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "lint": "eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0",
    "preview": "vite preview"
  },
  "dependencies": {
    "@headlessui/react": "^1.7.18",
    "@heroicons/react": "^2.1.1",
    "axios": "^1.6.5",
    "classnames": "^2.5.1",
    "framer-motion": "^10.18.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.21.2",
    "tailwindcss": "^3.4.1",
    "tailwindcss-animate": "^1.0.7",
    "wavesurfer.js": "^7.5.2"
  },
  "devDependencies": {
    "@types/react": "^18.2.43",
    "@types/react-dom": "^18.2.17",
    "@typescript-eslint/eslint-plugin": "^6.14.0",
    "@typescript-eslint/parser": "^6.14.0",
    "@vitejs/plugin-react": "^4.2.1",
    "autoprefixer": "^10.4.16",
    "eslint": "^8.55.0",
    "eslint-plugin-react-hooks": "^4.6.0",
    "eslint-plugin-react-refresh": "^0.4.5",
    "postcss": "^8.4.33",
    "typescript": "^5.2.2",
    "vite": "^5.0.8"
  }
}
```

### 4.2 Vite Configuration

**`burke/vite.config.ts`**:

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
});
```

### 4.3 TypeScript Configuration

**`burke/tsconfig.json`**:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    
    /* Bundler mode */
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    
    /* Linting */
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    
    /* Path Aliases */
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

### 4.4 Key Frontend Components

#### Main App Component

**`burke/src/App.tsx`**:

```tsx
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { Suspense, lazy } from 'react';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import LoadingSpinner from './components/ui/LoadingSpinner';

// Lazy-loaded pages
const Home = lazy(() => import('./pages/Home'));
const BatchTTS = lazy(() => import('./pages/BatchTTS'));
const StreamingTTS = lazy(() => import('./pages/StreamingTTS'));
const NotFound = lazy(() => import('./pages/NotFound'));

function App() {
  return (
    <Router>
      <div className="flex flex-col min-h-screen bg-gradient-to-br from-slate-900 to-slate-800 text-white">
        <Navbar />
        <main className="flex-grow container mx-auto px-4 py-8">
          <Suspense fallback={<div className="flex justify-center items-center h-64"><LoadingSpinner size="lg" /></div>}>
            <Routes>
              <Route path="/" element={<Home />} />
              <Route path="/batch" element={<BatchTTS />} />
              <Route path="/streaming" element={<StreamingTTS />} />
              <Route path="*" element={<NotFound />} />
            </Routes>
          </Suspense>
        </main>
        <Footer />
      </div>
    </Router>
  );
}

export default App;
```

#### Streaming TTS Page

**`burke/src/pages/StreamingTTS.tsx`**:

```tsx
import { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import TextEditor from '../components/TextEditor';
import VoiceSelector from '../components/VoiceSelector';
import Button from '../components/ui/Button';
import StreamingPanel from '../components/StreamingPanel';
import { useWebSocket } from '../services/websocketService';
import { Voice } from '../types';

const StreamingTTS = () => {
  const [text, setText] = useState<string>('');
  const [selectedVoice, setSelectedVoice] = useState<Voice | null>(null);
  const [isStreaming, setIsStreaming] = useState<boolean>(false);
  const [audioBuffer, setAudioBuffer] = useState<Uint8Array | null>(null);
  const [availableVoices, setAvailableVoices] = useState<Voice[]>([]);
  const audioContextRef = useRef<AudioContext | null>(null);
  
  // WebSocket connection
  const { 
    connect, 
    disconnect, 
    sendMessage, 
    lastMessage, 
    lastBinaryMessage,
    connectionStatus 
  } = useWebSocket();
  
  useEffect(() => {
    // Initialize audio context
    if (!audioContextRef.current) {
      audioContextRef.current = new (window.AudioContext || (window as any).webkitAudioContext)();
    }
    
    // Fetch available voices
    const fetchVoices = async () => {
      try {
        const response = await fetch('/api/tts/voices');
        const data = await response.json();
        setAvailableVoices(data);
        
        // Select default voice if available
        if (data.length > 0) {
          setSelectedVoice(data[0]);
        }
      } catch (error) {
        console.error('Error fetching voices:', error);
      }
    };
    
    fetchVoices();
    
    // Connect to WebSocket on component mount
    connect('ws://localhost:8000/api/streaming/ws');
    
    // Cleanup on unmount
    return () => {
      disconnect();
      if (audioContextRef.current?.state !== 'closed') {
        audioContextRef.current?.close();
      }
    };
  }, [connect, disconnect]);
  
  // Handle text messages from WebSocket
  useEffect(() => {
    if (!lastMessage) return;
    
    try {
      const data = JSON.parse(lastMessage);
      
      switch (data.type) {
        case 'connection_established':
          console.log('Connected to streaming server');
          break;
        case 'processing_started':
          setIsStreaming(true);
          break;
        case 'processing_complete':
          setIsStreaming(false);
          break;
        case 'error':
          console.error('Streaming error:', data.message);
          setIsStreaming(false);
          break;
        default:
          // Handle other message types as needed
          break;
      }
    } catch (error) {
      console.error('Error parsing WebSocket message:', error);
    }
  }, [lastMessage]);
  
  // Handle binary audio data from WebSocket
  useEffect(() => {
    if (!lastBinaryMessage || !audioContextRef.current) return;
    
    // Convert binary message to audio buffer
    const audioData = new Uint8Array(lastBinaryMessage);
    setAudioBuffer(audioData);
    
    // Play the audio
    const playAudio = async () => {
      try {
        const audioCtx = audioContextRef.current!;
        const audioBuffer = await audioCtx.decodeAudioData(lastBinaryMessage);
        
        const source = audioCtx.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioCtx.destination);
        source.start(0);
      } catch (error) {
        console.error('Error playing audio:', error);
      }
    };
    
    playAudio();
  }, [lastBinaryMessage]);
  
  // Start streaming
  const handleStartStreaming = () => {
    if (!text || !selectedVoice) return;
    
    sendMessage(JSON.stringify({
      type: 'tts_request',
      text,
      engine: 'xtts',  // Default to XTTS for streaming
      language: 'en',  // Default to English
      voice_profile: selectedVoice.id
    }));
  };
  
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5 }}
      className="space-y-8"
    >
      <header className="text-center">
        <h1 className="text-4xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 text-transparent bg-clip-text">
          Live Streaming TTS
        </h1>
        <p className="mt-2 text-gray-300">
          Experience real-time text-to-speech streaming with instant feedback
        </p>
      </header>
      
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2">
          <TextEditor 
            value={text} 
            onChange={setText} 
            placeholder="Enter text to convert to speech..."
            disabled={isStreaming}
          />
        </div>
        
        <div className="space-y-6 bg-slate-800/50 p-6 rounded-xl border border-slate-700">
          <h2 className="text-xl font-semibold">Voice Settings</h2>
          
          <VoiceSelector
            voices={availableVoices}
            selectedVoice={selectedVoice}
            onSelect={setSelectedVoice}
            disabled={isStreaming}
          />
          
          <div className="pt-4">
            <Button
              onClick={handleStartStreaming}
              disabled={!text || !selectedVoice || isStreaming || connectionStatus !== 'OPEN'}
              isLoading={isStreaming}
              className="w-full"
              variant="primary"
            >
              {isStreaming ? 'Streaming...' : 'Start Streaming'}
            </Button>
          </div>
          
          <div className="text-xs text-gray-400 mt-2">
            {connectionStatus === 'CONNECTING' && 'Connecting to streaming server...'}
            {connectionStatus === 'CLOSED' && 'Connection to streaming server closed. Please refresh.'}
            {connectionStatus === 'OPEN' && 'Connected to streaming server'}
          </div>
        </div>
      </div>
      
      <StreamingPanel
        isStreaming={isStreaming}
        audioBuffer={audioBuffer}
        text={text}
      />
    </motion.div>
  );
};

export default StreamingTTS;
```

#### Batch TTS Page

**`burke/src/pages/BatchTTS.tsx`**:

```tsx
import { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import TextEditor from '../components/TextEditor';
import VoiceSelector from '../components/VoiceSelector';
import EngineSelector from '../components/EngineSelector';
import AudioPlayer from '../components/AudioPlayer';
import Button from '../components/ui/Button';
import { synthesizeSpeech, uploadSpeakerFile } from '../services/api';
import { Voice, Engine } from '../types';

const BatchTTS = () => {
  const [text, setText] = useState<string>('');
  const [selectedVoice, setSelectedVoice] = useState<Voice | null>(null);
  const [selectedEngine, setSelectedEngine] = useState<Engine>('xtts');
  const [isProcessing, setIsProcessing] = useState<boolean>(false);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [availableVoices, setAvailableVoices] = useState<Voice[]>([]);
  const [speakerFile, setSpeakerFile] = useState<File | null>(null);
  const [uploadedSpeakerPath, setUploadedSpeakerPath] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  
  // Fetch available voices
  useEffect(() => {
    const fetchVoices = async () => {
      try {
        const response = await fetch('/api/tts/voices');
        const data = await response.json();
        setAvailableVoices(data);
        
        // Select default voice if available
        if (data.length > 0) {
          setSelectedVoice(data[0]);
        }
      } catch (error) {
        console.error('Error fetching voices:', error);
        setError('Failed to fetch voices. Please try again later.');
      }
    };
    
    fetchVoices();
  }, []);
  
  // Handle speaker file upload
  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = event.target.files;
    if (!files || files.length === 0) return;
    
    const file = files[0];
    
    // Only accept audio files
    if (!file.type.startsWith('audio/')) {
      setError('Please upload an audio file (WAV, MP3, etc.)');
      return;
    }
    
    setSpeakerFile(file);
    
    try {
      setIsProcessing(true);
      const result = await uploadSpeakerFile(file);
      setUploadedSpeakerPath(result.path);
      setError(null);
    } catch (err) {
      console.error('Error uploading speaker file:', err);
      setError('Failed to upload speaker file. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };
  
  // Handle synthesis
  const handleSynthesize = async () => {
    if (!text) {
      setError('Please enter some text to synthesize');
      return;
    }
    
    if (selectedEngine === 'xtts' && !selectedVoice && !uploadedSpeakerPath) {
      setError('Please select a voice or upload a speaker file for XTTS');
      return;
    }
    
    try {
      setIsProcessing(true);
      setError(null);
      
      const result = await synthesizeSpeech({
        text,
        engine: selectedEngine,
        language: 'en',  // Default to English for now
        voice_profile: selectedVoice?.id,
        speaker_wav: uploadedSpeakerPath,
      });
      
      setAudioUrl(result.output_url);
    } catch (err: any) {
      console.error('Synthesis error:', err);
      setError(err.message || 'Failed to synthesize speech. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };
  
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5 }}
      className="space-y-8"
    >
      <header className="text-center">
        <h1 className="text-4xl font-bold bg-gradient-to-r from-blue-400 to-purple-500 text-transparent bg-clip-text">
          Batch Text-to-Speech
        </h1>
        <p className="mt-2 text-gray-300">
          Convert text to high-quality speech using powerful AI models
        </p>
      </header>
      
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2">
          <TextEditor 
            value={text} 
            onChange={setText} 
            placeholder="Enter text to convert to speech..."
            disabled={isProcessing}
          />
        </div>
        
        <div className="space-y-6 bg-slate-800/50 p-6 rounded-xl border border-slate-700">
          <h2 className="text-xl font-semibold">Synthesis Settings</h2>
          
          <EngineSelector
            selectedEngine={selectedEngine}
            onSelect={setSelectedEngine}
            disabled={isProcessing}
          />
          
          {selectedEngine === 'xtts' && (
            <>
              <VoiceSelector
                voices={availableVoices}
                selectedVoice={selectedVoice}
                onSelect={setSelectedVoice}
                disabled={isProcessing}
              />
              
              <div className="space-y-2">
                <label className="block text-sm font-medium">
                  Or upload your own voice
                </label>
                <input
                  type="file"
                  accept="audio/*"
                  onChange={handleFileChange}
                  disabled={isProcessing}
                  className="block w-full text-sm text-gray-400
                    file:mr-4 file:py-2 file:px-4
                    file:rounded-lg file:border-0
                    file:text-sm file:font-medium
                    file:bg-blue-600/20 file:text-blue-400
                    hover:file:bg-blue-600/30
                    focus:outline-none disabled:opacity-70"
                />
                {speakerFile && (
                  <p className="text-xs text-green-400">
                    {uploadedSpeakerPath ? 'File uploaded!' : 'Selected: '} 
                    {speakerFile.name}
                  </p>
                )}
              </div>
            </>
          )}
          
          {error && (
            <div className="text-red-400 text-sm p-2 bg-red-900/20 border border-red-900/50 rounded">
              {error}
            </div>
          )}
          
          <div className="pt-4">
            <Button
              onClick={handleSynthesize}
              disabled={isProcessing || !text}
              isLoading={isProcessing}
              className="w-full"
              variant="primary"
            >
              {isProcessing ? 'Synthesizing...' : 'Synthesize Speech'}
            </Button>
          </div>
        </div>
      </div>
      
      {audioUrl && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-slate-800/50 p-6 rounded-xl border border-slate-700"
        >
          <h2 className="text-xl font-semibold mb-4">Generated Audio</h2>
          <AudioPlayer audioUrl={audioUrl} />
        </motion.div>
      )}
    </motion.div>
  );
};

export default BatchTTS;
```

#### Audio Player Component

**`burke/src/components/AudioPlayer.tsx`**:

```tsx
import { useEffect, useRef, useState } from 'react';
import WaveSurfer from 'wavesurfer.js';
import { PlayIcon, PauseIcon } from '@heroicons/react/24/solid';
import Button from './ui/Button';

interface AudioPlayerProps {
  audioUrl: string;
}

const AudioPlayer = ({ audioUrl }: AudioPlayerProps) => {
  const waveformRef = useRef<HTMLDivElement>(null);
  const wavesurferRef = useRef<WaveSurfer | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  
  // Initialize WaveSurfer
  useEffect(() => {
    if (!waveformRef.current) return;
    
    setIsLoading(true);
    
    // Clean up previous instance
    if (wavesurferRef.current) {
      wavesurferRef.current.destroy();
    }
    
    // Create WaveSurfer instance
    const wavesurfer = WaveSurfer.create({
      container: waveformRef.current,
      waveColor: '#4f46e5',
      progressColor: '#818cf8',
      cursorColor: '#c7d2fe',
      barWidth: 2,
      barGap: 1,
      barRadius: 2,
      height: 80,
      normalize: true,
    });
    
    wavesurferRef.current = wavesurfer;
    
    // Load audio file
    wavesurfer.load(audioUrl);
    
    // Register events
    wavesurfer.on('ready', () => {
      setDuration(wavesurfer.getDuration());
      setIsLoading(false);
    });
    
    wavesurfer.on('play', () => setIsPlaying(true));
    wavesurfer.on('pause', () => setIsPlaying(false));
    wavesurfer.on('audioprocess', () => setCurrentTime(wavesurfer.getCurrentTime()));
    wavesurfer.on('seek', () => setCurrentTime(wavesurfer.getCurrentTime()));
    
    // Clean up on unmount
    return () => {
      if (wavesurferRef.current) {
        wavesurferRef.current.destroy();
      }
    };
  }, [audioUrl]);
  
  // Toggle play/pause
  const togglePlayPause = () => {
    if (!wavesurferRef.current) return;
    wavesurferRef.current.playPause();
  };
  
  // Format time (seconds to mm:ss)
  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };
  
  return (
    <div className="space-y-4">
      <div className="flex items-center space-x-4">
        <Button
          onClick={togglePlayPause}
          disabled={isLoading}
          variant="secondary"
          className="w-14 h-14 rounded-full flex items-center justify-center"
        >
          {isPlaying ? (
            <PauseIcon className="w-6 h-6" />
          ) : (
            <PlayIcon className="w-6 h-6" />
          )}
        </Button>
        
        <div className="flex-1">
          <div className="flex justify-between text-sm text-gray-400 mb-1">
            <span>{formatTime(currentTime)}</span>
            <span>{formatTime(duration)}</span>
          </div>
          
          <div 
            ref={waveformRef} 
            className={`relative bg-slate-700/50 rounded-lg overflow-hidden ${isLoading ? 'animate-pulse' : ''}`}
          />
        </div>
      </div>
      
      <div className="flex justify-end">
        <a
          href={audioUrl}
          download="synthesized-speech.wav"
          className="text-sm text-indigo-400 hover:text-indigo-300 transition-colors flex items-center gap-1"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clipRule="evenodd" />
          </svg>
          Download audio
        </a>
      </div>
    </div>
  );
};

export default AudioPlayer;
```

#### Streaming Panel Component

**`burke/src/components/StreamingPanel.tsx`**:

```tsx
import { useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { SpeakerWaveIcon, SpeakerXMarkIcon } from '@heroicons/react/24/solid';

interface StreamingPanelProps {
  isStreaming: boolean;
  audioBuffer: Uint8Array | null;
  text: string;
}

const StreamingPanel = ({ isStreaming, audioBuffer, text }: StreamingPanelProps) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationFrameRef = useRef<number | null>(null);
  const [isMuted, setIsMuted] = useState(false);
  
  // Visualize audio data
  useEffect(() => {
    if (!isStreaming || !audioBuffer || !canvasRef.current) return;
    
    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    
    // Set canvas size
    canvas.width = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
    
    // Calculate visualizer data
    const bufferLength = audioBuffer.length;
    const dataArray = new Uint8Array(bufferLength);
    
    // Copy audio data
    for (let i = 0; i < bufferLength; i++) {
      dataArray[i] = audioBuffer[i];
    }
    
    // Draw visualization
    const draw = () => {
      // Request next frame
      animationFrameRef.current = requestAnimationFrame(draw);
      
      // Clear canvas
      ctx.fillStyle = 'rgba(15, 23, 42, 0.1)';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      
      // Set line style
      ctx.lineWidth = 2;
      ctx.strokeStyle = 'rgb(129, 140, 248)';
      ctx.beginPath();
      
      const sliceWidth = (canvas.width * 1.0) / bufferLength;
      let x = 0;
      
      // Draw waveform
      for (let i = 0; i < bufferLength; i++) {
        const v = dataArray[i] / 128.0;
        const y = (v * canvas.height) / 2;
        
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
        
        x += sliceWidth;
      }
      
      ctx.lineTo(canvas.width, canvas.height / 2);
      ctx.stroke();
    };
    
    // Start animation
    draw();
    
    // Clean up
    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
    };
  }, [isStreaming, audioBuffer]);
  
  // Handle window resize
  useEffect(() => {
    const handleResize = () => {
      if (canvasRef.current) {
        canvasRef.current.width = canvasRef.current.offsetWidth;
        canvasRef.current.height = canvasRef.current.offsetHeight;
      }
    };
    
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);
  
  return (
    <AnimatePresence>
      {isStreaming && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 20 }}
          className="bg-slate-800/50 p-6 rounded-xl border border-slate-700"
        >
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold flex items-center">
              <div className="w-3 h-3 bg-green-500 rounded-full mr-2 animate-pulse" />
              Streaming Audio
            </h2>
            
            <button
              onClick={() => setIsMuted(!isMuted)}
              className="text-gray-400 hover:text-white transition-colors"
              aria-label={isMuted ? "Unmute" : "Mute"}
            >
              {isMuted ? (
                <SpeakerXMarkIcon className="w-6 h-6" />
              ) : (
                <SpeakerWaveIcon className="w-6 h-6" />
              )}
            </button>
          </div>
          
          <div className="h-24 mb-4">
            <canvas 
              ref={canvasRef} 
              className="w-full h-full bg-slate-900/30 rounded-lg"
            />
          </div>
          
          <div className="flex justify-between items-center text-sm text-gray-400">
            <div>Current speech</div>
            <div className="animate-pulse text-blue-400">
              Receiving audio stream...
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

export default StreamingPanel;
```

### 4.5 API Services

**`burke/src/services/api.ts`**:

```typescript
import axios from 'axios';
import { TTSRequest } from '../types';

const api = axios.create({
  baseURL: '/api',
  headers: {
    'Content-Type': 'application/json',
  },
});

export const getAvailableEngines = async () => {
  const response = await api.get('/tts/engines');
  return response.data;
};

export const getAvailableVoices = async () => {
  const response = await api.get('/tts/voices');
  return response.data;
};

export const synthesizeSpeech = async (request: TTSRequest) => {
  const response = await api.post('/tts/synthesize', request);
  return response.data;
};

export const uploadSpeakerFile = async (file: File) => {
  const formData = new FormData();
  formData.append('file', file);
  
  const response = await api.post('/tts/upload-speaker', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
  });
  
  return response.data;
};
```

**`burke/src/services/websocketService.ts`**:

```typescript
import { useState, useEffect, useCallback, useRef } from 'react';

type ConnectionStatus = 'CONNECTING' | 'OPEN' | 'CLOSING' | 'CLOSED';

interface UseWebSocketReturn {
  connect: (url: string) => void;
  disconnect: () => void;
  sendMessage: (message: string) => void;
  lastMessage: string | null;
  lastBinaryMessage: ArrayBuffer | null;
  connectionStatus: ConnectionStatus;
}

export const useWebSocket = (): UseWebSocketReturn => {
  const [lastMessage, setLastMessage] = useState<string | null>(null);
  const [lastBinaryMessage, setLastBinaryMessage] = useState<ArrayBuffer | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>('CLOSED');
  
  const ws = useRef<WebSocket | null>(null);
  
  const connect = useCallback((url: string) => {
    // Close existing connection if any
    if (ws.current) {
      ws.current.close();
    }
    
    // Create new WebSocket connection
    setConnectionStatus('CONNECTING');
    ws.current = new WebSocket(url);
    
    // Setup event handlers
    ws.current.onopen = () => {
      setConnectionStatus('OPEN');
      console.log('WebSocket connection established');
    };
    
    ws.current.onmessage = (event) => {
      if (typeof event.data === 'string') {
        setLastMessage(event.data);
      } else if (event.data instanceof ArrayBuffer) {
        setLastBinaryMessage(event.data);
      } else if (event.data instanceof Blob) {
        // Convert Blob to ArrayBuffer
        const reader = new FileReader();
        reader.onload = () => {
          if (reader.result instanceof ArrayBuffer) {
            setLastBinaryMessage(reader.result);
          }
        };
        reader.readAsArrayBuffer(event.data);
      }
    };
    
    ws.current.onclose = () => {
      setConnectionStatus('CLOSED');
      console.log('WebSocket connection closed');
    };
    
    ws.current.onerror = (error) => {
      console.error('WebSocket error:', error);
      setConnectionStatus('CLOSED');
    };
  }, []);
  
  const disconnect = useCallback(() => {
    if (ws.current && ws.current.readyState === WebSocket.OPEN) {
      setConnectionStatus('CLOSING');
      ws.current.close();
    }
  }, []);
  
  const sendMessage = useCallback((message: string) => {
    if (ws.current && ws.current.readyState === WebSocket.OPEN) {
      ws.current.send(message);
    } else {
      console.error('WebSocket is not connected');
    }
  }, []);
  
  // Clean up WebSocket on unmount
  useEffect(() => {
    return () => {
      if (ws.current) {
        ws.current.close();
      }
    };
  }, []);
  
  return {
    connect,
    disconnect,
    sendMessage,
    lastMessage,
    lastBinaryMessage,
    connectionStatus,
  };
};
```

## 5. Updated Justfile for BFF Tasks

Add the following tasks to the existing `justfile`:

```makefile
# === BFF Environment Tasks ===
setup_bff:
    @echo "🏗️ Setting up BFF architecture..."
    @mkdir -p packages/cicero/src/cicero/{api/{endpoints,models},config,services}
    @mkdir -p packages/cicero/tests
    @mkdir -p burke/{public,src/{components/{ui},pages,services,assets/{styles,images}}}
    @echo "✅ BFF structure created."

# Install frontend dependencies
install_frontend:
    @echo "📦 Installing frontend dependencies..."
    @cd burke && npm install
    @echo "✅ Frontend dependencies installed."

# Start backend (Cicero FastAPI server)
start_backend:
    @echo "🚀 Starting Cicero backend server..."
    @cd packages/cicero && nix develop --impure --command uvicorn cicero.main:app --reload --host 0.0.0.0 --port 8000

# Start frontend (Burke Vite server)
start_frontend:
    @echo "🚀 Starting Burke frontend server..."
    @cd burke && npm run dev

# Start both servers concurrently (requires tmux)
start_bff:
    @echo "🚀 Starting both backend and frontend servers..."
    @tmux new-session -d -s montaigne-bff "just start_backend"
    @tmux split-window -h -t montaigne-bff "just start_frontend"
    @tmux -2 attach-session -t montaigne-bff

# Stop BFF servers
stop_bff:
    @echo "🛑 Stopping BFF servers..."
    @tmux kill-session -t montaigne-bff || true
    @echo "✅ BFF servers stopped."

# Build frontend for production
build_frontend:
    @echo "🏗️ Building frontend for production..."
    @cd burke && npm run build
    @echo "✅ Frontend built successfully."

# Run full dev environment with one command
run_bff: setup_bff install_frontend start_bff
```

## 6. Deployment Considerations

### 6.1 Docker Compose for BFF Architecture

Create a `docker-compose.yml` file in the project root:

```yaml
version: '3.8'

services:
  cicero:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        - USE_LOCAL_MODEL=true
    ports:
      - "8000:8000"
    volumes:
      - ./packages:/app/packages
      - ./input:/app/input
      - ./output:/app/output
    environment:
      - CICERO_LOG_LEVEL=INFO
      - CICERO_CORS_ORIGINS=http://localhost:5173,http://localhost:4173
    command: cicero
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  burke:
    build:
      context: ./burke
      dockerfile: Dockerfile
    ports:
      - "4173:4173"
    depends_on:
      - cicero
```

### 6.2 Dockerfile for Burke Frontend

Create a Dockerfile for the Burke frontend:

```dockerfile
# Build stage
FROM node:20-alpine as build

WORKDIR /app

# Copy package files
COPY package.json package-lock.json ./

# Install dependencies
RUN npm ci

# Copy source files
COPY . .

# Build the app
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built assets from build stage
COPY --from=build /app/dist /usr/share/nginx/html

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 4173

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
```

### 6.3 Nginx Configuration for Burke

Create `burke/nginx.conf`:

```nginx
server {
    listen 4173;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # vite app
    location / {
        try_files $uri $uri/ /index.html;
    }

    # api proxy
    location /api/ {
        proxy_pass http://cicero:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # websocket proxy
    location /api/streaming/ws {
        proxy_pass http://cicero:8000/api/streaming/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
    }
}
```

## 7. Summary and Next Steps

The BFF architecture for Montaigne provides a modern, user-friendly interface to the powerful TTS capabilities:

1. **Core Module (Montaigne)**: Provides the TTS engines and processing logic
2. **Backend (Cicero)**: Exposes REST and WebSocket APIs for batch synthesis and streaming
3. **Frontend (Burke)**: Modern React UI with real-time audio streaming and visualization

**Key Features Implemented:**
- Batch TTS generation with multiple engine options
- Real-time streaming TTS with WebSocket connection
- Modern, AI-themed UI with animations and visualizations
- Audio waveform visualization and playback
- Voice profile selection and speaker file upload
- Audio download capability

**Next Steps:**
1. Add user authentication/sessions for persistent settings
2. Implement history tracking of generated audio
3. Add more language support and voice customization options
4. Optimize streaming performance for longer texts
5. Add analytics for usage tracking
6. Implement caching for frequently used voice profiles