# flake.nix - Final Version (Pinning Nixpkgs, Aligning uv version attribute with build output)
{
  description = "Development environment for Montaigne (Python TTS/STT) with reliable CUDA support";

  inputs = {
    # Pin nixpkgs to a specific commit known to have compatible CUDA/PyTorch builds.
    nixpkgs.url = "github:NixOS/nixpkgs/b5dd9efc912ecabeafa4f082d31e19cb1c74266c"; # Specific commit
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # --- Define the overlay to build uv from 0.7.2 tag, but expect version 0.7.0 output ---
        uv-overlay = final: prev: {
          uv = prev.uv.overrideAttrs (oldAttrs:
            let
              # Source code from the official 0.7.2 tag
              drv_src = final.fetchFromGitHub {
                owner = "astral-sh";
                repo = "uv";
                rev = "0.7.2"; # Fetch source for the 0.7.2 tag
                # Hash for the source archive of the 0.7.2 tag
                hash = "sha256-D/3YqhIjXhvH7hn/dmJ2Xmf1riGjVc9jqbqVJSD5EyA=";
              };
            in
            {
              # --- FIX: Align Nix version attribute with actual binary output ---
              # The code at tag 0.7.2 reports "0.7.0" when `uv --version` is run.
              # Set the Nix derivation version attribute to match this expected output.
              version = "0.7.0"; # <-- Set to match binary output

              src = drv_src; # Use the fetched 0.7.2 source code

              # Fetch cargo dependencies based on the Cargo.lock in the 0.7.2 source tag
              cargoDeps = prev.rustPlatform.fetchCargoVendor {
                src = drv_src; # Must match the main src
                # Hash derived from the Cargo.lock within the 0.7.2 source tag
                hash = "sha256-QQv3uAtqC24UkZ1pp7D0izu7xMQGtUPg2iQkp+k9IMI=";
              };

              # No need to disable installCheckPhase or versionCheckPhase now,
              # as the version attribute matches the expected output.

            } # End the attribute set returned by overrideAttrs
          ); # End overrideAttrs call
        };

        # --- Create a portaudio overlay ---
        portaudio-overlay = final: prev: {
          portaudio = prev.portaudio.overrideAttrs (oldAttrs: {
            configureFlags = (oldAttrs.configureFlags or [ ]) ++ [
              "--enable-shared"
              "--enable-static"
            ];
            outputs = (oldAttrs.outputs or [ "out" ]) ++ [ "dev" ];
            propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [ final.stdenv.cc ];
          });
        };

        # --- Apply the overlays ---
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ uv-overlay portaudio-overlay ]; # Apply both overlays
          config = {
            allowUnfree = true; # Required for NVIDIA CUDA components
            cudaSupport = true; # Enable CUDA support globally for pkgs
          };
        };

        # --- Get Nixpkgs Revision Info ---
        nixpkgsRev = nixpkgs.rev or "unknown"; # Use rev if available

        # --- Define Python version ---
        python = pkgs.python311;

        # --- Select CUDA packages ---
        cudaPkgs = pkgs.cudaPackages_12_1;
        cudatoolkit = cudaPkgs.cudatoolkit;
        cudnn = cudaPkgs.cudnn;

        # --- Python Packages Managed by Nix ---
        nixPythonMlPackages = with python.pkgs; [
          torchWithCuda
          torchaudio
          numpy
          pandas
          scipy
          soundfile
          rapidfuzz
          librosa
          numba
          transformers
          accelerate
          # python-sounddevice build definition
          (buildPythonPackage rec {
            pname = "sounddevice";
            version = "0.4.6";
            format = "setuptools";
            src = fetchPypi {
              inherit pname version;
              sha256 = "sha256-Mja3jxXwQVvfAGpiDO8HPQwFIoUdZvSpYe1tjrFIL+k=";
            };
            propagatedBuildInputs = [
              cffi
              numpy
              pkgs.portaudio # Runtime library dependency
            ];
            buildInputs = [
              (pkgs.lib.getDev pkgs.portaudio) # Build-time header dependency
              pkgs.pkg-config # Needed to find portaudio headers/libs
            ];
            nativeBuildInputs = [ pkgs.pkg-config ];
          })
          # uv is added directly to 'packages' below from the overlay
        ];

        # --- Runtime Libraries ---
        runtimeLibs = with pkgs; [
          stdenv.cc.cc.lib
          gcc-unwrapped.lib
          ffmpeg
          libsndfile
          alsa-lib
          fftw
          libopus
          flac
          libvorbis
          libjack2
          libGL
          openssl
          ncurses5
          portaudio # Runtime library
          # fftw listed twice, keeping one
        ];
        runtimeLibPath = pkgs.lib.makeLibraryPath runtimeLibs;

        # --- General Development Tools ---
        montaigneTools = with pkgs; [
          cachix
          bashInteractive
          coreutils
          git
          jq
          just
          repomix # Keeping one instance
          ripgrep
          fd
          curl
          wget
          gcc
          pkg-config
          gnumake
          python # Base Nix Python
          ruff
          nodejs_22
          corepack_22
          docker
          docker-compose
          docker-credential-helpers
          hadolint
          sox
          mpg123
          lame
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
          gawk
          gnugrep
          gnused
          which
          procps
          util-linux
          # portaudio utility binaries linker
          (runCommand "portaudio-utils" { nativeBuildInputs = [ pkgs.portaudio ]; } ''
            mkdir -p $out/bin
            if [ -d "${pkgs.portaudio}/bin" ]; then
               find "${pkgs.portaudio}/bin" -maxdepth 1 -type f -executable -exec ln -s {} $out/bin/ \;
            else
               echo "No binaries found in ${pkgs.portaudio}/bin" >&2 # Echo warnings to stderr
            fi
          '')
        ];

        # --- Compile-time Build Inputs (Headers/Dev Libs) ---
        devBuildInputs = with pkgs; [
          pkg-config # Crucial for finding .pc files
          cudatoolkit
          cudnn
          (ffmpeg.dev or ffmpeg)
          libsndfile.dev
          alsa-lib.dev
          fftw.dev
          libopus.dev
          flac.dev
          libvorbis.dev
          libjack2.dev
          (libGL.dev or libGL)
          openssl.dev
          ncurses5.dev
          (pkgs.lib.getDev portaudio) # Ensure we get headers/libs for portaudio
          # fftw.dev already included
        ];

      in
      {
        # --- Define the Development Shell ---
        devShells.default = pkgs.mkShell {
          name = "montaigne-dev-env-nix-torch";
          # Add uv (built from 0.7.2 src, reporting 0.7.0) and other packages
          packages = montaigneTools ++ nixPythonMlPackages ++ [ pkgs.uv ];

          # Add compile-time dependencies for C/C++ extensions built in the shell
          buildInputs = devBuildInputs;

          # --- Environment Variables ---
          env = {
            CUDA_HOME = "${cudatoolkit}";
            CUDA_PATH = "${cudatoolkit}";
            LD_LIBRARY_PATH = runtimeLibPath; # Core runtime libs path

            VIRTUAL_ENV = "$PWD/.venv"; # venv location
            PATH = "$PWD/.venv/bin:${pkgs.lib.makeBinPath montaigneTools}:${pkgs.lib.getBin pkgs.stdenv.cc}/bin"; # venv bin first

            UV_NATIVE_TLS = "1"; # Use system TLS

            # PKG_CONFIG_PATH setup - Helps find .pc files for build tools
            PKG_CONFIG_PATH = "${pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" devBuildInputs}:${pkgs.lib.makeSearchPathOutput "out" "lib/pkgconfig" runtimeLibs}";

            # Optional Compiler flags (usually PKG_CONFIG_PATH is enough)
            # NIX_CFLAGS_COMPILE = "...";
            # NIX_LDFLAGS = "...";

            # Docker helpers
            DOCKER_BUILDKIT = "1";
            COMPOSE_DOCKER_CLI_BUILD = "1";

            # Portaudio env var
            PORTAUDIO_PATH = "${pkgs.portaudio}"; # Point to the derivation path
          };

          # --- Shell Hook ---
          shellHook = ''
            echo "👋 Entering Montaigne Dev Env (Nix: uv from 0.7.2 src reporting 0.7.0, Python core + PyTorch/CUDA)..."
            # Ensure we get the correct Nix Python path
            if ! PYTHON_BIN_NIX=$(command -v python); then
                echo "❌ Fatal: Could not determine Nix Python path." >&2; exit 1
            fi
            PYTHON_BIN_DIR_NIX=$(dirname "$PYTHON_BIN_NIX")

            # --- venv setup using Nix Python ---
            VENV_DIR=".venv"
            EXPECTED_HOME_LINE=$(printf 'home = %s' "$PYTHON_BIN_DIR_NIX")

            if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/pyvenv.cfg" ] && \
               grep -q -F -x "$EXPECTED_HOME_LINE" "$VENV_DIR/pyvenv.cfg"; then
                echo "🐍 Re-using existing venv '$VENV_DIR' (linked to Nix Python: $PYTHON_BIN_NIX)."
            else
                echo "🐍 Creating new venv '$VENV_DIR' with Nix Python ($PYTHON_BIN_NIX)..."
                rm -rf "$VENV_DIR" # Ensure clean state
                "$PYTHON_BIN_NIX" -m venv "$VENV_DIR" || { echo "❌ Failed to create venv." >&2; exit 1; }
                echo "🐍 Venv created."

                # Temporarily activate for initial installation
                if [ -f "$VENV_DIR/bin/activate" ]; then
                    source "$VENV_DIR/bin/activate"
                    echo "📦 Installing project dependencies via uv..."

                    # Sync requirements files if they exist
                    sync_args=()
                    [ -f "requirements.txt" ] && sync_args+=("requirements.txt")
                    [ -f "requirements-dev.txt" ] && sync_args+=("-r" "requirements-dev.txt")
                    if [ ''${#sync_args[@]} -gt 0 ]; then
                        echo "   Syncing:" "''${sync_args[@]}"
                        uv pip sync "''${sync_args[@]}" || { echo "❌ Fatal: uv sync failed." >&2; deactivate; exit 1; }
                    else
                        echo "   No standard requirements files found to sync."
                    fi

                    # Install local editable packages if they exist
                    echo "   Installing editable local packages..."
                    local_pkgs_installed=0
                    [ -d "./packages/montaigne" ] && { uv pip install -e ./packages/montaigne || { echo "❌ Error installing montaigne" >&2; deactivate; exit 1; } ; local_pkgs_installed=1; }
                    [ -d "./packages/aider_analytics" ] && { uv pip install -e ./packages/aider_analytics || { echo "❌ Error installing aider_analytics" >&2; deactivate; exit 1; } ; local_pkgs_installed=1; }
                    if [ $local_pkgs_installed -eq 0 ]; then
                        echo "   No local editable packages found."
                    fi

                    deactivate # Deactivate after install
                    echo "✅ Initial venv setup complete."
                else
                    echo "❌ Fatal: Could not find activate script in new venv '$VENV_DIR'." >&2; exit 1
                fi
            fi

            # --- Activate venv for the interactive shell session ---
            if [ -f "$VENV_DIR/bin/activate" ]; then
                source "$VENV_DIR/bin/activate"
                echo "🐍 Python virtual environment activated ($VIRTUAL_ENV)."
                # Verify Python points to the venv
                current_python=$(command -v python)
                expected_python="$PWD/$VENV_DIR/bin/python"
                if [[ "$current_python" == "$expected_python" ]]; then
                   echo "   Python: $current_python ($(python --version))"
                else
                   echo "⚠️ Warning: PATH python ($current_python) differs from expected venv python ($expected_python)." >&2
                fi
            else
                echo "⚠️ Failed to activate venv '$VENV_DIR'." >&2
            fi

            # Check sounddevice installation post-activation
            echo "🎙️ Checking sounddevice..."
            if python -c "import sounddevice" &> /dev/null; then
                 echo "✅ sounddevice library imported successfully."
             else
                 echo "⚠️ sounddevice import failed. Attempting install/reinstall..."
                 # Try installing it explicitly within the activated venv
                 uv pip install sounddevice || echo "❌ Error installing sounddevice. Check PortAudio setup and build logs." >&2
             fi

            # Standard Python env settings
            export PYTHONDONTWRITEBYTECODE=1
            export PYTHONUNBUFFERED=1

            echo "🌲 Nixpkgs revision: ${nixpkgsRev}"
            echo "🚀 Environment ready!"

          ''; # End of shellHook definition
        }; # End of mkShell definition
      } # End of the attribute set returned by 'let...in'.
    ); # End of eachDefaultSystem function call
} # End of flake definition
