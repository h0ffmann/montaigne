#!/bin/bash
set -e

echo "🐍 Inside Nix environment. Installing workspace packages..."
# Call the simpler just task directly
just install-workspace

echo "✅ Workspace setup complete inside Nix environment."
echo "ℹ️ You can now run other commands or type 'exit' to leave."
exec bash # Keep the shell open
