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
            # cudaSupport = true; https://discourse.nixos.org/t/pytorch-with-cuda-support/51189/8
          };
        };

        # Get CUDA toolkit for PyTorch 2.3.1 (which expects CUDA 12.1)
        cuda_toolkit = pkgs.cudaPackages_12_1.cudatoolkit;

        montaignePkgs = with pkgs; [
          # Basic tools
          cachix
          bashInteractive
          coreutils
          git
          jq
          just
          ripgrep
          fd
          curl
          wget

          # Build essentials
          openssl
          pkg-config
          gcc
          gnumake
          gcc-unwrapped

          # Python and package management
          python311
          python311Packages.pip
          python311Packages.setuptools
          python311Packages.wheel
          python311Packages.venv

          # System libraries for audio and ML
          ffmpeg
          libsndfile
          alsa-lib
          libGL
          stdenv.cc.cc.lib

          # Node.js tools
          nodejs_22
          corepack_22

          # Other tools from your existing list
          uv  # Keep uv
        ];

        # Nix might handle library paths better now for its own packages.
        # Commenting out explicit LD_LIBRARY_PATH setup for now.
        # requiredSysLibs = with pkgs; [
        #   ffmpeg.lib # Use .lib outputs for library paths
        #   libsndfile.lib
        #   alsa-lib
        #   libGL
        #   stdenv.cc.cc.lib
        #   # CUDA libs likely handled by pytorchWithCuda dependency
        #   # cudaPackages_12_1.cudnn 
        # ];
        # requiredLibPath = pkgs.lib.makeLibraryPath requiredSysLibs;

      in
      {
        devShells.default = pkgs.mkShell {
          name = "montaigne-dev-env";
          packages = montaignePkgs;

          # Remove explicit LD_LIBRARY_PATH and CUDA_HOME for now, let Nix manage it
          # env = {
          #   LD_LIBRARY_PATH = requiredLibPath;
          #   NPM_CONFIG_PREFIX = "$HOME/.npm-global";
          #   CUDA_HOME = "${cuda_toolkit}";
          # };

          shellHook = ''
            # Welcome message
            echo "👋 Entering Focused Montaigne Development Environment (Flake)..."

            # --- Check Nix Python/PyTorch CUDA Status ---
            echo "🚀 Checking Nix Python/PyTorch CUDA status:"
            python -c "import torch; print(f'Nix PyTorch: {torch.__version__}, CUDA Available: {torch.cuda.is_available()}, Device Count: {torch.cuda.device_count()}')" || echo 'Python/Torch check failed in shellHook'

            # Ensure user's local bin and npm global bin are in PATH
            export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

            # Ensure npm global bin dir exists
            mkdir -p "$HOME/.npm-global/bin"

            set -o pipefail

            # Check optional Docker/Podman status
            if command -v docker &>/dev/null; then
                if ! docker ps > /dev/null 2>&1; then echo "⚠️ Warning: Cannot connect to Docker daemon."; fi
            elif command -v podman &>/dev/null; then echo "ℹ️ Podman available."; else echo "⚠️ Warning: Docker/Podman not found."; fi

            # Create a .venv directory if it doesn't exist
            if [ ! -d ".venv" ]; then
              echo "Creating Python virtual environment..."
              ${pkgs.python311}/bin/python -m venv .venv
            fi

            # Activate the venv
            source .venv/bin/activate

            # Ensure pip is up to date
            pip install --upgrade pip

            # Install TTS and the local package
            echo "Installing TTS and dependencies (this may take a while)..."
            pip install TTS==0.22.0 --no-deps
            pip install -e .

            # Set library path for C++ libraries
            export LD_LIBRARY_PATH=${pkgs.gcc-unwrapped.lib}/lib:${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH

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
            echo "   just run -- --help"
            echo ""
          '';
        };
      });
}
