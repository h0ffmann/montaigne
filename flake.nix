# flake.nix - Final Version (Nix manages PyTorch/CUDA, uv for others) - Simplified Python Check Execution
{
  description = "Development environment for Montaigne (Python TTS/STT) with reliable CUDA support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
            cudaSupport = true;
          };
        };

        # Define Python version
        python = pkgs.python311;

        # Select CUDA packages
        cudaPkgs = pkgs.cudaPackages_12_1;
        cudatoolkit = cudaPkgs.cudatoolkit;
        cudnn = cudaPkgs.cudnn;

        # --- Python Packages Managed by Nix ---
        nixPythonMlPackages = with python.pkgs; [
          torchWithCuda
          torchaudio
        ];

        # --- Runtime Libraries ---
        runtimeBuildLibs = with pkgs; [
          cudatoolkit
          cudnn
          ffmpeg
          libsndfile
          alsa-lib
          libGL
          openssl
          zlib
          ncurses5
        ];

        # Calculate the Library Path
        runtimeLibPath = pkgs.lib.makeLibraryPath ([
          pkgs.stdenv.cc.cc.lib
          pkgs.gcc-unwrapped.lib
        ] ++ runtimeBuildLibs);

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
          (pkgs.runCommand "nvidia-smi-wrapper" { } ''
            mkdir -p $out/bin ; _host_nvidia_smi=""
            if [ -e /run/opengl-driver/bin/nvidia-smi ]; then _host_nvidia_smi="/run/opengl-driver/bin/nvidia-smi";
            elif [ -e /run/opengl-driver/lib/nvidia-smi ]; then _host_nvidia_smi="/run/opengl-driver/lib/nvidia-smi";
            elif command -v nvidia-smi &>/dev/null ; then _host_nvidia_smi=$(command -v nvidia-smi); fi
            if [ -n "$_host_nvidia_smi" ] && [ -x "$_host_nvidia_smi" ] ; then ln -s "$_host_nvidia_smi" $out/bin/nvidia-smi;
            else echo '#!/bin/sh' > $out/bin/nvidia-smi ; echo 'echo "nvidia-smi wrapper: Host nvidia-smi not found."' >> $out/bin/nvidia-smi ; echo 'exit 1' >> $out/bin/nvidia-smi ; chmod +x $out/bin/nvidia-smi; fi
          '')
        ];

      in
      {
        # --- Define the Development Shell ---
        devShells.default = pkgs.mkShell {
          name = "montaigne-dev-env-nix-torch";
          packages = montaigneTools ++ nixPythonMlPackages;
          buildInputs = with pkgs; [ stdenv.cc.cc ] ++ runtimeBuildLibs;

          # --- Environment Variables ---
          env = {
            CUDA_HOME = "${cudatoolkit}";
            CUDA_PATH = "${cudatoolkit}";
            LD_LIBRARY_PATH = runtimeLibPath;
            VIRTUAL_ENV = "$PWD/.venv";
            PATH = "$PWD/.venv/bin:${pkgs.lib.makeBinPath montaigneTools}";
            UV_NATIVE_TLS = "1";
            NIX_CFLAGS_COMPILE = toString (pkgs.lib.optionals pkgs.stdenv.isLinux [ "-I${pkgs.lib.getDev pkgs.openssl}/include" "-I${pkgs.lib.getDev pkgs.zlib}/include" "-I${pkgs.lib.getDev pkgs.libsndfile}/include" ]);
            NIX_LDFLAGS = toString (pkgs.lib.optionals pkgs.stdenv.isLinux [ "-L${pkgs.lib.getLib pkgs.openssl}/lib" "-L${pkgs.lib.getLib pkgs.zlib}/lib" "-L${pkgs.lib.getLib pkgs.libsndfile}/lib" ]);
            EXTRA_LDFLAGS = "-L${pkgs.stdenv.cc.cc.lib}/lib -L${pkgs.gcc-unwrapped.lib}/lib";
            EXTRA_CPPFLAGS = "-I${pkgs.stdenv.cc.cc.lib}/include";
            DOCKER_BUILDKIT = "1";
            COMPOSE_DOCKER_CLI_BUILD = "1";
          };

          # --- Shell Hook: Setup Venv and Install uv Packages ---
          shellHook = ''
                        unset SOURCE_DATE_EPOCH
                        echo "👋 Entering Montaigne Dev Env (Nix managing Python core + PyTorch/CUDA)..."

                        # --- Venv Setup ---
                        _NIX_PYTHON_INTERPRETER="${python}/bin/python"
                        if ! command -v "$_NIX_PYTHON_INTERPRETER" &> /dev/null; then
                          echo "❌ Fatal: Nix Python interpreter not found at '$_NIX_PYTHON_INTERPRETER'."
                          return 1
                        fi
                        echo "🐍 Using Nix Python for venv base: $_NIX_PYTHON_INTERPRETER"

                        VENV_DIR="$PWD/.venv"
                        if [ ! -f "$VENV_DIR/bin/activate" ]; then
                          echo "🐍 Creating Python virtual environment using uv in '$VENV_DIR'..."
                          if ! uv venv "$VENV_DIR" --python "$_NIX_PYTHON_INTERPRETER"; then
                            echo "❌ Fatal: Failed to create uv virtual environment."
                            return 1
                          fi
                          echo "✅ Virtual environment created."
                        else
                          echo "🐍 Re-using existing virtual environment '$VENV_DIR'."
                        fi

                        # --- Venv Activation ---
                        if [ -f "$VENV_DIR/bin/activate" ]; then
                           echo "🐍 Activating Python virtual environment..."
                           source "$VENV_DIR/bin/activate"
                           echo "🐍 VIRTUAL_ENV set to: $VIRTUAL_ENV"
                           echo "🐍 Python interpreter path: $(which python)"
                           echo "🐍 Python version: $(python --version)"
                           if [[ "$(which python)" != "$VENV_DIR/bin/python" ]]; then
                             echo "⚠️ Warning: 'which python' does not point to the venv interpreter after activation."
                           fi
                        else
                          echo "❌ Fatal: Failed to find activate script in '$VENV_DIR/bin/activate'."
                          return 1
                        fi

                        # --- uv Dependency Installation ---
                        if command -v uv &> /dev/null; then
                           echo "📦 Installing/Verifying project-specific Python dependencies via uv into active venv '$VENV_DIR'..."
                           if ! uv pip install --no-cache-dir \
                               click==8.1.8 \
                               requests'>=2.31.0' \
                               TTS==0.22.0 \
                               openai-whisper==20240930 \
                               rapidfuzz==3.13.0 \
                               pydub'>=0.25.0'; then
                             echo "❌ Fatal: Failed to install base dependencies with uv into venv '$VENV_DIR'."
                             return 1
                           fi

                           echo "🏗️ Installing local Montaigne package in editable mode..."
                           if ! uv pip install --no-deps -e .; then
                             echo "⚠️ Warning: Failed to install local package '.' in editable mode with uv."
                             # Decide if this should be fatal: return 1
                           fi
                        else
                          echo "❌ Fatal: uv command not found in PATH after venv activation."
                          return 1
                        fi

                        # --- Sanity Checks ---
                        echo ""
                        echo "=== Environment Sanity Checks ==="

                        # --- PyTorch/Torchaudio Check ---
                        echo "🔍 Checking PyTorch & Torchaudio (managed by Nix, accessed via venv Python)..."
                        if command -v python &> /dev/null; then
                          python_exit_status=0 # Initialize

                          echo "DEBUG: Running python check command (output will appear below)..."
                          # Run Python check script directly, letting its output go to stdout/stderr
                          python -c '
            # --- Python Check Script ---
            import sys, os, torch, torchaudio, importlib.util
            messages = []
            cuda_available = False
            exit_code = 0

            messages.append(f"---> Python Executable: {sys.executable}")
            messages.append(f"---> Python Version: {sys.version.split()[0]}")

            # Check PyTorch
            torch_spec = importlib.util.find_spec("torch")
            if torch_spec:
                messages.append(f"---> PyTorch version: {torch.__version__}")
                messages.append(f"---> PyTorch path: {torch_spec.origin}")
                cudnn_available = False; device_count = 0;
                try: cuda_available = torch.cuda.is_available(); cudnn_available = torch.backends.cudnn.is_available();
                except Exception as e: messages.append(f"    ⚠️ Error checking CUDA/cuDNN availability: {e}")
                if cuda_available:
                    try: device_count = torch.cuda.device_count()
                    except Exception as e: messages.append(f"    ⚠️ Error checking CUDA device count: {e}")
                messages.append(f"---> CUDA Available (torch.cuda.is_available()): {cuda_available}")
                messages.append(f"---> cuDNN Available (torch.backends.cudnn.is_available()): {cudnn_available}")
                messages.append(f"---> CUDA Device Count: {device_count}")
                if cuda_available and device_count > 0:
                    try: current_device_idx = torch.cuda.current_device(); messages.append(f"---> Current CUDA Device Index: {current_device_idx}"); messages.append(f"---> Current CUDA Device Name: {torch.cuda.get_device_name(current_device_idx)}");
                    except Exception as e: messages.append(f"    ⚠️ Error getting CUDA device info: {e}")
                elif cuda_available: messages.append(f"---> Current CUDA Device Index: N/A (No devices found)"); messages.append(f"---> Current CUDA Device Name: N/A (No devices found)");
                else: messages.append(f"---> Current CUDA Device Index: N/A"); messages.append(f"---> Current CUDA Device Name: N/A");
            else: messages.append("❌ ERROR: PyTorch package not found by Python interpreter!"); exit_code = 1

            # Check Torchaudio
            torchaudio_spec = importlib.util.find_spec("torchaudio")
            if torchaudio_spec: messages.append(f"---> Torchaudio version: {torchaudio.__version__}"); messages.append(f"---> Torchaudio path: {torchaudio_spec.origin}");
            else: messages.append("❌ ERROR: Torchaudio package not found by Python interpreter!"); exit_code = 1

            # Check linked libraries (Best Effort)
            messages.append("---> Linked libraries check (ldd on torch libraries, requires ldd):")
            try:
                if torch_spec:
                    torch_lib_path = os.path.dirname(torch_spec.origin); c_lib_path = os.path.join(torch_lib_path, "lib", "libtorch_python.so");
                    if not os.path.exists(c_lib_path): c_lib_path = os.path.join(torch_lib_path, "_C.so")
                    if os.path.exists(c_lib_path):
                        ldd_cmd = f"ldd {c_lib_path} 2>/dev/null | grep -E 'cuda|cudnn|nvinfer'"; messages.append(f"     Running: {ldd_cmd}"); ldd_output = os.popen(ldd_cmd).read().strip();
                        if ldd_output: messages.append(f"     Output:\n{ldd_output}");
                        else: messages.append(f"     (No relevant CUDA/cuDNN libs found linked or ldd failed)");
                    else: messages.append(f"     Could not find torch C library ({c_lib_path}) to run ldd on.")
                else: messages.append("     Skipping ldd check because PyTorch was not found.")
            except Exception as e: messages.append(f"    ⚠️ Error running ldd check: {e}")
            print("\n".join(messages))
            sys.exit(exit_code)
            # --- End Python Check Script ---
            '
                          # Capture exit status immediately after execution
                          python_exit_status=$?
                          echo "DEBUG: Python check finished. Exit Status: $python_exit_status"

                          # Check the exit status ONLY
                          if [ $python_exit_status -ne 0 ]; then
                              # Python command failed (returned non-zero exit code)
                              echo "❌ Fatal: Python check script failed (Exit Status: $python_exit_status)."
                              echo "   >>> Check the Python errors printed directly above this message."
                              return 1 # Halt shell setup
                          else
                              # Python command succeeded (exit status 0)
                              echo "✅ Python check script completed successfully (details printed above)."
                              # Secondary checks on output content are removed as we didn't capture it reliably.
                          fi
                        else
                           echo "❌ Fatal: Python command not found after venv activation! Cannot perform checks."
                           return 1
                        fi

                        # --- Docker Check ---
                        echo "🐳 Checking Docker status..."
                        if command -v docker &>/dev/null; then
                          if timeout 5 docker info >/dev/null 2>&1; then
                             echo "✅ Docker daemon is running."
                             if timeout 5 docker info 2>/dev/null | grep -q -E 'Runtimes:.*[[:space:]]nvidia[[:space:]]*'; then echo "✅ NVIDIA Docker runtime detected.";
                             elif [ -f /usr/bin/nvidia-container-runtime ] || [ -f /usr/bin/nvidia-container-runtime-hook ]; then echo "ℹ️ NVIDIA container runtime binary found. Ensure configured.";
                             else echo "⚠️ NVIDIA Docker runtime not detected."; fi
                          else echo "⚠️ Docker daemon not running/responsive/permission error."; fi
                        else echo "❌ Docker command not found \(is 'docker' included in 'packages'?\)." ; fi

                        # --- Host NVIDIA Driver Check ---
                        echo "💻 Checking Host NVIDIA driver via nvidia-smi..."
                        if command -v nvidia-smi &>/dev/null; then
                          nvidia_smi_output=""; nvidia_smi_status=1;
                          if nvidia_smi_output=$(timeout 5 nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1); nvidia_smi_status=$?; then
                             if [ $nvidia_smi_status -eq 0 ]; then echo "✅ nvidia-smi successful. Host Driver Version: $nvidia_smi_output";
                             else if nvidia_smi_output=$(timeout 5 nvidia-smi 2>&1); nvidia_smi_status=$?; then
                                     if [ $nvidia_smi_status -eq 0 ] && echo "$nvidia_smi_output" | grep -q "Driver Version:"; then echo "✅ nvidia-smi generic command successful.";
                                     else echo "⚠️ nvidia-smi ran, but issue likely (Status: $nvidia_smi_status):" ; echo "$nvidia_smi_output" | head -n 5 ; fi
                                  else echo "⚠️ nvidia-smi command failed/timed out (Status: $nvidia_smi_status)." ; echo "$nvidia_smi_output" | head -n 5 ; fi ; fi
                          else echo "⚠️ Could not capture nvidia-smi exit status."; fi
                        else echo "❌ nvidia-smi command not found in PATH."; fi

                        # --- Final Message ---
                        echo "================================"; echo ""
                        echo "✅ Montaigne environment ready!"
                        echo "   Nix manages: Python ${python.version}, PyTorch+CUDA, Torchaudio"
                        echo "   uv manages other Python packages in: $VENV_DIR" ; echo ""
                        echo "📌 Quick Start:"
                        echo "   just --list          # Show available commands" ; echo "   just run -- --help   # Run the Montaigne CLI"
                        echo "   python --version     # Verify venv Python" ; echo "   uv pip list          # List venv packages" ; echo ""
          ''; # End of shellHook
        }; # End of devShells.default
      }
    ); # End of eachDefaultSystem
} # End of flake
