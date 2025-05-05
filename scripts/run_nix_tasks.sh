#!/bin/bash
# This script executes tasks within the Nix environment for the 'all' pipeline.
# It calls existing just tasks which should have the correct environment setup.
set -e

echo "--- [Nix Env] Check Basic Tools (inside script) ---"
echo "🐍 Python: $(python --version)"
echo "📦 UV: $(uv --version)"
# Can't reliably check ruff directly here if path is the issue, just tasks below will test it

echo "--- [Nix Env] Installing Workspace Packages ---"
# Assuming 'just install-workspace' works correctly when run from shell
just install-workspace

echo "--- [Nix Env] Running Linter and Formatter Checks (via just) ---"
# Delegate to the just task which should find ruff
just fix # Runs 'just lint' and 'just format' internally

echo "--- [Nix Env] Generating Repomix (via just) ---"
# Delegate to the just task which should find repomix
just mix

echo "--- [Nix Env] Preparing Directories (via just) ---"
# Delegate to the just task which should find ffmpeg
just prepare-dirs

echo "--- [Nix Env] Running TTS Synthesis Tasks (via just) ---"
# Delegate to the just task which should find python and run the modules
# This single task runs xtts, bark, and yt internally
just run_nix_tts_tasks

echo "--- [Nix Env] Script tasks via delegation completed Successfully ---"
