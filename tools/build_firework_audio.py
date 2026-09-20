"""Bake original, deterministic firework sound layers for positional playback."""
from pathlib import Path
import numpy as np
from scipy import signal
from scipy.io import wavfile

OUT = Path(__file__).resolve().parents[1] / 'godot/assets/audio/fireworks'
RATE = 44100
RNG = np.random.default_rng(7331)

def noise(n, low, high):
    return signal.sosfilt(signal.butter(3, [low, high], btype='bandpass', fs=RATE, output='sos'), RNG.normal(0, 1, n))

def save(name, x):
    x[:220] *= np.linspace(0, 1, 220)
    x[-2200:] *= np.linspace(1, 0, 2200)
    x = np.tanh(x * 1.1)
    x *= .88 / max(.001, np.max(np.abs(x)))
    wavfile.write(OUT / (name + '.wav'), RATE, (x * 32767).astype(np.int16))
    print(name, len(x) / RATE, 'seconds')

def crackles(duration, density):
    n = int(duration * RATE)
    x = np.zeros(n)
    for onset in RNG.uniform(.01, duration - .12, int(duration * density)):
        start = int(onset * RATE)
        t = np.arange(int(.08 * RATE)) / RATE
        tick = noise(len(t), 1300, 12000) * np.exp(-t / RNG.uniform(.003, .011))
        x[start:start+len(t)] += tick * RNG.uniform(.15, .8)
    return x

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    t = np.arange(int(2.5 * RATE)) / RATE
    fuse = noise(len(t), 2400, 11000) * .15 * (.7 + .3 * np.sin(t * 72))
    save('fuse', fuse + crackles(2.5, 85) * .25)
    t = np.arange(int(2.4 * RATE)) / RATE
    envelope = (1 - np.exp(-t * 25)) * np.clip(1 - t / 2.4, 0, 1) ** .45
    whistle = np.sin(2*np.pi*(900*t + 430*t*t)) + .18*np.sin(2*np.pi*(1800*t+860*t*t))
    save('launch', envelope * (noise(len(t), 300, 8500) * .4 + whistle * .13))
    for name, duration, decay in [('burst', 3.2, .42), ('cracker', 1.7, .15)]:
        t = np.arange(int(duration * RATE)) / RATE
        snap = noise(len(t), 800, 16000) * np.exp(-t/.015)
        body = noise(len(t), 45, 950) * np.exp(-t/decay) * 1.9
        thump = np.sin(2*np.pi*(65*t + 16*(1-np.exp(-t*10)))) * np.exp(-t/.18) * .25
        x = snap + body + thump
        tail = noise(len(t), 80, 1400) * np.exp(-t/.75) * .14
        for delay, gain in [(.11, .22), (.29, .11), (.57, .06)]:
            shift = int(delay * RATE)
            x[shift:] += (body + tail)[:-shift] * gain
        save(name, x)
    t = np.arange(int(3.5 * RATE)) / RATE
    save('crackle', crackles(3.5, 100) * np.exp(-t/1.8))

if __name__ == '__main__':
    main()
