#!/usr/bin/env bash
set -e

echo "--- [Nix Env] Installing Workspace Packages ---"
just install_workspace

echo "--- [Nix Env] Running Linter and Formatter Checks ---"
just check

echo "--- [Nix Env] Generating Repomix ---"
just mix

echo "--- [Nix Env] Preparing Directories ---"
just prepare_dirs

echo "--- [Nix Env] Running TTS Synthesis Tasks ---"
just xtts
just bark
just yt

echo "--- [Nix Env] Tasks Completed Successfully ---"
