#!/bin/bash
set -e

echo "🔍 Montaigne ML Environment Unified Debugger 🔍"
echo "=============================================="
echo "Running detection on $(date)"
echo

# Determine if we're in a virtual environment
if [[ -n "$VIRTUAL_ENV" ]]; then
    PYTHON_CMD="$VIRTUAL_ENV/bin/python"
    UV_CMD="$VIRTUAL_ENV/bin/uv"
    echo "🐍 Using virtual environment: $VIRTUAL_ENV"
else
    PYTHON_CMD="python"
    UV_CMD="uv"
    echo "⚠️ Not running in a virtual environment"
fi

#=====================================================
# PART 1: NIX ENVIRONMENT & SYSTEM DEPENDENCIES
#=====================================================
echo
echo "════════════════════════════════════"
echo "📦 NIX ENVIRONMENT INFORMATION"
echo "════════════════════════════════════"

echo -n "🔖 Nix Version: "
nix --version 2>/dev/null || echo "Not available"

echo -n "📋 Flake Support: "
if nix flake --help &>/dev/null; then
    echo "Available"
else
    echo "Not available"
fi

echo -n "🔄 Direnv Status: "
if command -v direnv &>/dev/null; then
    echo "Installed - $(direnv --version)"
else
    echo "Not installed"
fi

echo
echo "🧩 System Dependencies from Nix Store:"
echo "------------------------------------"

# Function to check Nix package version
check_nix_package() {
    local pkg_name="$1"
    local query="$2"
    local emoji="$3"
    
    echo -n "${emoji} $pkg_name: "
    
    # Try different methods to find the package
    if which $query &>/dev/null; then
        echo "✅ Found - $(which $query)"
        return 0
    elif nix-store -q --references /run/current-system/sw 2>/dev/null | grep -q "$pkg_name"; then
        local pkg_path=$(nix-store -q --references /run/current-system/sw | grep "$pkg_name" | head -n 1)
        echo "✅ Found at $pkg_path"
        return 0
    else
        # Try to query using nix-env
        local result=$(nix-env -qa "$pkg_name" 2>/dev/null || echo "")
        if [[ -n "$result" ]]; then
            echo "✅ Available but not installed: $result"
        else
            echo "❓ Not found in Nix store"
        fi
        return 1
    fi
}

# Check key libraries used by Montaigne
check_nix_package "ffmpeg" "ffmpeg" "🎬"
check_nix_package "libsndfile" "sndfile-info" "🔊"
check_nix_package "fftw" "fftw-wisdom" "📊"
check_nix_package "portaudio" "pacat" "🎙️"
check_nix_package "cuda" "nvcc" "🎮"
check_nix_package "alsa-lib" "aplay" "🎵"

# Check for shared libraries
echo
echo "📚 Checking Audio Library Dependencies:"
echo "------------------------------------"

echo -n "🔊 libsndfile.so: "
find /nix/store -path "*/lib/libsndfile.so*" | head -n 1 || echo "Not found"

echo -n "📊 libfftw3.so: "
find /nix/store -path "*/lib/libfftw3.so*" | head -n 1 || echo "Not found"

echo -n "🎙️ libportaudio.so: "
find /nix/store -path "*/lib/libportaudio.so*" | head -n 1 || echo "Not found"

# NVIDIA/CUDA detection
echo
echo "🎮 NVIDIA Driver/CUDA Detection:"
echo "------------------------------"

echo -n "🔌 NVIDIA Driver (from Nix): "
if [ -e /run/opengl-driver/lib/libcuda.so ]; then
    echo "✅ Found at /run/opengl-driver/lib/"
    ls -l /run/opengl-driver/lib/libcuda.so
else
    echo "❌ Not found in /run/opengl-driver/lib/"
fi

echo -n "📝 Trying nvidia-smi: "
if command -v nvidia-smi &>/dev/null; then
    echo "✅ Available"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
else
    echo "❌ Not found in PATH"
fi

echo -n "🏠 CUDA Home: "
if [ -n "$CUDA_HOME" ]; then
    echo "$CUDA_HOME"
else
    echo "Not set"
fi

#=====================================================
# PART 2: PYTHON & PACKAGE ENVIRONMENT
#=====================================================
echo
echo "════════════════════════════════════"
echo "🐍 PYTHON ENVIRONMENT"
echo "════════════════════════════════════"

echo -n "📌 Python Version: "
$PYTHON_CMD --version || echo "Not available"

echo -n "📍 Python Path: "
which $PYTHON_CMD || echo "Not found"

# Check for UV
echo -n "🔧 UV Tool: "
if command -v $UV_CMD &>/dev/null; then
    echo "✅ Found - $($UV_CMD --version | head -n 1)"
    UV_AVAILABLE=true
else
    echo "❌ Not found in PATH"
    echo "⚠️ Will skip package checks that require UV"
    UV_AVAILABLE=false
fi

# Package listing with UV if available
if [ "$UV_AVAILABLE" = "true" ]; then
    echo
    echo "📋 Python Package List (via UV):"
    echo "------------------------------"
    $UV_CMD pip list || echo "Failed to list packages"
fi

echo
echo "🔍 Key Package Version Check:"
echo "--------------------------"

# Function to check package version with pip/UV
check_package() {
    local pkg_name="$1"
    local emoji="$2"
    
    echo -n "${emoji} $pkg_name: "
    
    # Try with UV first if available
    if [ "$UV_AVAILABLE" = "true" ]; then
        pkg_info=$($UV_CMD pip show $pkg_name 2>/dev/null)
    fi
    
    # Fall back to pip if UV failed or isn't available
    if [ -z "$pkg_info" ]; then
        pkg_info=$($PYTHON_CMD -m pip show $pkg_name 2>/dev/null)
    fi
    
    if [[ -n "$pkg_info" ]]; then
        version=$(echo "$pkg_info" | grep "^Version:" | awk '{print $2}')
        location=$(echo "$pkg_info" | grep "^Location:" | awk '{print $2}')
        echo "✅ Version $version"
        echo "   Location: $location"
        return 0
    else
        # Try direct import as last resort
        if $PYTHON_CMD -c "import $pkg_name; print('Version:', getattr($pkg_name, '__version__', 'Unknown'))" 2>/dev/null; then
            return 0
        else
            echo "❌ Not installed or not importable"
            return 1
        fi
    fi
}

# Check specific ML packages
check_package "numpy" "🔢"
check_package "torch" "🔥"
check_package "librosa" "🎵"
check_package "soundfile" "🔊"
check_package "noisereduce" "🔇"
check_package "numba" "⚡"
check_package "TTS" "🗣️"
check_package "transformers" "🤗"
check_package "scipy" "📊"
check_package "audioread" "🎧"
check_package "montaigne" "🏔️"

#=====================================================
# PART 3: IMPORT & INTEGRATION TESTS
#=====================================================
echo
echo "════════════════════════════════════"
echo "🧪 IMPORT & INTEGRATION TESTS"
echo "════════════════════════════════════"

echo "🧩 Testing Package Imports:"
echo "-----------------------"

# Function to check if package imports successfully
test_import() {
    local pkg_name="$1"
    local import_name="${2:-$1}"
    local emoji="$3"
    
    echo -n "${emoji} $import_name: "
    if $PYTHON_CMD -c "import $import_name; print('✅ Success')" 2>/dev/null; then
        return 0
    else
        echo "❌ Failed"
        echo "   Error details:"
        $PYTHON_CMD -c "import $import_name" 2>&1 | head -n 3
        return 1
    fi
}

# Test specific imports
test_import "numpy" "numpy" "🔢"
test_import "torch" "torch" "🔥"
test_import "librosa" "librosa" "🎵"
test_import "soundfile" "soundfile" "🔊"
test_import "noisereduce" "noisereduce" "🔇" 
test_import "numba" "numba" "⚡"
test_import "montaigne" "montaigne" "🏔️"

echo
echo "🧬 Testing NumPy-Librosa Integration:"
echo "---------------------------------"
$PYTHON_CMD -c "
try:
    print('Importing NumPy...', end=' ')
    import numpy as np
    print('✅')
    
    print('Importing Librosa...', end=' ')
    import librosa
    print('✅')
    
    print('Testing integration...', end=' ')
    data = np.ones(1024)
    result = librosa.util.normalize(data)
    print('✅ Success!')
except ImportError as e:
    print(f'❌ Import Error: {e}')
except Exception as e:
    print(f'❌ Runtime Error: {e}')
"

echo
echo "🔥 PyTorch CUDA Detection:"
echo "----------------------"
$PYTHON_CMD -c "
try:
    import torch
    print(f'PyTorch Version: {torch.__version__}')
    print(f'CUDA Available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'CUDA Version: {torch.version.cuda}')
        print(f'Device Count: {torch.cuda.device_count()}')
        for i in range(torch.cuda.device_count()):
            print(f'Device {i}: {torch.cuda.get_device_name(i)}')
    print(f'Default Device: {\"cuda\" if torch.cuda.is_available() else \"cpu\"}')
except ImportError:
    print('PyTorch not available')
except Exception as e:
    print(f'Error checking PyTorch: {e}')
"

# Special check for librosa working with numpy
echo
echo "🎵 Detailed Librosa Information:"
echo "----------------------------"
$PYTHON_CMD -c "
try:
    import librosa
    import sys
    
    # Basic version info
    print(f'Librosa Version: {librosa.__version__}')
    print(f'Librosa Path: {librosa.__file__}')
    
    # Check underlying NumPy
    import numpy as np
    print(f'NumPy Version: {np.__version__}')
    
    # Check AudioRead backends
    import audioread
    print(f'AudioRead Backends: {[b.__name__.split(\".\")[-1] for b in audioread.available_backends()]}')
    
    # Try to run librosa.show_versions
    print('\\nLibrosa Dependencies:')
    try:
        librosa.show_versions()
    except Exception as e:
        print(f'Could not show versions: {e}')
    
except ImportError as e:
    print(f'Error importing librosa: {e}')
except Exception as e:
    print(f'Unexpected error: {e}')
"

echo
echo "✅ Montaigne ML Environment Check Complete!"
echo "Save this output to help with debugging."