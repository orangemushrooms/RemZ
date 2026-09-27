"""Bakes the sounds of the wheels of fortune in the Holzlager (27 Sep 2026) into
godot/assets/audio/sfx/fortune/*.wav. Seeded, so a rerun gives the same files.

tick_1..3  the leather flapper slapping over a brass peg (wood clack + a short leather slap)
coin       a coin rattling into the iron cash box when a spin is paid
win        one brass counter bell
jackpot    the bell rung in a rising run with a shimmer tail (weapon prizes)
lose       a dull wooden knock and a low, falling bell (nothing won)
"""
import os, wave
import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "godot", "assets", "audio", "sfx", "fortune")
rng = np.random.default_rng(2709)


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bell(freq, seconds, decay, partials=((1.0, 1.0), (2.76, 0.45), (5.40, 0.22), (8.93, 0.1))):
    tt = t(seconds)
    y = np.zeros_like(tt)
    for ratio, gain in partials:
        y += gain * np.sin(2 * np.pi * freq * ratio * tt + rng.uniform(0, 6.28)) * np.exp(-tt * decay * (0.6 + ratio * 0.4))
    y *= 1.0 - np.exp(-tt * 900.0)   # a strike, not a click
    return y


def tick(variant):
    tt = t(0.09)
    noise = rng.normal(0, 1, tt.size)
    clack = highpass(lowpass(noise, 5200 + variant * 400), 1400) * np.exp(-tt * 260)
    body = np.sin(2 * np.pi * (980 + variant * 70) * tt) * np.exp(-tt * 90) * 0.55
    thump = np.sin(2 * np.pi * 190 * tt) * np.exp(-tt * 60) * 0.35
    slap = lowpass(noise, 1800) * np.exp(-np.maximum(tt - 0.012, 0) * 140) * (tt > 0.012) * 0.5
    return clack + body + thump + slap


def coin():
    y = np.zeros(int(0.7 * RATE))
    at = 0.0
    for k in range(6):
        freq = rng.uniform(3900, 5600)
        piece = bell(freq, 0.25, 30.0 + k * 6, ((1.0, 1.0), (1.47, 0.6), (2.31, 0.3))) * (0.9 ** k)
        start = int(at * RATE)
        y[start:start + piece.size] += piece[: y.size - start]
        at += rng.uniform(0.035, 0.09) * (1.0 + k * 0.25)
    knock = tick(0)[: int(0.06 * RATE)] * 0.5
    y[: knock.size] += knock
    return y


def win():
    return bell(1318.5, 1.6, 3.2)


def jackpot():
    y = np.zeros(int(3.4 * RATE))
    notes = [1046.5, 1318.5, 1568.0, 2093.0, 1568.0, 2093.0, 2637.0]
    for k, freq in enumerate(notes):
        piece = bell(freq, 1.8, 2.4) * (0.8 if k < len(notes) - 1 else 1.0)
        start = int(k * 0.14 * RATE)
        y[start:start + piece.size] += piece[: y.size - start]
    shimmer = highpass(rng.normal(0, 1, y.size), 6000) * 0.05
    env = np.clip((np.arange(y.size) / RATE - 0.9) * 3, 0, 1) * np.exp(-np.maximum(np.arange(y.size) / RATE - 1.2, 0) * 1.6)
    return y + shimmer * env


def lose():
    knock = tick(2) * 0.8
    tt = t(1.3)
    glide = 330.0 * np.exp(-tt * 0.45)
    phase = 2 * np.pi * np.cumsum(glide) / RATE
    low = (np.sin(phase) + 0.3 * np.sin(2.76 * phase)) * np.exp(-tt * 3.0) * (1.0 - np.exp(-tt * 400)) * 0.5
    y = np.zeros(int(1.4 * RATE))
    y[: knock.size] += knock
    start = int(0.08 * RATE)
    y[start:start + low.size] += low[: y.size - start]
    return y


def save(name, y, peak=0.8):
    y = y / max(1e-6, np.max(np.abs(y))) * peak
    fade = min(len(y), int(0.01 * RATE))
    y[-fade:] *= np.linspace(1, 0, fade)
    data = (y * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data)
    print(name, f"{len(y) / RATE:.2f} s")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for v in range(3):
        save(f"tick_{v + 1}", tick(v), 0.7)
    save("coin", coin(), 0.6)
    save("win", win(), 0.7)
    save("jackpot", jackpot(), 0.8)
    save("lose", lose(), 0.6)
