"""Head-burst variants for lethal headshots (25 Sep 2026): godot/assets/audio/sfx/head_burst_1..5.wav.

Layers per variant, each with its own random timing, so no two bursts sound alike:
  - the wet splat: the pumpkin_splat clip, band-limited and time-varied, plus a burst of filtered noise
    ("flesh") with a fast attack and a ragged decay
  - a low thud (a 60-90 Hz sine hit with a pitch drop) for the weight of the skull
  - two to four bone cracks: 2-4 ms clicks with a resonant tail at 1.2-2.6 kHz
  - a short "drip" tail of sparse high clicks
Deterministic per variant (seeded), 44.1 kHz mono, peak-normalised to -3 dBFS.
    python tools/build_head_burst_audio.py
then Godot.exe --headless --path godot --import. Sfx.EVENTS "head_burst" picks one at random; zombie.gd adds
random pitch and level on top.
"""
import numpy as np
import soundfile as sf
from pathlib import Path
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[1]
SFX = ROOT / 'godot/assets/audio/sfx'
SR = 44100


def bandpass(x, lo, hi, order=4):
    sos = butter(order, [lo, hi], btype='band', fs=SR, output='sos')
    return sosfilt(sos, x)


def lowpass(x, hz, order=4):
    sos = butter(order, hz, btype='low', fs=SR, output='sos')
    return sosfilt(sos, x)


def env(n, attack, decay, rng, ragged=0.0):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-np.maximum(0.0, t - attack) / decay)
    if ragged > 0:
        e *= 1.0 - ragged * rng.random(n) * (t > attack)
    return e


def place(buf, clip, at, gain=1.0):
    i = int(at * SR)
    n = min(len(clip), len(buf) - i)
    if n > 0:
        buf[i:i + n] += clip[:n] * gain


def splat_source():
    data, sr = sf.read(SFX / 'pumpkin_splat.ogg')
    if data.ndim > 1:
        data = data.mean(axis=1)
    if sr != SR:
        idx = np.linspace(0, len(data) - 1, int(len(data) * SR / sr))
        data = np.interp(idx, np.arange(len(data)), data)
    return data / (np.abs(data).max() + 1e-9)


def variant(seed, splat):
    rng = np.random.default_rng(seed)
    length = int(1.1 * SR)
    out = np.zeros(length)
    # 1. wet splat: the pumpkin clip, resampled a little and band limited, at a random slice
    rate = rng.uniform(0.82, 1.18)
    idx = np.arange(0, len(splat) - 1, rate)
    wet = np.interp(idx, np.arange(len(splat)), splat)
    wet = bandpass(wet, rng.uniform(140, 260), rng.uniform(3200, 5200))
    place(out, wet * env(len(wet), 0.004, rng.uniform(0.18, 0.3), rng), 0.0, rng.uniform(0.55, 0.8))
    # 2. flesh burst: filtered noise, fast attack, ragged decay
    n = int(rng.uniform(0.22, 0.4) * SR)
    flesh = bandpass(rng.standard_normal(n), rng.uniform(250, 450), rng.uniform(1800, 3000))
    place(out, flesh * env(n, 0.003, rng.uniform(0.05, 0.1), rng, ragged=0.6), rng.uniform(0.0, 0.012), rng.uniform(0.35, 0.55))
    # 3. low thud with a pitch drop
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    f0 = rng.uniform(70, 95)
    thud = np.sin(2 * np.pi * (f0 * t - 30.0 * t * t)) * env(n, 0.002, rng.uniform(0.06, 0.1), rng)
    place(out, lowpass(thud, 220), rng.uniform(0.0, 0.01), rng.uniform(0.5, 0.75))
    # 4. bone cracks
    for k in range(rng.integers(2, 5)):
        n = int(rng.uniform(0.03, 0.07) * SR)
        t = np.arange(n) / SR
        f = rng.uniform(1200, 2600)
        crack = (rng.standard_normal(n) * np.exp(-t / 0.0025) * 1.5 + np.sin(2 * np.pi * f * t) * np.exp(-t / rng.uniform(0.006, 0.015)))
        place(out, crack, rng.uniform(0.0, 0.09), rng.uniform(0.25, 0.5))
    # 5. drips: sparse high clicks in the tail
    for k in range(rng.integers(3, 8)):
        n = int(0.02 * SR)
        t = np.arange(n) / SR
        drip = np.sin(2 * np.pi * rng.uniform(2500, 5000) * t) * np.exp(-t / 0.003)
        place(out, drip, rng.uniform(0.25, 0.95), rng.uniform(0.04, 0.12))
    # soft saturation and level
    out = np.tanh(out * 1.6) / np.tanh(1.6)
    out *= 10 ** (-3 / 20) / (np.abs(out).max() + 1e-9)
    fade = int(0.05 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out.astype(np.float32)


def main():
    splat = splat_source()
    for i in range(1, 6):
        clip = variant(2609 + i, splat)
        path = SFX / f'head_burst_{i}.wav'
        sf.write(path, clip, SR, subtype='PCM_16')
        print('wrote', path.name, f'{len(clip) / SR:.2f}s', f'rms {20 * np.log10(np.sqrt((clip ** 2).mean()) + 1e-9):.1f} dBFS')


if __name__ == '__main__':
    main()
