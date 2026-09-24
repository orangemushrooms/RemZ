"""Prepare the supplied drone_flying recording; preserve its one-time spin-up."""
from pathlib import Path
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "godot/assets/audio/sfx/drone_flying.mp3"
OUTPUT = SOURCE.with_name("drone_flying_motor.wav")
TRIM_SECONDS = 1.18  # Leave 40 ms ahead of the first audible rotor onset.
LOOP_SOURCE_SECONDS = 3.5
END_SECONDS = 17.7
CROSSFADE_SECONDS = 0.15


def prepare():
    audio, rate = sf.read(SOURCE, always_2d=True)
    mono = audio.mean(axis=1)
    start, begin, end, fade = [round(t * rate) for t in
                             (TRIM_SECONDS, LOOP_SOURCE_SECONDS, END_SECONDS, CROSSFADE_SECONDS)]
    # The last samples approach the samples immediately BEFORE loop_begin.
    # Consequently both the first pass and every wrap have a continuous join.
    result = mono[start:end].copy()
    blend = np.linspace(0, 1, fade)
    result[-fade:] = result[-fade:] * (1-blend) + mono[begin-fade:begin] * blend
    rms = np.sqrt(np.mean(result[begin-start:] ** 2))
    gain = min(10 ** (-20/20) / rms, 0.9 / np.max(np.abs(result)))
    result *= gain
    sf.write(OUTPUT, result, rate, subtype="PCM_16")
    print(f"{OUTPUT.name}: {len(result)/rate:.3f}s, loop at {(begin-start)/rate:.3f}s, "
          f"{rate}Hz mono, gain {20*np.log10(gain):.2f}dB")


if __name__ == "__main__":
    prepare()
