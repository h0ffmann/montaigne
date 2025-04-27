# flake.nix - Final Version (Pinning Nixpkgs for stability)
{
  description = "Development environment for Montaigne (Python TTS/STT) with reliable CUDA support";

  inputs = {
    # Pin nixpkgs to a specific commit known to have compatible CUDA/PyTorch builds.
    # You might need to find a more recent working commit from:
    # https://github.com/NixOS/nixpkgs/commits/nixos-unstable/
    # Example commit from late Sept 2024 (adjust as needed):
    nixpkgs.url = "github:NixOS/nixpkgs/9a41dd7b72e35457f5b4601716516f4c164e41c4"; # Pinned!
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

        # Define Python version
        python = pkgs.python311;

        # Select CUDA packages (matching the pinned nixpkgs)
        cudaPkgs = pkgs.cudaPackages_12_1;
        cudatoolkit = cudaPkgs.cudatoolkit;
        cudnn = cudaPkgs.cudnn;

        # --- Python Packages Managed by Nix ---
        nixPythonMlPackages = with python.pkgs; [
          torchWithCuda # Built by Nix with cudaSupport=true awareness
          torchaudio
        ];

        # --- Runtime Libraries ---
        # Packages whose shared libraries might be needed at runtime
        runtimeLibs = with pkgs; [
          stdenv.cc.cc.lib # Standard C++ library
          gcc-unwrapped.lib # GCC support libraries
          cudatoolkit # CUDA runtime libraries
          cudnn # cuDNN runtime libraries
          ffmpeg
          libsndfile
          alsa-lib
          libGL
          openssl
          zlib
          ncurses5
        ];

        # Calculate the Library Path for runtime
        runtimeLibPath = pkgs.lib.makeLibraryPath runtimeLibs;

        # --- General Development Tools ---
        montaigneTools = with pkgs; [
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
          repomix
          pkg-config
          gcc
          gnumake
          python
          uv
          nodejs_22
          corepack_22
          docker
          docker-compose
          docker-credential-helpers
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
          # Utilities (ldd removed, provided by glibc/stdenv)
          gawk
          gnugrep
          gnused
          which
          procps
          util-linux
        ];

        # --- Compile-time Build Inputs ---
        # Packages needed for compiling software *inside* the shell
        devBuildInputs = with pkgs; [
          stdenv.cc.cc
          pkg-config
          cudatoolkit # Provide CUDA toolkit for linking/headers
          cudnn # Provide cuDNN for linking/headers
          # Use .dev where available/common, otherwise Nix tries to find dev files in main pkg
          (ffmpeg.dev or ffmpeg) # Example: Use ffmpeg.dev if it exists, else ffmpeg
          libsndfile.dev
          alsa-lib.dev
          libGL.dev
          openssl.dev
          zlib.dev
          ncurses5.dev
        ];

      in
      {
        # --- Define the Development Shell ---
        devShells.default = pkgs.mkShell {
          name = "montaigne-dev-env-nix-torch";

          packages = montaigneTools ++ nixPythonMlPackages;
          buildInputs = devBuildInputs;

          # --- Environment Variables ---
          env = {
            CUDA_HOME = "${cudatoolkit}";
            CUDA_PATH = "${cudatoolkit}";
            LD_LIBRARY_PATH = runtimeLibPath;
            VIRTUAL_ENV = "$PWD/.venv"; # Updated in shellHook
            PATH = "$PWD/.venv/bin:${pkgs.lib.makeBinPath montaigneTools}"; # Updated in shellHook
            UV_NATIVE_TLS = "1";

            # Use lib.getDev to safely find header paths
            NIX_CFLAGS_COMPILE = toString (pkgs.lib.optionals pkgs.stdenv.isLinux ([
              "-I${pkgs.lib.getDev pkgs.openssl}/include"
              "-I${pkgs.lib.getDev pkgs.zlib}/include"
              "-I${pkgs.lib.getDev pkgs.libsndfile}/include"
              "-I${pkgs.lib.getDev cudatoolkit}/include"
              "-I${pkgs.lib.getDev cudnn}/include"
            ] ++ pkgs.lib.optionals (pkgs.libGL.dev != null) [ "-I${pkgs.lib.getDev pkgs.libGL}/include" ]
            ++ pkgs.lib.optionals (pkgs.alsa-lib.dev != null) [ "-I${pkgs.lib.getDev pkgs.alsa-lib}/include" ]
            ));

            # Use lib.getLib to safely find library paths for linking
            # NOTE: Removed explicit -L path for cuda_compat, relying on Nix's cudaSupport wrappers
            NIX_LDFLAGS = toString (pkgs.lib.optionals pkgs.stdenv.isLinux ([
              "-L${pkgs.lib.getLib pkgs.openssl}/lib"
              "-L${pkgs.lib.getLib pkgs.zlib}/lib"
              "-L${pkgs.lib.getLib pkgs.libsndfile}/lib"
              "-L${pkgs.lib.getLib cudatoolkit}/lib" # Link against CUDA runtime
              "-L${pkgs.lib.getLib cudnn}/lib" # Link against cuDNN
              # Standard C/C++ library paths
              "-L${pkgs.stdenv.cc.cc.lib}/lib"
              "-L${pkgs.gcc-unwrapped.lib}/lib"
            ] ++ pkgs.lib.optionals (pkgs.libGL.out != null) [ "-L${pkgs.lib.getLib pkgs.libGL}/lib" ]
            ++ pkgs.lib.optionals (pkgs.alsa-lib.out != null) [ "-L${pkgs.lib.getLib pkgs.alsa-lib}/lib" ]
            ));

            EXTRA_LDFLAGS = "-L${pkgs.stdenv.cc.cc.lib}/lib -L${pkgs.gcc-unwrapped.lib}/lib";
            EXTRA_CPPFLAGS = "-I${pkgs.stdenv.cc.cc.lib}/include";
            DOCKER_BUILDKIT = "1";
            COMPOSE_DOCKER_CLI_BUILD = "1";
            PKG_CONFIG_PATH = "${pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" devBuildInputs}";
          };

          # --- Shell Hook ---
          shellHook = ''
                        unset SOURCE_DATE_EPOCH
                        echo "👋 Entering Montaigne Dev Env (Nix managing Python core + PyTorch/CUDA)..."

                        # --- Venv Setup ---
                        _NIX_PYTHON_INTERPRETER="${python}/bin/python"
                        if ! command -v "$_NIX_PYTHON_INTERPRETER" &> /dev/null; then
                          echo "❌ Fatal: Nix Python interpreter not found at '$_NIX_PYTHON_INTERPRETER'." && return 1
                        fi
                        echo "🐍 Using Nix Python for venv base: $_NIX_PYTHON_INTERPRETER"
                        _PROJECT_DIR="$(pwd)"
                        VENV_DIR="$_PROJECT_DIR/.venv"
                        export VIRTUAL_ENV="$VENV_DIR"
                        export PATH="$VENV_DIR/bin:$PATH" # Prepend venv bin
                        echo "   Resolved VIRTUAL_ENV='$VIRTUAL_ENV'"
                        echo "   Prepended venv bin to PATH."
                        if [ ! -f "$VENV_DIR/bin/activate" ]; then
                          echo "🐍 Creating Python virtual environment using uv in '$VENV_DIR'..."
                          if ! uv venv "$VENV_DIR" --python "$_NIX_PYTHON_INTERPRETER"; then
                            echo "❌ Fatal: Failed to create uv virtual environment." && return 1
                          fi
                          echo "✅ Virtual environment created."
                        else
                          echo "🐍 Re-using existing virtual environment '$VENV_DIR'."
                        fi

                        # --- Venv Activation ---
                        if [ -f "$VENV_DIR/bin/activate" ]; then
                           echo "🐍 Activating Python virtual environment..."
                           source "$VENV_DIR/bin/activate"
                           echo "   VIRTUAL_ENV is: $VIRTUAL_ENV"
                           _VENV_PYTHON_PATH=$(command -v python)
                           echo "   Python interpreter path (venv): $_VENV_PYTHON_PATH"
                           echo "   Python version (venv): $(python --version)"
                           if ! [[ "$_VENV_PYTHON_PATH" == "$VENV_DIR/bin/python" ]]; then
                             echo "⚠️ Warning: 'command -v python' found '$_VENV_PYTHON_PATH' which is not the expected venv path '$VENV_DIR/bin/python'."
                           fi
                        else
                          echo "❌ Fatal: Failed to find activate script in '$VENV_DIR/bin/activate'." && return 1
                        fi

                        # --- uv Dependency Installation ---
                        if command -v uv &> /dev/null; then
                           echo "📦 Installing/Verifying project-specific Python dependencies via uv into active venv '$VENV_DIR'..."
                           # Added --no-cache-dir for cleaner installs potentially
                           if ! uv pip install --no-cache-dir \
                               click==8.1.8 requests'>=2.31.0' TTS==0.22.0 \
                               openai-whisper==20240930 rapidfuzz==3.13.0 pydub'>=0.25.0'; then
                             echo "❌ Fatal: Failed to install base dependencies with uv into venv '$VENV_DIR'." && return 1
                           fi
                           echo "🏗️ Installing local Montaigne package in editable mode into venv..."
                           if ! uv pip install --no-deps -e "$_PROJECT_DIR"; then
                             echo "⚠️ Warning: Failed to install local package '$_PROJECT_DIR' in editable mode with uv."
                             # Consider 'return 1' if this is critical
                           fi
                           echo "✅ uv dependency installation complete."
                        else
                          echo "❌ Fatal: uv command not found in PATH." && return 1
                        fi

                        # --- Sanity Checks ---
                        echo "" && echo "=== Environment Sanity Checks ==="
                        # --- PyTorch/Torchaudio Check ---
                        echo "🔍 Checking PyTorch & Torchaudio (managed by Nix, accessed via venv Python)..."
                        if [ -n "$_VENV_PYTHON_PATH" ] && command -v "$_VENV_PYTHON_PATH" &> /dev/null; then
                          python_exit_status=0
                          echo "DEBUG: Running python check script..."
                          # Execute Python script using the venv Python, capture exit status
                          "$_VENV_PYTHON_PATH" <<EOF || python_exit_status=$?
            # --- Python Check Script Start ---
            import sys, os, torch, torchaudio, importlib.util, subprocess

            messages = []
            cuda_available = False; cudnn_available = False; device_count = 0; exit_code = 0

            messages.append(f"---> Python Executable: {sys.executable}")
            messages.append(f"---> Python Version: {sys.version.split()[0]}")

            # Check PyTorch
            try:
                torch_spec = importlib.util.find_spec("torch")
                if not torch_spec:
                    messages.append("❌ ERROR: PyTorch package spec not found!")
                    exit_code = 1
                else:
                    messages.append(f"---> PyTorch version: {torch.__version__}")
                    messages.append(f"---> PyTorch path: {torch_spec.origin}")
                    # Check CUDA/cuDNN safely within try block for torch import
                    try:
                        cuda_available = torch.cuda.is_available()
                        messages.append(f"---> CUDA Available (torch.cuda.is_available()): {cuda_available}")
                        if cuda_available:
                            cudnn_available = torch.backends.cudnn.is_available()
                            messages.append(f"---> cuDNN Available (torch.backends.cudnn.is_available()): {cudnn_available}")
                            device_count = torch.cuda.device_count()
                            messages.append(f"---> CUDA Device Count: {device_count}")
                            if device_count > 0:
                                try:
                                    idx = torch.cuda.current_device(); messages.append(f"---> Current CUDA Device Index: {idx}"); messages.append(f"---> Current CUDA Device Name: {torch.cuda.get_device_name(idx)}")
                                except Exception as e_dev: messages.append(f"    ⚠️ Error getting CUDA device info: {e_dev}")
                            else: messages.append(f"---> Current CUDA Device Index: N/A (No devices detected/usable by Torch)"); messages.append(f"---> Current CUDA Device Name: N/A (No devices detected/usable by Torch)")
                        else: messages.append(f"---> cuDNN Available: N/A (CUDA not available)"); messages.append(f"---> CUDA Device Count: N/A (CUDA not available)"); messages.append(f"---> Current CUDA Device Index: N/A"); messages.append(f"---> Current CUDA Device Name: N/A")
                        # Uncomment below if unavailable CUDA should cause failure
                        # if not cuda_available:
                        #    messages.append("    INFO: CUDA check reported unavailable.")
                        #    exit_code = 1
                    except Exception as e_cuda:
                        messages.append(f"    ⚠️ Error during CUDA/cuDNN check via Torch: {e_cuda}")
                        cuda_available=False; cudnn_available=False; device_count=0
                        messages.append(f"---> CUDA Available: False (Error during check)")
                        messages.append(f"---> cuDNN Available: False (Error during check)")
                        messages.append(f"---> CUDA Device Count: 0 (Error during check)")
                        exit_code = 1 # Treat inability to check as an error

            except ImportError as e_imp:
                messages.append(f"❌ ERROR: Failed to import PyTorch: {e_imp}")
                messages.append(f"   Check LD_LIBRARY_PATH and CUDA Toolkit/Driver compatibility.")
                exit_code = 1
            except Exception as e_torch_init:
                 messages.append(f"❌ ERROR: Unexpected error during PyTorch initialization: {e_torch_init}")
                 exit_code = 1

            # Check Torchaudio (only if PyTorch import succeeded)
            if exit_code == 0:
                try:
                    torchaudio_spec = importlib.util.find_spec("torchaudio")
                    if torchaudio_spec:
                         messages.append(f"---> Torchaudio version: {torchaudio.__version__}")
                         messages.append(f"---> Torchaudio path: {torchaudio_spec.origin}")
                    else:
                        messages.append("❌ ERROR: Torchaudio package spec not found!")
                        exit_code = 1
                except ImportError as e_audio_imp:
                    messages.append(f"❌ ERROR: Failed to import Torchaudio: {e_audio_imp}")
                    exit_code = 1
                except Exception as e_audio_init:
                    messages.append(f"❌ ERROR: Unexpected error during Torchaudio initialization: {e_audio_init}")
                    exit_code = 1
            else:
                messages.append("INFO: Skipping Torchaudio check due to PyTorch import failure.")


            # Check linked libraries (ldd) - only if PyTorch spec was found initially
            if torch_spec:
                messages.append("---> Linked libraries check (ldd on torch C library):")
                ldd_path = subprocess.getoutput('command -v ldd')
                if ldd_path:
                    try:
                        torch_lib_path = os.path.dirname(torch_spec.origin); c_lib_path_options = [os.path.join(torch_lib_path, "lib", lib) for lib in ["libtorch_python.so", "libtorch_cuda.so", "libtorch.so"]] + [os.path.join(torch_lib_path, "_C.so")]; c_lib_path = next((p for p in c_lib_path_options if os.path.exists(p)), None)
                        if c_lib_path:
                            ldd_cmd = [ldd_path, c_lib_path]; messages.append(f"     Running command: {' '.join(ldd_cmd)}")
                            try:
                                result = subprocess.run(ldd_cmd, capture_output=True, text=True, timeout=5, check=False); relevant_libs = [line for line in result.stdout.splitlines() if any(s in line for s in ['cuda', 'cudnn', 'nvinfer', 'nvrtc'])]
                                if result.returncode == 0: messages.append(f"     Relevant linked libraries found:\n" + "\n".join([f"       {l.strip()}" for l in relevant_libs])) if relevant_libs else messages.append(f"     (ldd successful, but no relevant CUDA/cuDNN libs found linked)")
                                else: messages.append(f"     (ldd command failed with exit code {result.returncode}. Stderr:\n{result.stderr.strip()})")
                            except subprocess.TimeoutExpired: messages.append(f"     (ldd command timed out after 5 seconds)")
                            except Exception as e_ldd: messages.append(f"     (Error running ldd command: {e_ldd})")
                        else: messages.append(f"     Could not find a common torch C library to run ldd on (checked options).")
                    except Exception as e: messages.append(f"    ⚠️ Error during ldd check setup: {e}")
                elif not ldd_path: messages.append("     Skipping ldd check because 'ldd' command was not found in PATH.")
            else:
                messages.append("INFO: Skipping LDD check because PyTorch spec was not found.")


            print("\n".join(messages), flush=True); sys.exit(exit_code)
            # --- Python Check Script End ---
            EOF
                          echo "DEBUG: Python check script finished. Exit Status: $python_exit_status"
                          if [ $python_exit_status -ne 0 ]; then echo "❌ Fatal: Python check script failed (Exit Status: $python_exit_status)." && return 1
                          else echo "✅ Python check script completed successfully."; fi
                        else echo "❌ Fatal: Venv Python path '$_VENV_PYTHON_PATH' not found or not executable." && return 1; fi

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
                        echo "   Nix manages: Python ${python.version}, PyTorch+CUDA, Torchaudio, Core libs (from Nixpkgs ${nixpkgs.rev or "commit " + nixpkgs.lastModifiedDate})"
                        echo "   uv manages other Python packages in: $VIRTUAL_ENV"
                        echo ""
                        echo "📌 Quick Start:"
                        echo "   just --list          # Show available commands"
                        echo "   just run -- --help   # Run the Montaigne CLI"
                        echo "   python --version     # Verify venv Python ($(python --version))"
                        echo "   which python         # Verify venv Python path ($(command -v python))"
                        echo "   uv pip list          # List venv packages"
                        echo ""
          ''; # End of shellHook definition
        }; # End of mkShell definition

      } # End of the attribute set returned by 'let...in'.
    ); # End of eachDefaultSystem function call
} # End of flake definition
