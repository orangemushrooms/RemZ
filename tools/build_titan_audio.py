"""Bake original titan sound design; no runtime DSP or downloaded sound packs.

Uses the four existing, user-supplied zombie recordings as organic throat layers.
Run: python tools/build_titan_audio.py (numpy, scipy, imageio-ffmpeg).
"""
from pathlib import Path
import hashlib
import json
import subprocess

import imageio_ffmpeg
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "godot/assets/audio/sfx"
OUT = SOURCE / "titan"
RATE = 44100


def filt(x, low=None, high=None):
    limits = [low, high] if low and high else low or high
    mode = "bandpass" if low and high else "highpass" if low else "lowpass"
    return signal.sosfilt(signal.butter(3, limits, btype=mode, fs=RATE, output="sos"), x)


def norm(x):
    return x / max(float(np.max(np.abs(x))), 1e-9)


def recording(index):
    raw = subprocess.check_output([
        imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", str(SOURCE / f"zombie_{index}.mp3"),
        "-f", "f32le", "-ac", "1", "-ar", str(RATE), "pipe:1",
    ])
    return norm(filt(np.frombuffer(raw, np.float32).astype(float), low=35, high=7000))


def fit(x, length, speed=1.0, offset=0.0):
    return np.interp((np.arange(length) / RATE - offset) * speed * RATE,
                     np.arange(len(x)), x, left=0, right=0)


def echoes(x):
    # Short, diffuse outdoor reflections rather than an enclosed cathedral reverb.
    tail = filt(x, high=950)
    result = x.copy()
    for delay, gain in [(0.093, 0.12), (0.211, 0.075), (0.389, 0.05), (0.631, 0.022)]:
        shift = int(delay * RATE)
        result[shift:] += tail[:-shift] * gain
    return result


def roar(index, duration, seed, dying=False, short=False):
    rng = np.random.default_rng(seed)
    t = np.arange(int(RATE * duration)) / RATE
    source = recording(index)
    # Two different organic throat layers, almost an octave and an octave-and-a-half down.
    a = fit(source, len(t), speed=0.43 if not short else 0.95, offset=0.20)
    b = fit(recording(index % 4 + 1), len(t), speed=0.56 if not short else 1.08, offset=0.32)
    organic = norm(filt(a * 0.8 + b * 0.3, low=48, high=2400))
    syllables = np.sqrt(np.maximum(0, signal.sosfilt(
        signal.butter(2, 15, fs=RATE, output="sos"), organic ** 2)))
    syllables = norm(syllables)
    # Irregular subharmonic vocal folds follow the recorded utterance, not a flat drone.
    freq = 48 + 12 * np.sin(np.pi * np.minimum(t / (duration * 0.7), 1))
    freq += 1.9 * np.sin(t * 7.4) + 0.8 * np.sin(t * 19.7 + seed)
    if dying:
        freq *= 1.0 - 0.3 * np.minimum(t / duration, 1)
    phase = np.cumsum(freq) * (2 * np.pi / RATE)
    folds = sum(np.sin(phase * k + 0.16 * k) / k ** 1.35 for k in range(1, 19))
    folds = norm(folds) * (0.28 + 0.72 * syllables)
    folds *= 0.72 + 0.28 * np.sin(phase * 0.5 + 0.2) ** 2
    air = norm(filt(rng.standard_normal(len(t)), low=280, high=1600))
    throat = np.tanh(2.5 * (organic * 0.82 + folds * 0.52)) * 0.67
    throat += air * syllables * 0.24
    end = duration - (0.35 if short else 0.9)
    envelope = np.interp(t, [0, 0.12, 0.28, end * 0.40, end * 0.73, end, duration],
                         [0, 0.04, 0.70, 1.0, 0.76, 0.0, 0.0])
    breath = norm(filt(rng.standard_normal(len(t)), low=180, high=1400))
    breath *= np.exp(-((t - 0.18) / 0.13) ** 2) * 0.12
    return echoes(filt(throat * envelope + breath, low=28, high=3600))


def ground(duration, seed, slam=False):
    rng = np.random.default_rng(seed)
    t = np.arange(int(RATE * duration)) / RATE
    attack = 1 - np.exp(-t / 0.009)
    freq = 35 + (42 if slam else 27) * np.exp(-t / 0.065)
    phase = np.cumsum(freq) * (2 * np.pi / RATE)
    bass = (np.sin(phase) + 0.34 * np.sin(phase * 1.97)) * np.exp(-t / (0.62 if slam else 0.40))
    body = norm(filt(rng.standard_normal(len(t)), low=45, high=280)) * np.exp(-t / 0.35)
    grit = norm(filt(rng.standard_normal(len(t)), low=300, high=2000)) * np.exp(-t / 0.085)
    settle = norm(filt(rng.standard_normal(len(t)), low=75, high=750)) * np.exp(-t / 0.75)
    for _ in range(18 if slam else 9):
        at = rng.uniform(0.05, 0.9)
        settle += np.exp(-np.maximum(t - at, 0) / 0.027) * (t > at) * np.sin(t * rng.uniform(700, 1600)) * 0.13
    return echoes((bass * 0.70 + body * 0.35 + grit * 0.22 + settle * 0.14) * attack)


def save(name, x):
    x = filt(x, low=26)
    # Soft saturation, then true-peak headroom and click-free endpoints.
    x = np.tanh(x * 1.25)
    fade = int(RATE * 0.03)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    x *= (10 ** (-3.5 / 20)) / np.max(np.abs(signal.resample_poly(x, 4, 1)))
    pcm = np.round(x * 32767).astype(np.int16)
    wavfile.write(OUT / f"{name}.wav", RATE, pcm)
    spectrum = np.abs(np.fft.rfft(x)) ** 2
    frequencies = np.fft.rfftfreq(len(x), 1 / RATE)
    return {"file": f"{name}.wav", "seconds": round(len(x) / RATE, 3),
            "peak_dbfs": round(20 * np.log10(np.max(np.abs(x))), 2),
            "rms_dbfs": round(20 * np.log10(np.sqrt(np.mean(x * x))), 2),
            "energy_below_250hz": round(float(spectrum[frequencies < 250].sum() / spectrum.sum()), 3),
            "sha256": hashlib.sha256((OUT / f"{name}.wav").read_bytes()).hexdigest()}


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    report = [save("roar_1", roar(2, 5.8, 611)), save("roar_2", roar(4, 6.6, 612)),
              save("roar_3", roar(3, 5.2, 613)), save("windup", roar(1, 2.15, 614, short=True)),
              save("death", roar(4, 6.4, 615, dying=True)),
              save("step_1", ground(1.8, 621)), save("step_2", ground(1.9, 622)),
              save("slam", ground(3.1, 623, slam=True))]
    report_path = ROOT / "artifacts/titan-horror/audio-report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
