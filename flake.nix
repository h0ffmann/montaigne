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
            cudaSupport = true; # Uncommented to enable CUDA support in nixpkgs
          };
        };

        # Get CUDA toolkit for PyTorch 2.3.1 (which expects CUDA 12.1)
        cuda_toolkit = pkgs.cudaPackages_12_1.cudatoolkit;
        cudnn = pkgs.cudaPackages_12_1.cudnn;

        # Define required system libraries
        requiredSysLibs = with pkgs; [
          cuda_toolkit
          cudnn
          linuxPackages.nvidia_x11
          stdenv.cc.cc.lib
          zlib
          ncurses5
        ];

        # Create library path for LD_LIBRARY_PATH
        requiredLibPath = pkgs.lib.makeLibraryPath requiredSysLibs;

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
          # python311Packages.venv # Removed - venv is a built-in module

          # System libraries for audio and ML
          ffmpeg
          libsndfile
          alsa-lib
          libGL
          stdenv.cc.cc.lib

          # Node.js tools
          nodejs_22
          corepack_22

          # Docker and container tools
          docker
          docker-compose
          docker-credential-helpers

          # Other tools
          uv
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

          # Add explicit environment variables for CUDA
          env = {
            CUDA_HOME = "${cuda_toolkit}";
            CUDNN_HOME = "${cudnn}";
            CUDA_PATH = "${cuda_toolkit}";
            LD_LIBRARY_PATH = "${requiredLibPath}";
            EXTRA_LDFLAGS = "-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib";
            EXTRA_CCFLAGS = "-I/usr/include";
          };

          shellHook = ''
            # Welcome message
            echo "👋 Entering Montaigne Development Environment..."

            # Make sure Python is in PATH
            export PATH="${pkgs.python311}/bin:$PATH"

            # Set up virtualenv
            VENV_DIR=".venv"
            if [ ! -d "$VENV_DIR" ]; then
              echo "Creating Python virtual environment in $VENV_DIR..."
              python -m venv $VENV_DIR
            fi

            # Activate virtualenv
            source $VENV_DIR/bin/activate

            # Install dependencies in a more robust way
            if [ -f "$VENV_DIR/bin/pip" ]; then
              echo "Installing project dependencies..."
              $VENV_DIR/bin/pip install --upgrade pip
              $VENV_DIR/bin/pip install TTS==0.22.0 openai-whisper==20240930
              $VENV_DIR/bin/pip install -e .
            else
              echo "❌ pip not found in virtualenv"
            fi

            # Set library path for C++ libraries
            export LD_LIBRARY_PATH="${pkgs.gcc-unwrapped.lib}/lib:${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"

            echo ""
            echo "📌 Quick Start:"
            echo "   just run -- --help"
            echo ""
          '';
        };
      });
}
