# flake.nix - Flake definition for Montaigne Development Environment (Corrected with CUDA Support)
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
            cudaSupport = true;
          };
        };

        # Get CUDA toolkit for PyTorch 2.3.1 (which expects CUDA 12.1)
        cuda_toolkit = pkgs.cudaPackages_12_1.cudatoolkit;

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
          # Add CUDA toolkit explicitly
          cuda_toolkit
        ];

        requiredSysLibs = with pkgs; [
          ffmpeg
          libsndfile
          alsa-lib
          libGL
          stdenv.cc.cc.lib
          # Add CUDA libraries
          cuda_toolkit
          cudaPackages_12_1.cudnn
        ];

        requiredLibPath = pkgs.lib.makeLibraryPath requiredSysLibs;

      in
      {
        devShells.default = pkgs.mkShell {
          name = "montaigne-dev-env";
          packages = montaignePkgs;

          env = {
            # Keep this minimal but include CUDA paths
            LD_LIBRARY_PATH = requiredLibPath;
            # Define NPM_CONFIG_PREFIX here to make it available throughout the shell
            NPM_CONFIG_PREFIX = "$HOME/.npm-global";
            # Set CUDA_HOME for PyTorch to find CUDA
            CUDA_HOME = "${cuda_toolkit}";
          };

          shellHook = ''
            # Welcome message
            echo "👋 Entering Focused Montaigne Development Environment (Flake)..."
            
            # Display CUDA information
            echo "🚀 CUDA Environment:"
            echo "   CUDA Toolkit: $(${pkgs.cudaPackages_12_1.cudatoolkit}/bin/nvcc --version 2>/dev/null || echo 'CUDA Toolkit installed but nvcc not found')"
            echo "   CUDA_HOME: $CUDA_HOME"
            
            # --- CORRECTED: Use the explicit path in PATH modification ---
            # Ensure user's local bin and npm global bin are in PATH
            export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

            # Ensure npm global bin dir exists
            mkdir -p "$HOME/.npm-global/bin"

            set -o pipefail

            # Check optional Docker/Podman status
            if command -v docker &>/dev/null; then
                if ! docker ps > /dev/null 2>&1; then echo "⚠️ Warning: Cannot connect to Docker daemon."; fi
            elif command -v podman &>/dev/null; then echo "ℹ️ Podman available."; else echo "⚠️ Warning: Docker/Podman not found."; fi

            # Python setup instructions
            echo "🐍 Python Environment ($(python -V)): Managed by uv."
            VENV_DIR=".venv-py$(python -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')"
            if [ -f "$VENV_DIR/bin/activate" ]; then
               echo "   Python venv '$VENV_DIR' exists. Activate with: source $VENV_DIR/bin/activate"
               echo "   Run 'just setup' or 'just install' if needed."
            else
               echo "   Python venv '$VENV_DIR' not found. Run 'just setup'."
            fi

            # Node.js Instructions
            echo "🕸️ Node.js Environment ($(node -v)) ready."
            echo "   Global node packages path (in PATH): $HOME/.npm-global/bin" # Show the user the path
            echo "   To install global tools (repomix, etc.):"
            echo "   npm install -g repomix @anthropic-ai/claude-code @modelcontextprotocol/server-brave-search"

            # .env loading
            echo "🔑 Checking for .env file..."
            if [ -f ".env" ]; then
              echo "   Found .env, loading variables..."
              loaded_vars=$(grep -vE '^\s*(#|$)' .env)
              if [ -n "$loaded_vars" ]; then
                 # Loop is safer for potentially complex values than `export $(...)`
                 while IFS= read -r line || [ -n "$line" ]; do # Handle lines without newline at EOF
                    # Basic check to ensure it looks like VAR=VAL before exporting
                    if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*=.* ]]; then
                       export "$line"
                    fi
                 done <<< "$loaded_vars"
                 echo "   ✅ Variables potentially loaded from .env (verify)."
              else echo "   ℹ️ .env found, but no loadable variable lines."; fi
            else
              echo "   ⚠️ .env file not found."; if [ -f ".env.example" ]; then echo "   💡 Hint: Found '.env.example'. Copy/edit: cp .env.example .env"; fi
            fi

            # Final readiness message
            echo ""
            echo "✨ Montaigne AI/TTS flake environment is ready! ✨"
            echo ""
            echo "📌 Quick Start:"
            echo "   just setup"
            echo "   source $VENV_DIR/bin/activate"
            echo "   just run -- --help"
            echo ""
          '';
        };
      });
}
