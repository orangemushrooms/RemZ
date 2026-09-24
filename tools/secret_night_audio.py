"""Deterministic original 140 BPM guide loop and rain, replaced by the user's song later."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / 'godot/assets/audio'
RATE = 22050

def write(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', int(max(-0.95, min(0.95, x)) * 32767)) for x in samples))

def goa():
    beat = 60 / 140
    rng = random.Random(510)
    notes = [55, 55, 65.406, 55, 73.416, 65.406, 82.407, 65.406]
    for i in range(round(RATE * beat * 32)):
        t = i / RATE
        b = t % beat
        kick = math.sin(2 * math.pi * (48 * b + 8 * (1 - math.exp(-b * 35)))) * math.exp(-b * 19)
        sixteenth = (t / (beat / 4)) % 1
        note = notes[int(t / (beat / 2)) % len(notes)]
        bass = (math.sin(2 * math.pi * note * t) + 0.25 * math.sin(4 * math.pi * note * t)) * math.exp(-sixteenth * 4) * min(1, b * 35)
        hat = rng.uniform(-1, 1) * math.exp(-((t + beat / 2) % (beat / 2)) * 85)
        arp = math.sin(2 * math.pi * note * 8 * t + math.sin(t * 4)) * math.exp(-sixteenth * 5)
        yield 0.38 * kick + 0.22 * bass + 0.06 * hat + 0.05 * arp

def rain():
    rng = random.Random(514)
    previous = 0
    for _ in range(RATE * 8):
        noise = rng.uniform(-1, 1)
        previous = previous * 0.65 + noise * 0.35
        yield previous * 0.8 + noise * 0.09

if __name__ == '__main__':
    write(ROOT / 'music/secret_goa_placeholder.wav', goa())
    write(ROOT / 'sfx/secret_rain.wav', rain())
