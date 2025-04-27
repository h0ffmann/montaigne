# flake.nix - Flake definition for Montaigne Development Environment (Final Fix 2)
{
  description = "Development environment for Montaigne (Python TTS/STT) & AI Tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };

        montaignePkgs = with pkgs; [
          bashInteractive
          coreutils
          git
          jq
          just
          ripgrep
          fd
          curl
          wget
          openssl
          pkg-config
          gcc
          gnumake
          python311
          uv
          nodejs_22
          corepack_22
          ffmpeg
          libsndfile
          alsa-lib
          libGL
          stdenv.cc.cc.lib
          speedtest-cli
          dig
          nmap
          lsof
          busybox
        ];

        requiredLibPath = pkgs.lib.makeLibraryPath [
          pkgs.ffmpeg
          pkgs.libsndfile
          pkgs.alsa-lib
          pkgs.libGL
          pkgs.stdenv.cc.cc.lib
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          name = "montaigne-dev-env";
          packages = montaignePkgs;

          env = {
            LD_LIBRARY_PATH = requiredLibPath;
          };

          shellHook = ''
            # Welcome message
            echo "👋 Entering Focused Montaigne Development Environment (Flake)..."

            # Set shell options
            set -o pipefail

            # --- NPM Global Setup ---
            if [ -z "$HOME" ]; then echo "⚠️ ERROR: \$HOME not set."; exit 1; fi
            export NPM_CONFIG_PREFIX="$HOME/.npm-global"
            export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
            echo "   Ensuring Node global directory exists: $HOME/.npm-global/bin"
            mkdir -p "$HOME/.npm-global/bin"
            # --- End NPM Global Setup ---

            # Check optional Docker/Podman status
            if command -v docker &>/dev/null; then
                if ! docker ps > /dev/null 2>&1; then echo "⚠️ Warning: Cannot connect to Docker daemon."; fi
            elif command -v podman &>/dev/null; then echo "ℹ️ Podman available."; else echo "⚠️ Warning: Docker/Podman not found."; fi

            # --- Python setup instructions (CORRECTED VENV_DIR definition) ---
            echo "🐍 Python Environment ($(python -V)): Managed by uv."
            # Fix: Removed unnecessary backslash \ before " in the f-string
            VENV_DIR=".venv-py$(python -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')"
            if [ -f "$VENV_DIR/bin/activate" ]; then
               echo "   Python venv '$VENV_DIR' exists. Activate with: source $VENV_DIR/bin/activate"
               echo "   Run 'just setup' or 'just install' if needed."
            else
               echo "   Python venv '$VENV_DIR' not found. Run 'just setup'."
            fi
            # --- End Python Setup ---

            # Node.js Instructions
            echo "🕸️ Node.js Environment ($(node -v)) ready."
            echo "   Global node packages path added to PATH: $NPM_CONFIG_PREFIX/bin" # Use var for echo
            echo "   To install global tools (repomix, etc.):"
            echo "   npm install -g repomix @anthropic-ai/claude-code @modelcontextprotocol/server-brave-search"

            # .env loading
            echo "🔑 Checking for .env file..."
            if [ -f ".env" ]; then
              echo "   Found .env, loading variables..."
              temp_env_vars=$(mktemp)
              # Filter and write valid lines to temp file
              grep -vE '^\s*(#|$)' .env > "$temp_env_vars"
              # Process temp file if it's not empty
              if [ -s "$temp_env_vars" ]; then
                 while IFS= read -r line || [ -n "$line" ]; do # Handle last line without newline
                    # Ensure line looks like KEY=VALUE before exporting
                    if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*=.* ]]; then
                       export "$line"
                    fi
                 done < "$temp_env_vars"
                 echo "   ✅ Variables potentially loaded from .env (verify)."
              else
                 echo "   ℹ️ .env found, but no loadable variable lines.";
              fi
              rm "$temp_env_vars" # Clean up temp file regardless
            else
              echo "   ⚠️ .env file not found."; if [ -f ".env.example" ]; then echo "   💡 Hint: Found '.env.example'. Copy/edit: cp .env.example .env"; fi
            fi

            # Final readiness message
            echo ""
            echo "✨ Montaigne AI/TTS flake environment is ready! ✨"
            echo ""
            echo "📌 Quick Start:"
            echo "   just setup             # Create venv, install project deps"
            echo "   source $VENV_DIR/bin/activate  # Activate Python venv"
            echo "   just run -- --help   # Run the montaigne CLI"
            echo ""
          '';
        };
      });
}
