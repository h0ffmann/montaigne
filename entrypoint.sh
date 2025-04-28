#!/bin/bash
set -e

# Optional: Just print PyTorch version for confirmation
/usr/bin/python3.11 -c "import torch; print(f\"---> PyTorch version: {torch.__version__}\", flush=True)" || echo "⚠️ Could not print PyTorch version."

# Execute the original command
echo "🚀 Executing Docker CMD/args: $@" 
exec "$@"
