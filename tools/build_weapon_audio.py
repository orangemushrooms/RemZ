"""Bake weapon sounds into godot/assets/audio/sfx/weapons/.

The eight gun reports now use the user's September 23 MP3s from the project.
Run --recordings-only to update just those, retaining existing mechanical and
impact effects. A full build also replaces the legacy report recipes below with
these supplied recordings before saving; it cannot restore the old shot sounds.

Same house rules as tools/prepare_tower_audio.py and tools/build_titan_audio.py: the user's own
recordings are the organic layer, everything else is synthesised here, nothing is downloaded and
no DSP runs at game time. Originals in the sound library stay untouched.

Sources (unused by the game so far, verified by md5 against godot/assets/audio/sfx):
  Weapons/Anti_Mater_Rifle_Gunshot.mp3  -> Desert Eagle .50 report
  Weapons/Heavy_Machine_Gun_Gunshot.mp3 -> Minigun single report
  Weapons/Sniper_Rifle_Gunshot.mp3      -> lever action crack
  Weapons/Tactical_Rifle_Gunshot.mp3    -> cryo body
  Silenced_Tower.mp3                    -> suppressed MAC-10
  Water_Tower.mp3                       -> cold gas hiss (cryo, flare sizzle)
  anti_tank_tower.mp3                   -> graviton implosion body
  time_stop.mp3                         -> graviton warp tail
  input/audio/Flaregun.mp3 (repo)       -> Leuchtpistole, the user's own flare shot (Sep 2026)

Run: python tools/build_weapon_audio.py [--report]   (numpy, scipy, imageio-ffmpeg)
"""
from pathlib import Path
import argparse
import json
import subprocess
import hashlib
import shutil

import imageio_ffmpeg
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = Path(r"C:\Users\miche\Desktop\Developement\music")
USER_FLARE = ROOT / "input/audio/Flaregun.mp3"   # absolute, so decode() ignores LIBRARY for it
OUT = ROOT / "godot/assets/audio/sfx/weapons"
RATE = 44100
RNG = np.random.default_rng(20260922)
RECORDINGS = {
    'deagle': 'Desert Eagle.mp3', 'flare': 'Flaregun.mp3', 'mac10': 'Mac10.mp3',
    'cryo': 'Kryo_MP.mp3', 'plasma': 'Plasma_Gunshot.mp3', 'lever': 'Unterhebler_shot.mp3',
    'minigun': 'Minigun_Shots_long.mp3', 'graviton': 'Graviton_Gunshot.mp3',
}


# ---------------------------------------------------------------- helpers

def decode(relative):
    raw = subprocess.check_output([
        imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", str(LIBRARY / relative),
        "-f", "f32le", "-ac", "1", "-ar", str(RATE), "pipe:1",
    ])
    return np.frombuffer(raw, np.float32).astype(float)


def norm(x, peak=1.0):
    return x * (peak / max(float(np.max(np.abs(x))), 1e-9))


def filt(x, low=None, high=None, order=3):
    if not low and not high:
        return x
    limits = [low, high] if low and high else (low or high)
    mode = "bandpass" if low and high else "highpass" if low else "lowpass"
    return signal.sosfilt(signal.butter(order, limits, btype=mode, fs=RATE, output="sos"), x)


def envelope(x, window=0.004):
    n = max(1, round(window * RATE))
    return np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same"))


def onset(x, lead=0.012, search_from=0.0):
    """Start of the loudest transient: walk back from the peak to where the level collapses."""
    start = round(search_from * RATE)
    env = envelope(x)
    peak = int(np.argmax(env[start:])) + start
    floor = float(np.max(env[start:])) * 0.06
    i = peak
    while i > start and env[i] > floor:
        i -= 1
    return max(0, min(i, peak) - round(lead * RATE))


def shot(x, length, lead=0.012, search_from=0.0, release=0.05):
    """One report: the loudest transient plus `length` seconds of its own tail."""
    begin = onset(x, lead, search_from)
    clip = x[begin:begin + round(length * RATE)].copy()
    if clip.size < round(length * RATE):
        clip = np.concatenate([clip, np.zeros(round(length * RATE) - clip.size)])
    return fade(clip, 0.001, release)


def body(x, start, length):
    return x[round(start * RATE):round((start + length) * RATE)].copy()


def fade(x, attack=0.002, release=0.05):
    x = x.copy()
    if attack:
        n = min(len(x), round(attack * RATE))
        x[:n] *= np.linspace(0, 1, n)
    if release:
        n = min(len(x), round(release * RATE))
        x[-n:] *= np.linspace(1, 0, n)
    return x


def seconds(n):
    return np.arange(round(n * RATE)) / RATE


def noise(length, low=None, high=None):
    return filt(RNG.normal(0.0, 1.0, round(length * RATE)), low, high)


def sweep(length, start_hz, end_hz, curve=2.0):
    t = seconds(length)
    k = (t / t[-1]) ** curve
    f = start_hz + (end_hz - start_hz) * k
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def decay(length, tau, curve=1.0):
    t = seconds(length)
    return np.exp(-t / tau) ** curve


def mix(*layers):
    n = max(len(x) for x in layers)
    out = np.zeros(n)
    for x in layers:
        out[:len(x)] += x
    return out


def pad(x, before):
    return np.concatenate([np.zeros(round(before * RATE)), x])


def loop(x, crossfade=0.08):
    """Seamless loop: fold the tail back over the head so the wrap is inaudible."""
    n = round(crossfade * RATE)
    blend = np.linspace(0, 1, n)
    seam = x[-n:] * (1 - blend) + x[:n] * blend
    return np.concatenate([seam, x[n:-n]])


def save(name, x, peak=0.82, looped=False):
    x = norm(x, peak)
    path = OUT / (name + ".wav")
    wavfile.write(path, RATE, np.round(x * 32767).astype(np.int16))
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    centroid = float(np.sum(spectrum * freqs) / max(float(np.sum(spectrum)), 1e-9))
    return {
        "file": path.name,
        "seconds": round(len(x) / RATE, 3),
        "rms": round(float(np.sqrt(np.mean(x * x))), 4),
        "centroid_hz": round(centroid),
        "loop": looped,
    }


def replace_recordings(report):
    """Use the supplied September 23 reports, with no synthetic layers or EQ.

    Keep the existing graviton impact separate from its new muzzle recording.
    Originals are untouched; decoded MP3 overshoots get safe PCM headroom.
    """
    OUT.mkdir(parents=True, exist_ok=True)
    impact = OUT / 'graviton_impact.wav'
    if not impact.exists():
        shutil.copyfile(OUT / 'graviton.wav', impact)
    impact_rate, impact_pcm = wavfile.read(impact)
    impact_samples = impact_pcm.astype(float) / 32767.0
    spectrum = np.abs(np.fft.rfft(impact_samples * np.hanning(len(impact_samples))))
    freqs = np.fft.rfftfreq(len(impact_samples), 1 / impact_rate)
    report['graviton_impact'] = {
        'file': impact.name, 'seconds': round(len(impact_samples) / impact_rate, 3),
        'rms': round(float(np.sqrt(np.mean(impact_samples ** 2))), 4),
        'centroid_hz': round(float(np.sum(spectrum * freqs) / max(float(np.sum(spectrum)), 1e-9))),
        'loop': False,
    }
    sources = {}
    for name, filename in RECORDINGS.items():
        source = ROOT / 'godot/assets/audio/sfx' / filename
        x = decode(source)
        # Earliest audible attack, not the loudest later transient (long bursts).
        active = np.flatnonzero(np.abs(x) > np.max(np.abs(x)) * 0.008)
        if not active.size:
            raise ValueError(f'Empty recording: {source}')
        start = max(0, int(active[0]) - round(0.002 * RATE))
        # Retain the natural tail until it falls 54 dB below the recording peak.
        tail = np.flatnonzero(envelope(x) > np.max(envelope(x)) * 0.002)
        end = min(len(x), int(tail[-1]) + round(0.05 * RATE))
        clip = x[start:end]
        if name == 'minigun':
            clip = loop(clip, 0.06)
        else:
            clip = fade(clip, 0.001, 0.025)
        report[name] = save(name, clip, looped=name == 'minigun')
        report[name]['source'] = source.relative_to(ROOT).as_posix()
        report[name]['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        report[name]['trim_start_seconds'] = round(start / RATE, 5)
        sources[name] = report[name]['source'] + (' (continuous fire, loop seam crossfaded)' if name == 'minigun' else ' (silence trimmed, peak normalized)')
    return sources


# ---------------------------------------------------------------- clips

def build():
    OUT.mkdir(parents=True, exist_ok=True)
    report = {}

    anti_materiel = decode("Weapons/Anti_Mater_Rifle_Gunshot.mp3")
    heavy_mg = decode("Weapons/Heavy_Machine_Gun_Gunshot.mp3")
    sniper = decode("Weapons/Sniper_Rifle_Gunshot.mp3")
    tactical = decode("Weapons/Tactical_Rifle_Gunshot.mp3")
    silenced = decode("Silenced_Tower.mp3")
    water = decode("Water_Tower.mp3")
    anti_tank = decode("anti_tank_tower.mp3")
    warp = decode("time_stop.mp3")

    # Desert Eagle .50: the anti materiel report, shortened to a handgun's slap, with a little
    # extra chest from a short sub thump - a hand cannon, not an artillery piece.
    report["deagle"] = save("deagle", mix(
        norm(shot(anti_materiel, 0.55, release=0.22), 1.0),
        norm(np.sin(2 * np.pi * 78 * seconds(0.22)) * decay(0.22, 0.05), 0.35),
    ))

    # Leuchtpistole: the user's own recording. Only the 57 ms of dead air in front of the bang go
    # (they read as a delayed shot); the rest plays as recorded, mono like every other report.
    if USER_FLARE.exists():
        recording = decode(USER_FLARE)
        report["flare"] = save("flare", fade(recording[onset(recording, lead=0.002):], 0.001, 0.05))
    else:
        # Fallback without the recording: hollow breech thump, then the burning star hissing away.
        sizzle = norm(filt(body(water, 0.35, 1.05), 900, 7200), 0.5) * np.linspace(1.0, 0.25, round(1.05 * RATE))
        report["flare"] = save("flare", mix(
            norm(filt(shot(tactical, 0.18, release=0.12), high=520), 0.75),
            norm(np.sin(2 * np.pi * 132 * seconds(0.3)) * decay(0.3, 0.07), 0.5),
            pad(fade(sizzle, 0.02, 0.35), 0.06),
        ))

    # MAC-10 with the can on: the suppressed tower report, trimmed to a single flat clack, plus
    # the bolt rattling in the stamped receiver - what you actually hear at this rate of fire.
    bolt = norm(noise(0.05, 1800, 9000) * decay(0.05, 0.012) * 0.30
                + noise(0.05, 250, 900) * decay(0.05, 0.02) * 0.22) * 0.45
    report["mac10"] = save("mac10", mix(
        norm(shot(silenced, 0.16, release=0.09), 0.9),
        pad(bolt, 0.02),
    ))

    # Kryo-MP: pneumatic discharge. The tactical report is high passed into a dry crack, the cold
    # gas comes off the water tower hiss, and a thin metallic ring sits on top.
    report["cryo"] = save("cryo", mix(
        norm(filt(shot(tactical, 0.13, release=0.07), 900), 0.62),
        norm(filt(body(water, 1.2, 0.26), 2200, 11000) * decay(0.26, 0.07), 0.55),
        norm(np.sin(2 * np.pi * 2650 * seconds(0.2)) * decay(0.2, 0.035), 0.16),
    ))

    # Plasma rifle: a magnetic accelerator letting go. Descending body sweep, an ionised crack at
    # the muzzle and a short ringing tail; fully synthetic so it sits apart from every firearm.
    plasma_core = sweep(0.34, 1150, 130, curve=1.7) * decay(0.34, 0.075)
    plasma_snap = noise(0.09, 1400, 12000) * decay(0.09, 0.016)
    plasma_ring = (np.sin(2 * np.pi * 620 * seconds(0.4)) + 0.6 * np.sin(2 * np.pi * 933 * seconds(0.4))) * decay(0.4, 0.1)
    report["plasma"] = save("plasma", mix(norm(plasma_core, 1.0), norm(plasma_snap, 0.5), norm(plasma_ring, 0.3)))

    # Overheat: the barrel dumping its heat through the vents between shots.
    vent = norm(noise(0.7, 400, 6500) * (decay(0.7, 0.28) * 0.9 + 0.1), 0.8)
    report["plasma_vent"] = save("plasma_vent", mix(
        vent,
        norm(np.sin(2 * np.pi * 1450 * seconds(0.5)) * decay(0.5, 0.16), 0.18),
    ))

    # Unterhebelrepetierer: the rifle crack, dry and quick.
    report["lever"] = save("lever", norm(shot(sniper, 0.62, release=0.3), 1.0))

    # ... and the lever itself: two metal clacks, the way the action is thrown and closed.
    clack_a = filt(noise(0.06, 900, 6000) * decay(0.06, 0.010), 250) * 1.0
    clack_b = filt(noise(0.07, 600, 4500) * decay(0.07, 0.014), 200) * 0.85
    report["lever_cycle"] = save("lever_cycle", mix(
        norm(clack_a, 0.9),
        pad(norm(clack_b, 0.75), 0.13),
        norm(np.sin(2 * np.pi * 320 * seconds(0.25)) * decay(0.25, 0.05), 0.1),
    ))

    # Minigun: ONE report, cut hard. At twenty rounds a second anything longer turns to mud.
    report["minigun"] = save("minigun", mix(
        norm(shot(heavy_mg, 0.105, lead=0.006, release=0.045), 1.0),
        norm(np.sin(2 * np.pi * 95 * seconds(0.09)) * decay(0.09, 0.025), 0.3),
    ), peak=0.78)

    # The motor: a rising whine into a steady loop, and the run-down when the trigger is let go.
    def motor(length, start_hz, end_hz, curve=1.6):
        t = seconds(length)
        k = (t / t[-1]) ** curve
        f = start_hz + (end_hz - start_hz) * k
        phase = 2 * np.pi * np.cumsum(f) / RATE
        gear = signal.sawtooth(phase) * 0.55 + signal.sawtooth(phase * 2.0) * 0.25
        whir = filt(RNG.normal(0, 1, len(t)), 700, 5200) * (0.25 + 0.35 * k)
        return gear * (0.35 + 0.65 * k) + whir

    report["minigun_spinup"] = save("minigun_spinup", fade(motor(0.75, 22, 165), 0.03, 0.02))
    steady = motor(1.0, 165, 165, curve=1.0)
    report["minigun_loop"] = save("minigun_loop", loop(steady, 0.12), peak=0.6, looped=True)
    report["minigun_spindown"] = save("minigun_spindown", fade(motor(1.1, 165, 18, curve=0.7), 0.02, 0.25))

    # Graviton cannon: space folding in on itself. The anti tank body gives the physical slam, the
    # warp recording the unnatural tail, and a sub drop does the punch in the chest.
    report["graviton"] = save("graviton", mix(
        norm(shot(anti_tank, 1.25, release=0.5), 1.0),
        norm(filt(body(warp, 0.4, 1.6), 60, 3200) * (decay(1.6, 0.55) * 0.85 + 0.15), 0.55),
        norm(sweep(0.55, 105, 32, curve=0.8) * decay(0.55, 0.16), 0.75),
    ))

    # The cell spinning up before it fires.
    report["graviton_charge"] = save("graviton_charge", fade(mix(
        norm(sweep(0.6, 90, 720, curve=1.4) * (0.25 + 0.75 * (seconds(0.6) / 0.6)), 0.8),
        norm(noise(0.6, 1200, 7000) * (seconds(0.6) / 0.6) ** 2, 0.3),
    ), 0.05, 0.04))

    # A zombie freezing solid: crystal ticks over a cold breath.
    ticks = np.zeros(round(0.55 * RATE))
    for at in RNG.uniform(0.0, 0.42, 22):
        i = round(at * RATE)
        tick = noise(0.035, 2600, 13000) * decay(0.035, 0.006)
        ticks[i:i + len(tick)] += tick * RNG.uniform(0.35, 1.0)
    report["cryo_freeze"] = save("cryo_freeze", mix(
        norm(ticks, 0.9),
        norm(noise(0.55, 300, 2400) * decay(0.55, 0.18), 0.35),
    ))

    recording_sources = replace_recordings(report)
    (OUT / "sources.json").write_text(json.dumps({
        "built_by": "tools/build_weapon_audio.py",
        "library": str(LIBRARY),
        "sources": {
            "deagle": "Weapons/Anti_Mater_Rifle_Gunshot.mp3 + synthesised sub",
            "flare": ("input/audio/Flaregun.mp3 (the user's recording, leading silence trimmed)" if USER_FLARE.exists()
                      else "Weapons/Tactical_Rifle_Gunshot.mp3 (high passed) + Water_Tower.mp3 sizzle + synthesised thump"),
            "mac10": "Silenced_Tower.mp3 + synthesised bolt",
            "cryo": "Weapons/Tactical_Rifle_Gunshot.mp3 + Water_Tower.mp3 gas + synthesised ring",
            "plasma": "fully synthesised", "plasma_vent": "fully synthesised",
            "lever": "Weapons/Sniper_Rifle_Gunshot.mp3", "lever_cycle": "fully synthesised",
            "minigun": "Weapons/Heavy_Machine_Gun_Gunshot.mp3 + synthesised sub",
            "minigun_spinup": "fully synthesised", "minigun_loop": "fully synthesised",
            "minigun_spindown": "fully synthesised",
            "graviton": "anti_tank_tower.mp3 + time_stop.mp3 + synthesised sub drop",
            "graviton_charge": "fully synthesised", "cryo_freeze": "fully synthesised",
            "graviton_impact": "original graviton explosion: anti_tank_tower.mp3 + time_stop.mp3 + synthesised sub drop",
            **recording_sources,
        },
        "clips": report,
    }, indent=2), encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--recordings-only", action="store_true", help="Replace only the eight reports with the new project recordings; keep existing mechanical/effect sounds")
    args = parser.parse_args()
    if args.recordings_only:
        provenance = json.loads((OUT / 'sources.json').read_text(encoding='utf-8'))
        clips = provenance['clips']
        provenance['sources'].update(replace_recordings(clips))
        provenance['sources']['graviton_impact'] = 'original graviton explosion: anti_tank_tower.mp3 + time_stop.mp3 + synthesised sub drop'
        (OUT / 'sources.json').write_text(json.dumps(provenance, indent=2), encoding='utf-8')
    else:
        clips = build()
    for name, info in clips.items():
        print("%-18s %5.3f s  rms %.3f  centroid %5d Hz%s" % (
            name, info["seconds"], info["rms"], info["centroid_hz"], "  [loop]" if info["loop"] else ""))
    print(len(clips), "clips ->", OUT)
