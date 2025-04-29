#!/bin/bash
set -e

# MODEL_PATH_VAR needs to be passed as an environment variable
if [ -z "$MODEL_PATH_VAR" ]; then
    echo "❌ MODEL_PATH_VAR environment variable not set for script."
    exit 1
fi

echo "📦 Preparing local TTS model directory..."
mkdir -p model_files
echo "   Checking for model at: $MODEL_PATH_VAR"

if [ -d "$MODEL_PATH_VAR" ]; then
    echo '   Found local model - copying to build context (./model_files)...'
    # Use rsync for efficient copy, show progress
    if ! rsync -a --info=progress2 "$MODEL_PATH_VAR/" model_files/; then
        echo '   ❌ Failed to copy local model.'
        echo '   ⚠️ Continuing build without pre-copied local model.'
        # exit 1; # Optional: Make this error fatal
    else
        echo "   ✅ Local model copied successfully."
    fi
else
    echo "   ⚠️ Local model not found at '$MODEL_PATH_VAR'."
    echo "      If USE_LOCAL_MODEL=true is set in Docker build args, it might fail or download."
fi
