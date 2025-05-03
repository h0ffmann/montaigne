"""
Audio metrics calculation module for Montaigne TTS.

Provides audio quality metrics including SNR, spectral analysis, and other acoustic features.
"""

import logging
from pathlib import Path

import numpy as np

# Try importing librosa, handle if missing
try:
    import librosa

    LIBROSA_AVAILABLE = True
except ImportError:
    LIBROSA_AVAILABLE = False
    librosa = None  # type: ignore

logger = logging.getLogger(__name__)


class AudioMetrics:
    """
    Class for calculating various audio metrics.

    Provides methods to analyze audio quality, including:
    - SNR (Signal-to-Noise Ratio)
    - RMS (Root Mean Square) energy
    - Spectral characteristics
    - Dynamic range
    - Pitch and harmonic analysis
    """

    @staticmethod
    def calculate_audio_metrics(audio_path: Path) -> dict[str, float]:
        """
        Calculate comprehensive audio metrics for a given audio file.

        Args:
            audio_path: Path to the audio file

        Returns:
            Dictionary containing various audio metrics
        """
        if not LIBROSA_AVAILABLE:
            logger.warning("Librosa not available. Cannot calculate audio metrics.")
            return {}

        try:
            y, sr = librosa.load(str(audio_path), sr=None)

            # Basic energy metrics
            rms = np.sqrt(np.mean(y**2))
            peak = np.max(np.abs(y))

            # SNR estimation
            noise_floor = np.percentile(np.abs(y), 5)  # Bottom 5% as noise
            signal_power = rms**2
            noise_power = noise_floor**2
            snr = 10 * np.log10(signal_power / noise_power) if noise_power > 1e-10 else float("inf")

            # Duration
            duration = librosa.get_duration(y=y, sr=sr)

            # Spectral features
            spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)[0]
            mean_spectral_centroid = np.mean(spectral_centroid)

            spectral_bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)[0]
            mean_bandwidth = np.mean(spectral_bandwidth)

            spectral_rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)[0]
            mean_rolloff = np.mean(spectral_rolloff)

            # Zero-crossing rate
            zcr = librosa.feature.zero_crossing_rate(y)[0]
            mean_zcr = np.mean(zcr)

            # Dynamic range
            dynamic_range = 20 * np.log10(peak / noise_floor) if noise_floor > 1e-10 else float("inf")

            # Harmonic-percussive separation
            y_harmonic, y_percussive = librosa.effects.hpss(y)
            harmonic_ratio = np.mean(y_harmonic**2) / (np.mean(y**2) + 1e-10)

            # Pitch detection (F0 estimation)
            f0 = librosa.yin(y, fmin=50, fmax=400)
            mean_f0 = np.mean(f0[f0 > 0]) if np.any(f0 > 0) else 0

            return {
                "rms": float(rms),
                "peak": float(peak),
                "dynamic_range_db": float(dynamic_range),
                "snr_db": float(snr),
                "duration_sec": float(duration),
                "spectral_centroid_hz": float(mean_spectral_centroid),
                "spectral_bandwidth_hz": float(mean_bandwidth),
                "spectral_rolloff_hz": float(mean_rolloff),
                "zero_crossing_rate": float(mean_zcr),
                "harmonic_ratio": float(harmonic_ratio),
                "mean_f0_hz": float(mean_f0),
                "sample_rate": int(sr),
            }
        except Exception as e:
            logger.error(f"Failed to calculate audio metrics: {e}")
            return {}

    @staticmethod
    def calculate_voice_quality_score(metrics: dict[str, float]) -> float:
        """
        Calculate a simple voice quality score based on audio metrics.

        Args:
            metrics: Dictionary of audio metrics

        Returns:
            Float score between 0 and 100
        """
        if not metrics:
            return 0.0

        # Weights for different metrics
        weights = {
            "snr_db": 0.3,  # SNR is crucial for quality
            "dynamic_range_db": 0.2,  # Good dynamic range indicates clear speech
            "harmonic_ratio": 0.2,  # High harmonic content usually indicates voice
            "rms": 0.15,  # Adequate energy level
            "spectral_centroid_hz": 0.1,  # Frequency content
            "mean_f0_hz": 0.05,  # Pitch detection
        }

        normalized_scores = {}

        # Normalize SNR (typical range -10 to 30 dB)
        if "snr_db" in metrics:
            snr = metrics["snr_db"]
            normalized_scores["snr_db"] = min(max((snr + 10) / 40, 0), 1)

        # Normalize dynamic range (typical range 10 to 50 dB)
        if "dynamic_range_db" in metrics:
            dr = metrics["dynamic_range_db"]
            normalized_scores["dynamic_range_db"] = min(max((dr - 10) / 40, 0), 1)

        # Harmonic ratio (0 to 1)
        if "harmonic_ratio" in metrics:
            normalized_scores["harmonic_ratio"] = metrics["harmonic_ratio"]

        # RMS (typical range 0.01 to 0.1)
        if "rms" in metrics:
            rms = metrics["rms"]
            normalized_scores["rms"] = min(max((rms - 0.01) / 0.09, 0), 1)

        # Spectral centroid (typical range 1000 to 3000 Hz for voice)
        if "spectral_centroid_hz" in metrics:
            centroid = metrics["spectral_centroid_hz"]
            normalized_scores["spectral_centroid_hz"] = min(max((centroid - 1000) / 2000, 0), 1)

        # F0 (typical range 100 to 300 Hz)
        if "mean_f0_hz" in metrics:
            f0 = metrics["mean_f0_hz"]
            normalized_scores["mean_f0_hz"] = min(max((f0 - 100) / 200, 0), 1)

        # Calculate weighted score
        score = 0.0
        total_weight = 0.0

        for metric, weight in weights.items():
            if metric in normalized_scores:
                score += normalized_scores[metric] * weight
                total_weight += weight

        # Normalize to 0-100 scale
        if total_weight > 0:
            return (score / total_weight) * 100
        else:
            return 0.0

    @staticmethod
    def generate_metrics_report(input_metrics: dict | None, output_metrics: dict[str, float]) -> str:
        """
        Generate a formatted report of audio metrics.

        Args:
            input_metrics: Metrics for input audio file(s)
            output_metrics: Metrics for output audio file

        Returns:
            Formatted string report
        """
        report = []

        # Output metrics report
        if output_metrics:
            report.append("📊 Output Audio Metrics:")
            report.append(f"  Duration: {output_metrics.get('duration_sec', 'N/A'):.2f}s")
            report.append(f"  SNR: {output_metrics.get('snr_db', 'N/A'):.1f}dB")
            report.append(f"  RMS Energy: {output_metrics.get('rms', 'N/A'):.3f}")
            report.append(f"  Dynamic Range: {output_metrics.get('dynamic_range_db', 'N/A'):.1f}dB")
            report.append(f"  Sample Rate: {output_metrics.get('sample_rate', 'N/A')}Hz")
            report.append(
                f"  Voice Quality Score: {AudioMetrics.calculate_voice_quality_score(output_metrics):.1f}/100"
            )
            report.append("")

        # Input metrics report
        if input_metrics:
            if isinstance(input_metrics, list):
                # Multiple input files
                for i, item in enumerate(input_metrics):
                    if "file" in item and "metrics" in item and item["metrics"]:
                        report.append(f"📝 Input Audio {i + 1} Metrics ({Path(item['file']).name}):")
                        metrics = item["metrics"]
                        report.append(f"  SNR: {metrics.get('snr_db', 'N/A'):.1f}dB")
                        report.append(f"  Duration: {metrics.get('duration_sec', 'N/A'):.2f}s")
                        report.append(
                            f"  Voice Quality Score: {AudioMetrics.calculate_voice_quality_score(metrics):.1f}/100"
                        )
                        report.append("")
            elif isinstance(input_metrics, dict) and input_metrics:
                # Single input file
                report.append("📝 Input Audio Metrics:")
                report.append(f"  SNR: {input_metrics.get('snr_db', 'N/A'):.1f}dB")
                report.append(f"  Duration: {input_metrics.get('duration_sec', 'N/A'):.2f}s")
                report.append(
                    f"  Voice Quality Score: {AudioMetrics.calculate_voice_quality_score(input_metrics):.1f}/100"
                )
                report.append("")

        return "\n".join(report)


# Convenience functions for backward compatibility
def calculate_audio_metrics(audio_path: Path) -> dict[str, float]:
    """
    Calculate audio metrics for a given audio file.
    Convenience wrapper for the AudioMetrics class.
    """
    return AudioMetrics.calculate_audio_metrics(audio_path)


def generate_metrics_report(input_metrics: dict | None, output_metrics: dict[str, float]) -> str:
    """
    Generate a formatted report of audio metrics.
    Convenience wrapper for the AudioMetrics class.
    """
    return AudioMetrics.generate_metrics_report(input_metrics, output_metrics)
