# flake.nix - Final Version (Pinning Nixpkgs, Corrected Rev Info Comment)
{
  description = "Development environment for Montaigne (Python TTS/STT) with reliable CUDA support";

  inputs = {
    # Pin nixpkgs to a specific commit known to have compatible CUDA/PyTorch builds.
    # You MUST find a working commit hash from:
    # https://github.com/NixOS/nixpkgs/commits/nixos-unstable/
    # Replace the placeholder hash below with a recent, valid commit SHA.
    nixpkgs.url = "github:NixOS/nixpkgs/f771eb401a46846c1aebd20552521b233dd7e18b"; # <-- EDIT THIS LINE
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # --- Define the overlay to override uv source to 0.7.0 ---
        uv-overlay = final: prev: {
          uv = prev.uv.overrideAttrs (oldAttrs:
            let
              # Define the source in a 'let' binding for clear scope
              drv_src = final.fetchFromGitHub {
                owner = "astral-sh";
                repo = "uv";
                rev = "0.7.0"; # <-- Use the tag/release name 0.7.0
                # Verify this source hash corresponds to the 0.7.0 tag/release
                hash = "sha256-D/3YqhIjXhvH7hn/dmJ2Xmf1riGjVc9jqbqVJSD5EyA="; # <-- Double-check this Source hash
              };
            in
            { # Start the attribute set returned by overrideAttrs
              version = "0.7.0"; # <-- Ensure version is 0.7.0
              # Use the let-bound variable for the derivation's source
              src = drv_src;

              # Use fetchCargoVendor and the sha256 attribute
              # Use fetchCargoVendor and the HASH attribute this time
              cargoDeps = prev.rustPlatform.fetchCargoVendor {
                # Explicitly pass the let-bound variable here
                src = drv_src;
                # !! IMPORTANT STEP REMAINS !!
                # 1. Set this to empty string: hash = "";
                # 2. Run `nix develop` or `just nix_shell`. Note the failure and the 'got: sha256-...' hash.
                # 3. Paste the correct hash string (including the "sha256-" prefix) here.
                hash = ""; # <-- Set to "" first, then paste correct value
              };
            } # End the attribute set returned by overrideAttrs
          ); # End overrideAttrs call
        };

        # --- Apply the overlay ---
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ uv-overlay ]; # Apply the source overlay
          config = {
            allowUnfree = true; # Required for NVIDIA CUDA components
            cudaSupport = true; # Enable CUDA support globally for pkgs
          };
        };

        # --- Get Nixpkgs Revision Info ---
        # Access rev directly from the input flake object
        nixpkgsRev = nixpkgs.rev or "unknown"; # Use rev if available

        # Define Python version
        python = pkgs.python311;

        # Select CUDA packages (matching the pinned nixpkgs)
        cudaPkgs = pkgs.cudaPackages_12_1; # Adjust if your pinned nixpkgs uses a different default
        cudatoolkit = cudaPkgs.cudatoolkit;
        cudnn = cudaPkgs.cudnn;

        # --- Python Packages Managed by Nix ---
        nixPythonMlPackages = with python.pkgs; [
          torchWithCuda
          torchaudio
          numpy # Add NumPy
          pandas # Add Pandas
          scipy # Add SciPy
          soundfile # Add soundfile (links libsndfile)
          rapidfuzz # Add rapidfuzz (C++ extensions)
          librosa # Add librosa (audio analysis, C extensions)
          numba # Add numba (JIT compiler, C extensions)
          transformers # Add transformers for Bark
          accelerate # Add accelerate for HF/Bark
          # uv is now handled by the overlay and added directly to packages below
        ];

        # --- Runtime Libraries ---
        runtimeLibs = with pkgs; [
          # Core C/C++ libs
          stdenv.cc.cc.lib
          gcc-unwrapped.lib
          # Application runtime libs
          ffmpeg
          libsndfile
          alsa-lib
          libGL
          openssl
          ncurses5
          portaudio # Added for sounddevice runtime loading
          fftw # Added for librosa/noisereduce (Use 'fftw' instead of 'libfftw')
        ];
        runtimeLibPath = pkgs.lib.makeLibraryPath runtimeLibs;

        # --- Additional Python Packages for Real-time TTS ---
        # REMOVED: realtimePythonPackages definition. These will be installed via uv in shellHook.

        # --- General Development Tools ---
        montaigneTools = with pkgs; [
          cachix
          bashInteractive
          coreutils
          git
          jq
          just
          repomix # Added repomix
          ripgrep
          fd
          curl
          wget
          repomix
          gcc
          pkg-config # Needed for building some Python packages
          gnumake
          python
          #uv
          ruff
          nodejs_22
          corepack_22
          docker
          docker-compose
          docker-credential-helpers
          hadolint # Added hadolint
          # nvidia-smi wrapper
          (pkgs.runCommand "nvidia-smi-wrapper" { } ''
            mkdir -p $out/bin ; _host_nvidia_smi=""
            if [ -e /run/opengl-driver/bin/nvidia-smi ]; then _host_nvidia_smi="/run/opengl-driver/bin/nvidia-smi";
            elif [ -e /run/opengl-driver/lib/nvidia-smi ]; then _host_nvidia_smi="/run/opengl-driver/lib/nvidia-smi";
            elif command -v nvidia-smi &>/dev/null ; then _host_nvidia_smi=$(command -v nvidia-smi); fi
            if [ -n "$_host_nvidia_smi" ] && [ -x "$_host_nvidia_smi" ] ; then
              ln -s "$_host_nvidia_smi" $out/bin/nvidia-smi;
            else
              echo '#!/bin/sh' > $out/bin/nvidia-smi
              echo 'echo "nvidia-smi wrapper: Host nvidia-smi not found or not executable."' >> $out/bin/nvidia-smi
              echo 'exit 1' >> $out/bin/nvidia-smi
              chmod +x $out/bin/nvidia-smi
            fi
          '')
          # Utilities
          gawk
          gnugrep
          gnused
          which
          procps
          util-linux
        ];

        # --- Compile-time Build Inputs ---
        devBuildInputs = with pkgs; [
          # System libraries needed for compiling Python extensions
          pkg-config
          cudatoolkit
          cudnn
          (ffmpeg.dev or ffmpeg)
          libsndfile.dev
          alsa-lib.dev
          libGL.dev
          openssl.dev
          ncurses5.dev
          pkgs.portaudio
          pkgs.fftw.dev # Added for librosa/noisereduce (Use 'fftw' instead of 'libfftw')
        ];

      in
      {
        # --- Define the Development Shell ---
        devShells.default = pkgs.mkShell {
          name = "montaigne-dev-env-nix-torch";
          packages = montaigneTools ++ nixPythonMlPackages ++ [ pkgs.uv ]; # Add the overridden uv here
          # buildInputs are implicitly added to PATH and include .dev outputs
          # Needed for compiling non-Nix Python packages if they require these libs.
          buildInputs = devBuildInputs;

          # --- Environment Variables ---
          env = {
            # These might still be useful for tools *other* than PyTorch's runtime linking
            CUDA_HOME = "${cudatoolkit}";
            CUDA_PATH = "${cudatoolkit}";
            # Let torchWithCuda's dependencies primarily manage runtime linking.
            # Set LD_LIBRARY_PATH to our specific runtime libs. mkShell prepends buildInputs libs automatically.
            LD_LIBRARY_PATH = runtimeLibPath;
            # Setup Venv path - shellHook will handle creation/activation
            VIRTUAL_ENV = "$PWD/.venv"; # Standard venv location
            PATH = "$PWD/.venv/bin:${pkgs.lib.makeBinPath montaigneTools}:${pkgs.lib.getBin pkgs.stdenv.cc}/bin"; # Prepend venv bin in hook, add C compiler bin path
            UV_NATIVE_TLS = "1";
            # Simplify NIX_CFLAGS/LDFLAGS - rely on buildInputs and pkg-config more
            # Keep essential ones if known to be required by specific non-Nix packages
            NIX_CFLAGS_COMPILE = toString ([
              "-I${pkgs.lib.getDev pkgs.openssl}/include"
              "-I${pkgs.lib.getDev pkgs.libsndfile}/include"
            ] ++ pkgs.lib.optionals (pkgs.libGL.dev != null) [ "-I${pkgs.lib.getDev pkgs.libGL}/include" ]);
            NIX_LDFLAGS = toString ([
              "-L${pkgs.lib.getLib pkgs.openssl}/lib"
              "-L${pkgs.lib.getLib pkgs.libsndfile}/lib"
            ] ++ pkgs.lib.optionals (pkgs.libGL.out != null) [ "-L${pkgs.lib.getLib pkgs.libGL}/lib" ]);
            DOCKER_BUILDKIT = "1";
            COMPOSE_DOCKER_CLI_BUILD = "1";
            PKG_CONFIG_PATH = "${pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" devBuildInputs}";
          };

          # --- Shell Hook ---
          shellHook = ''
            echo "👋 Entering Montaigne Dev Env (Nix managing Python core + PyTorch/CUDA)..."
            PYTHON_BIN_NIX=$(command -v python) # Get nix python path

            # --- venv setup ---
            VENV_DIR=".venv"
            # Ensure Nix Python path is captured
            if ! PYTHON_BIN_NIX=$(command -v python); then
                echo "❌ Fatal: Could not determine Nix Python path using 'command -v python'."
                exit 1
            fi
            # Use dirname for robustness instead of shell expansion
            PYTHON_BIN_DIR_NIX=$(dirname "$PYTHON_BIN_NIX")

            # Check if venv exists and is based on the correct Nix Python
            # Use printf for safer pattern generation and handle potential spaces in paths
            EXPECTED_HOME_LINE=$(printf 'home = %s' "$PYTHON_BIN_DIR_NIX")
            if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/pyvenv.cfg" ] && \
               grep -q -F -x "$EXPECTED_HOME_LINE" "$VENV_DIR/pyvenv.cfg"; then
                echo "🐍 Re-using existing virtual environment '$VENV_DIR'."
            else
                echo "🐍 Creating new virtual environment '$VENV_DIR' based on Nix Python ($PYTHON_BIN_NIX)..."
                rm -rf "$VENV_DIR" # Remove old venv if incompatible
                # Create venv using the Python from Nix env
                $PYTHON_BIN_NIX -m venv "$VENV_DIR" || { echo "❌ Failed to create venv."; exit 1; }
                echo "🐍 Virtual environment created."
                # Activate temporarily just to run the sync/install
                source "$VENV_DIR/bin/activate"
                echo "📦 Initial sync/install of workspace packages into new venv via uv..."
                # Use the 'uv' from Nix path (which is the correct one)
                uv pip sync uv.lock && \
                uv pip install -e ./packages/montaigne -e ./packages/aider_analytics --no-deps || \
                  { echo "❌ Fatal: Failed initial workspace package install into venv '$VENV_DIR'."; deactivate; exit 1; }
                deactivate
                echo "✅ Initial package installation complete."
            fi

            # --- Activation ---
            # Standard venv activation for the shell session
            if [ -f "$VENV_DIR/bin/activate" ]; then
                source "$VENV_DIR/bin/activate"
                echo "🐍 Python virtual environment activated."
                echo "   VIRTUAL_ENV is: $VIRTUAL_ENV"
                echo "   Python interpreter path (venv): $(command -v python)"
                echo "   Python version (venv): $(python --version)"
            else
                echo "⚠️ Failed to activate venv '$VENV_DIR'."
            fi

            export PYTHONDONTWRITEBYTECODE=1
            export PYTHONUNBUFFERED=1
            # Add any other exports you need
          ''; # End of shellHook definition
        }; # End of mkShell definition

      } # End of the attribute set returned by 'let...in'.
    ); # End of eachDefaultSystem function call
} # End of flake definition
