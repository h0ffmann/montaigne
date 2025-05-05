#!/usr/bin/env python
"""
Demonstration script for Montaigne TTS new features.

This script showcases:
1. MP3 output (default)
2. Automatic naming
3. Audio metrics analysis
4. TOML metadata persistence
5. Voice quality scoring
6. Performance optimization
"""
import subprocess
import sys
from pathlib import Path
import time
import tomli
from montaigne.metadata_manager import MetadataManager
from montaigne.audio_metrics import AudioMetrics

def run_command(cmd: list) -> tuple[int, str]:
    """Run a command and return its output."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr

def demo_basic_synthesis():
    """Demo 1: Basic synthesis with MP3 output and automatic naming."""
    print("\n" + "="*50)
    print("Demo 1: Basic MP3 Synthesis with Auto-naming")
    print("="*50)
    
    cmd = [
        "montaigne", "synthesize",
        "--text", "Welcome to Montaigne TTS version 0.2.0",
        "--language", "en",
        "--voice-profile", "morgan_freeman"
    ]
    
    print(f"Command: {' '.join(cmd)}")
    code, output = run_command(cmd)
    print(output)
    
    # Find the generated file
    files = list(Path(".").glob("en-morgan_freeman-xtts-*.mp3"))
    if files:
        latest_file = max(files, key=lambda f: f.stat().st_mtime)
        print(f"\n✅ Generated file: {latest_file}")
        return latest_file
    return None

def demo_fast_synthesis():
    """Demo 2: Fast synthesis with processing optimizations."""
    print("\n" + "="*50)
    print("Demo 2: Fast Synthesis (No Processing)")
    print("="*50)
    
    # Regular synthesis
    start_time = time.time()
    cmd_regular = [
        "montaigne", "synthesize",
        "--text", "This is regular synthesis with full processing.",
        "--language", "en",
        "--voice-profile", "obama",
        "--output-file", "regular_output.mp3"
    ]
    print(f"Regular synthesis...")
    code, _ = run_command(cmd_regular)
    regular_time = time.time() - start_time
    
    # Fast synthesis
    start_time = time.time()
    cmd_fast = [
        "montaigne", "synthesize",
        "--text", "This is fast synthesis with no processing.",
        "--language", "en",
        "--voice-profile", "obama",
        "--output-file", "fast_output.mp3",
        "--skip-audio-processing"
    ]
    print(f"Fast synthesis...")
    code, _ = run_command(cmd_fast)
    fast_time = time.time() - start_time
    
    speedup = regular_time / fast_time if fast_time > 0 else float('inf')
    print(f"\n📊 Performance Comparison:")
    print(f"Regular synthesis: {regular_time:.1f}s")
    print(f"Fast synthesis: {fast_time:.1f}s")
    print(f"Speedup: {speedup:.1f}x faster!")

def demo_metadata_analysis():
    """Demo 3: Analyze metadata from synthesis."""
    print("\n" + "="*50)
    print("Demo 3: Metadata Analysis")
    print("="*50)
    
    # Create a test synthesis
    cmd = [
        "montaigne", "synthesize",
        "--text", "Testing metadata persistence feature with voice quality metrics.",
        "--language", "en",
        "--voice-profile", "david_attenborough",
        "--output-file", "metadata_test.mp3"
    ]
    print(f"Running test synthesis...")
    code, output = run_command(cmd)
    
    # Load and display metadata
    metadata_file = Path("metadata_test.mp3.toml")
    if metadata_file.exists():
        try:
            with open(metadata_file, "rb") as f:
                metadata = tomli.load(f)
            
            print("\n📋 Metadata Summary:")
            print(MetadataManager.generate_summary(metadata))
            
            # Show raw metrics
            if "output" in metadata and "metrics" in metadata["output"]:
                metrics = metadata["output"]["metrics"]
                print("\n🔍 Raw Metrics:")
                for key, value in metrics.items():
                    if isinstance(value, float):
                        print(f"  {key}: {value:.3f}")
                    else:
                        print(f"  {key}: {value}")
        except Exception as e:
            print(f"Error loading metadata: {e}")

def demo_quality_comparison():
    """Demo 4: Compare voice quality scores."""
    print("\n" + "="*50)
    print("Demo 4: Voice Quality Comparison")
    print("="*50)
    
    voices = ["obama", "morgan_freeman", "adele"]
    results = []
    
    for voice in voices:
        cmd = [
            "montaigne", "synthesize",
            "--text", "The quick brown fox jumps over the lazy dog.",
            "--language", "en",
            "--voice-profile", voice,
            "--output-file", f"quality_test_{voice}.mp3"
        ]
        
        print(f"Synthesizing with {voice}...")
        code, _ = run_command(cmd)
        
        # Load metadata and get quality score
        metadata_file = Path(f"quality_test_{voice}.mp3.toml")
        if metadata_file.exists():
            try:
                with open(metadata_file, "rb") as f:
                    metadata = tomli.load(f)
                
                metrics = metadata["output"]["metrics"]
                quality_score = metrics.get("voice_quality_score", 0)
                snr = metrics.get("snr_db", 0)
                duration = metrics.get("duration_sec", 0)
                
                results.append({
                    "voice": voice,
                    "quality": quality_score,
                    "snr": snr,
                    "duration": duration
                })
            except Exception as e:
                print(f"Error processing {voice}: {e}")
    
    # Display comparison
    if results:
        print("\n🏆 Voice Quality Comparison:")
        print(f"{'Voice':<20} {'Quality Score':<15} {'SNR (dB)':<10} {'Duration (s)':<10}")
        print("-" * 60)
        
        # Sort by quality score
        results.sort(key=lambda x: x["quality"], reverse=True)
        
        for r in results:
            print(f"{r['voice']:<20} {r['quality']:<15.1f} {r['snr']:<10.1f} {r['duration']:<10.1f}")

def demo_custom_naming():
    """Demo 5: Custom output naming patterns."""
    print("\n" + "="*50)
    print("Demo 5: Custom Naming Patterns")
    print("="*50)
    
    # Test different naming scenarios
    test_cases = [
        {
            "desc": "Automatic MP3 naming",
            "cmd": [
                "montaigne", "synthesize",
                "--text", "Auto-named MP3 file",
                "--language", "fr",
                "--voice-profile", "default"
            ]
        },
        {
            "desc": "Custom path with automatic extension",
            "cmd": [
                "montaigne", "synthesize",
                "--text", "Custom path test",
                "--language", "es",
                "--voice-profile", "shakira",
                "--output-file", "custom/path/test_output"  # No extension
            ]
        },
        {
            "desc": "Full custom filename",
            "cmd": [
                "montaigne", "synthesize",
                "--text", "Full custom name",
                "--language", "pt",
                "--voice-profile", "lula",
                "--output-file", "my_specific_file.mp3"
            ]
        }
    ]
    
    for i, test in enumerate(test_cases, 1):
        print(f"\nTest {i}: {test['desc']}")
        print(f"Command: {' '.join(test['cmd'])}")
        
        # Create output directory if needed
        if "custom/path" in test["cmd"]:
            Path("custom/path").mkdir(parents=True, exist_ok=True)
        
        code, output = run_command(test["cmd"])
        print(output)

def main():
    """Run all demonstrations."""
    print("Montaigne TTS v0.2.0 Feature Demonstration")
    print("=========================================")
    
    # Check if montaigne is installed
    code, _ = run_command(["montaigne", "--version"])
    if code != 0:
        print("Error: Montaigne TTS not found. Please install it first.")
        sys.exit(1)
    
    # Run demonstrations
    demo_basic_synthesis()
    demo_fast_synthesis()
    demo_metadata_analysis()
    demo_quality_comparison()
    demo_custom_naming()
    
    print("\n" + "="*50)
    print("🎉 All demonstrations completed!")
    print("Check the generated files and metadata for details.")
    print("="*50)

if __name__ == "__main__":
    main()