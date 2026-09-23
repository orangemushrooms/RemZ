"""Prepare user-provided turret recordings for synchronized positional playback.

Original MP3s stay untouched. Requires numpy, scipy and imageio-ffmpeg.
"""
from pathlib import Path
import hashlib
import json
import subprocess

import imageio_ffmpeg
import numpy as np
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "godot/assets/audio/sfx"
OUT = SOURCE / "towers"
RATE = 44100


def decode(name):
    raw = subprocess.check_output([
        imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", str(SOURCE / name),
        "-f", "f32le", "-ac", "1", "-ar", str(RATE), "pipe:1",
    ])
    return np.frombuffer(raw, np.float32).astype(float)


def cut(x, start, end):
    return x[round(start * RATE):round(end * RATE)].copy()


def save(name, x, attack=0.002, release=0.04):
    if attack:
        n = round(attack * RATE)
        x[:n] *= np.linspace(0, 1, n)
    if release:
        n = round(release * RATE)
        x[-n:] *= np.linspace(1, 0, n)
    # Preserve dynamics, matching headroom rather than compressing the recordings.
    x *= 0.75 / max(float(np.max(np.abs(x))), 1e-9)
    wavfile.write(OUT / (name + ".wav"), RATE, np.round(x * 32767).astype(np.int16))
    return {"seconds": round(len(x) / RATE, 4), "peak": round(float(np.max(np.abs(x))), 4)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    names = ["flamethrower_tower.mp3", "Machinegun_Tower.mp3", "Mortar_Tower.mp3", "Teslacoil_Tower.mp3", "Sentinel_Tower.mp3"]
    flame, mg, mortar, tesla, sentinel = [decode(name) for name in names]
    # Crossfade the stable flame body across the wrap; no silent MP3 padding in the loop.
    loop = cut(flame, 0.26, 1.16)
    n = round(0.09 * RATE)
    blend = np.linspace(0, 1, n)
    seam = loop[-n:] * (1 - blend) + loop[:n] * blend
    loop = np.concatenate([loop[n:-n], seam])
    clips = {"flame_loop": save("flame_loop", loop, 0, 0)}
    # Last MG report includes the recording's natural outdoor decay, but no next shot.
    clips["mg42_shot"] = save("mg42_shot", cut(mg, 3.385, 4.08), release=0.08)
    clips["mortar_shot"] = save("mortar_shot", cut(mortar, 0.30, 2.28), release=0.16)
    # One short electrical discharge per visible bolt; no overlapping 2.6-second buzzes.
    clips["tesla_shot"] = save("tesla_shot", cut(tesla, 0.185, 0.735), attack=0.005, release=0.18)
    # Remove the 61 ms lead-in; fade the quiet reverb before the recording's noise floor.
    # Three voices retain this decay even at the level-three Sentinel firing rate.
    clips["sentinel_shot"] = save("sentinel_shot", cut(sentinel, 0.061, 0.56), attack=0.001, release=0.10)
    manifest = {"sources": {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() for name in names},
                "clips": clips, "sample_rate": RATE, "channels": 1}
    (OUT / "sources.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(clips, indent=2))


if __name__ == "__main__":
    main()
