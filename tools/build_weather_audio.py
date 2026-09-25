"""Synthetic sound effects of the 26 Sep 2026 batch, baked into godot/assets/audio/sfx/*.wav (44.1 kHz mono,
peak -3 dBFS, deterministic per file). The user's library has no recordings for these, so they are built
from noise, resonators and envelopes like build_head_burst_audio.py:
  thunder_1..3     a distant roll: low rumble with a sharp crack, long ragged decay (weather.gd storms)
  screamer_call    the screamer's shriek that calls the horde: a rising, wavering scream 600 -> 1500 Hz
  acid_spit        the spitter's cough-and-hiss when the glob leaves the mouth
  acid_splash      the glob bursting into a sizzling pool
  helmet_ping      a bullet ringing off a steel helmet
  radio_ping       the callout radio: two clicks and a short beep
    python tools/build_weather_audio.py
then Godot.exe --headless --path godot --import.
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


def highpass(x, hz, order=2):
    sos = butter(order, hz, btype='high', fs=SR, output='sos')
    return sosfilt(sos, x)


def env(n, attack, decay, rng=None, ragged=0.0):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-np.maximum(0.0, t - attack) / decay)
    if ragged > 0 and rng is not None:
        e *= 1.0 - ragged * rng.random(n) * (t > attack)
    return e


def normalise(x, peak_db=-3.0):
    peak = np.max(np.abs(x)) or 1.0
    return x / peak * (10 ** (peak_db / 20.0))


def write(name, x):
    x = normalise(x.astype(np.float64))
    fade = int(SR * 0.01)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    sf.write(str(SFX / (name + '.wav')), x.astype(np.float32), SR, subtype='PCM_16')
    print('wrote', name, '%.2f s' % (len(x) / SR))


def thunder(seed):
    rng = np.random.default_rng(seed)
    length = 5.5 + rng.random() * 2.5
    n = int(length * SR)
    t = np.arange(n) / SR
    # the crack: a short bright burst at the start, delayed by the "distance" (0 .. 0.6 s)
    delay = int((0.05 + rng.random() * 0.5) * SR)
    crack = bandpass(rng.standard_normal(n), 400, 5000) * env(n, 0.004, 0.09 + rng.random() * 0.08, rng, 0.3)
    crack = np.roll(crack, delay) * (0.6 + rng.random() * 0.4)
    crack[:delay] = 0.0
    # the roll: slow rumble with several rolling swells and a very long decay
    rumble = lowpass(rng.standard_normal(n), 90 + rng.random() * 60)
    swells = np.ones(n)
    for k in range(int(3 + rng.random() * 5)):
        centre = rng.random() * length * 0.8
        width = 0.2 + rng.random() * 0.6
        swells += (0.4 + rng.random() * 1.2) * np.exp(-((t - centre) / width) ** 2)
    roll = rumble * swells * env(n, 0.15 + rng.random() * 0.3, 1.4 + rng.random() * 1.2, rng, 0.15)
    roll = np.roll(roll, delay)
    roll[:delay] = 0.0
    # a little mid-band body so it reads on small speakers
    body = bandpass(rng.standard_normal(n), 120, 600) * env(n, 0.3, 1.0, rng, 0.2) * 0.35
    body = np.roll(body, delay)
    body[:delay] = 0.0
    return crack * 0.8 + roll * 1.6 + body


def screamer_call(seed=11):
    rng = np.random.default_rng(seed)
    length = 2.2
    n = int(length * SR)
    t = np.arange(n) / SR
    # pitch: a rise, a wavering hold, a falling tail
    f = 620 + 900 * np.clip(t / 0.45, 0, 1) - 300 * np.clip((t - 1.5) / 0.7, 0, 1)
    f *= 1.0 + 0.045 * np.sin(2 * np.pi * 11.0 * t) + 0.02 * np.sin(2 * np.pi * 3.3 * t)
    phase = 2 * np.pi * np.cumsum(f) / SR
    # a harsh voice: saw-like harmonics with a breathy noise layer
    voice = sum(np.sin(phase * h) / h for h in range(1, 9))
    breath = bandpass(rng.standard_normal(n), 900, 4000) * 0.35
    formant = bandpass(voice, 500, 3500)
    e = env(n, 0.06, 0.9, rng, 0.05) * (1.0 - 0.6 * np.clip((t - 1.6) / 0.6, 0, 1))
    return (formant * 0.9 + voice * 0.3 + breath) * e


def acid_spit(seed=21):
    rng = np.random.default_rng(seed)
    n = int(0.75 * SR)
    t = np.arange(n) / SR
    cough = lowpass(rng.standard_normal(n), 500) * env(n, 0.01, 0.07, rng, 0.3)
    hiss = bandpass(rng.standard_normal(n), 1500, 7000) * env(n, 0.05, 0.25, rng, 0.2)
    gurgle = np.sin(2 * np.pi * (90 - 40 * t) * t) * env(n, 0.02, 0.18)
    return cough * 1.2 + hiss * 0.5 + gurgle * 0.6


def acid_splash(seed=31):
    rng = np.random.default_rng(seed)
    n = int(1.6 * SR)
    splat = bandpass(rng.standard_normal(n), 200, 2500) * env(n, 0.004, 0.08, rng, 0.4)
    sizzle = bandpass(rng.standard_normal(n), 2500, 9000) * env(n, 0.05, 0.8, rng, 0.35) * 0.5
    bubbles = np.zeros(n)
    for k in range(18):
        at = int((0.1 + rng.random() * 1.2) * SR)
        length = int(0.03 * SR)
        f = 300 + rng.random() * 900
        seg = np.sin(2 * np.pi * f * np.arange(length) / SR) * env(length, 0.002, 0.008)
        bubbles[at:at + length] += seg * 0.4
    return splat + sizzle + bubbles


def helmet_ping(seed=41):
    rng = np.random.default_rng(seed)
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    ring = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / d) for f, d in [(2350, 0.18), (3900, 0.12), (5600, 0.07), (1180, 0.25)])
    hit = bandpass(rng.standard_normal(n), 800, 6000) * env(n, 0.001, 0.02)
    return ring * 0.7 + hit * 1.0


def radio_ping(seed=51):
    rng = np.random.default_rng(seed)
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    clicks = np.zeros(n)
    for at in (0.0, 0.045):
        start = int(at * SR)
        length = int(0.012 * SR)
        clicks[start:start + length] += bandpass(rng.standard_normal(length), 1200, 6000) * env(length, 0.0005, 0.004)
    beep = np.sin(2 * np.pi * 1760 * t) * ((t > 0.12) & (t < 0.24)) * env(n, 0.005, 0.3)
    static = bandpass(rng.standard_normal(n), 2000, 5000) * env(n, 0.01, 0.15) * 0.15
    return clicks * 1.2 + beep * 0.5 + static


if __name__ == '__main__':
    # 25 Sep 2026 evening: the user replaced thunder_1..3, screamer_call, acid_splash and helmet_ping with
    # real recordings (mp3 in the sfx folder, sfx.gd loads .mp3 before .wav). Only the two that stayed
    # synthetic are baked by default; --all rebuilds every fallback as .wav next to the recordings.
    import sys
    everything = '--all' in sys.argv
    if everything:
        for i in range(3):
            write('thunder_%d' % (i + 1), thunder(100 + i))
        write('screamer_call', screamer_call())
        write('acid_splash', acid_splash())
        write('helmet_ping', helmet_ping())
    write('acid_spit', acid_spit())
    write('radio_ping', radio_ping())
