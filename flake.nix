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
        # Configure nixpkgs
        pkgs = import nixpkgs {
          inherit system;
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
          uv
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
          packages = montaigneTools ++ nixPythonMlPackages; # REMOVED: ++ realtimePythonPackages
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
            unset SOURCE_DATE_EPOCH
            echo "👋 Entering Montaigne Dev Env (Nix managing Python core + PyTorch/CUDA)..."

            # --- Venv Setup ---
            # Use the python provided in `packages` which should be the correct one
            _NIX_PYTHON_INTERPRETER=$(command -v python)
            if ! command -v "$_NIX_PYTHON_INTERPRETER" &> /dev/null; then echo "❌ Fatal: Nix Python interpreter not found in PATH." && return 1; fi
            echo "🐍 Using Nix Python for venv base: $_NIX_PYTHON_INTERPRETER ($($_NIX_PYTHON_INTERPRETER --version))"
            _PROJECT_DIR="$(pwd)"; VENV_DIR="$_PROJECT_DIR/.venv"; export VIRTUAL_ENV="$VENV_DIR"; export PATH="$VENV_DIR/bin:$PATH"

            echo "   Resolved VIRTUAL_ENV='$VIRTUAL_ENV'"; echo "   Prepended venv bin to PATH."
            if [ ! -f "$VENV_DIR/bin/activate" ]; then
              echo "🐍 Creating Python virtual environment using uv in '$VENV_DIR'..."
              if ! uv venv "$VENV_DIR" --python "$_NIX_PYTHON_INTERPRETER"; then echo "❌ Fatal: Failed to create uv virtual environment." && return 1; fi
              echo "✅ Virtual environment created."
            else echo "🐍 Re-using existing virtual environment '$VENV_DIR'."; fi

            # --- Venv Activation ---
            if [ -f "$VENV_DIR/bin/activate" ]; then
               echo "🐍 Activating Python virtual environment..."; source "$VENV_DIR/bin/activate"; echo "   VIRTUAL_ENV is: $VIRTUAL_ENV"
               _VENV_PYTHON_PATH=$(command -v python); echo "   Python interpreter path (venv): $_VENV_PYTHON_PATH"; echo "   Python version (venv): $(python --version)"
               if ! [[ "$_VENV_PYTHON_PATH" == "$VENV_DIR/bin/python" ]]; then echo "⚠️ Warning: 'command -v python' found '$_VENV_PYTHON_PATH' not expected '$VENV_DIR/bin/python'."; fi
            else echo "❌ Fatal: Failed to find activate script in '$VENV_DIR/bin/activate'." && return 1; fi

            # --- uv Workspace Installation ---
            if command -v uv &> /dev/null; then
               echo "📦 Installing/Verifying workspace packages via uv..."
               # Install all workspace members defined in the root pyproject.toml
               # Explicitly use -e . to ensure editable installs for workspace members
               # This helps Python find the modules correctly via the generated entry points.
               if ! uv pip install --no-cache-dir -e .; then
                 echo "❌ Fatal: Failed to install workspace packages with uv into venv '$VENV_DIR'." && return 1
               fi

               # Add PortAudio library path to LD_LIBRARY_PATH for sounddevice (still needed at runtime)
               echo "🔊 Adding PortAudio to LD_LIBRARY_PATH for audio playback..."
               export LD_LIBRARY_PATH="${pkgs.portaudio}/lib''${LD_LIBRARY_PATH:+:''$LD_LIBRARY_PATH}"
               echo "   Current LD_LIBRARY_PATH includes:"
               echo "   - ${pkgs.portaudio}/lib"
               echo "   This enables runtime loading of libportaudio.so.2 by sounddevice"

               echo "✅ uv workspace installation complete."
            else
               echo "❌ Fatal: uv command not found. Cannot install workspace packages." && return 1
            fi
            # --- Sanity Checks ---
            echo "" && echo "=== Sanity Checks ==="
            # --- PyTorch/Torchaudio Check ---
            echo "🔍 Checking PyTorch & Torchaudio (managed by Nix, accessed via venv Python)..."
            python -c "import torch; print(f'---> Torch Version: {torch.__version__}'); print(f'---> CUDA Available: {torch.cuda.is_available()}'); print(f'---> Device Count: {torch.cuda.device_count()}')"

            # --- Docker Check ---
            echo "🐳 Checking Docker status..."
            if command -v docker &> /dev/null; then
              if timeout 5 docker info >/dev/null 2>&1; then
                 echo "✅ Docker daemon is running and accessible."
                 if timeout 5 docker info 2>/dev/null | grep -qE 'Runtimes:.* nvidia( |$)'; then echo "✅ NVIDIA Docker runtime detected in docker info."
                 elif command -v nvidia-container-runtime &>/dev/null || command -v nvidia-container-runtime-hook &>/dev/null ; then echo "ℹ️ NVIDIA container runtime binary found, but not listed in 'docker info Runtimes'."
                 else echo "⚠️ NVIDIA Docker runtime not detected."; fi
              else echo "⚠️ Docker daemon not running, not responsive within 5s, or permission error."; fi
            else echo "❌ Docker command not found \(is 'docker' included in 'packages'?\)."; fi

            # --- Host NVIDIA Driver Check ---
            echo "💻 Checking Host NVIDIA driver via nvidia-smi wrapper..."
            if command -v nvidia-smi &> /dev/null; then
              nvidia_smi_output=""; nvidia_smi_status=1
              if nvidia_smi_output=$(timeout 5 nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1); nvidia_smi_status=$?; then
                 if [ $nvidia_smi_status -eq 0 ] && [ -n "$nvidia_smi_output" ]; then echo "✅ nvidia-smi query successful. Host Driver Version: $nvidia_smi_output"
                 else
                   echo "   ℹ️ nvidia-smi query failed (Status: $nvidia_smi_status)/empty. Trying generic 'nvidia-smi'..."
                   if nvidia_smi_output=$(timeout 5 nvidia-smi 2>&1); nvidia_smi_status=$?; then
                      if [ $nvidia_smi_status -eq 0 ] && echo "$nvidia_smi_output" | grep -q "Driver Version:"; then echo "✅ nvidia-smi generic command successful. Host drivers okay."; echo "$nvidia_smi_output" | grep "Driver Version:" | sed 's/ *|//'
                      else echo "⚠️ nvidia-smi generic command issue (Status: $nvidia_smi_status). Output:"; echo "--- START ---"; echo "$nvidia_smi_output"; echo "--- END ---"; fi
                   else echo "⚠️ nvidia-smi generic command failed/timed out (Status: $nvidia_smi_status). Output:"; echo "--- START ---"; echo "$nvidia_smi_output"; echo "--- END ---"; fi
                 fi
              else echo "⚠️ Error running/capturing nvidia-smi status."; fi
            else echo "❌ nvidia-smi command (wrapper) not found in PATH."; fi

            # --- Final Message ---
            echo "================================"; echo ""
            echo "✅ Montaigne environment ready!"
            # Use the nixpkgsRev variable defined in the Nix 'let' block
            # This uses Nix interpolation.
            echo "   Nix manages: Python ${python.version}, PyTorch+CUDA, Torchaudio, Core libs (from Nixpkgs commit ${nixpkgsRev})"
            echo "   uv manages other Python packages in: $VENV_DIR" # Use shell variable $VENV_DIR
            echo ""
            echo "📌 Quick Start:"
            echo "   just --list          # Show available commands"
            echo "   just run -- --help   # Run the Montaigne CLI"
            echo "   python --version     # Verify venv Python ($(python --version))"
            echo "   which python         # Verify venv Python path ($(command -v python))"
            echo "   uv pip list          # List venv packages"
            echo ""
            # --- Final LD_LIBRARY_PATH Check ---
            echo "🔧 Final LD_LIBRARY_PATH value:"
            echo "   $LD_LIBRARY_PATH"
            echo "================================"; echo ""
          ''; # End of shellHook definition
        }; # End of mkShell definition

      } # End of the attribute set returned by 'let...in'.
    ); # End of eachDefaultSystem function call
} # End of flake definition
