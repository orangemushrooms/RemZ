"""Bake the class-weapon recordings of 30 Sep 2026 into godot/assets/audio/sfx/weapons/.

The user's own MP3s live in input/audio/weapons/ (raw, never played by the game). Same house rules as
build_weapon_audio.py, whose helpers this reuses: the recording is the organic layer, anything added is
synthesised here, no DSP at game time, originals untouched.

  MP5.mp3, Tommy_Gun.mp3       bursts of six to seven rounds at ~900 rpm. One round is cut out (the second
                               shot, whose attack is complete and which the next shot ends exactly one period
                               later) and given the burst's own after-tail plus a short synthetic room decay,
                               so a single tap sounds like a shot and automatic fire stacks back into the burst.
  AR_15.mp3, SIG P226.mp3,     single reports: leading silence trimmed, natural tail kept until 54 dB under
  Nighthawk.mp3, Titan_Breaker the peak (at most 1.4 s), peak normalised to 0.82 like the September 23 set.
  Spas 12.mp3, Sawed_Off_...   distant, soft recordings without a real attack: a synthetic muzzle crack and a
                               sub thump open the clip, the recording follows as body and tail.

The suggested Weapons.DEFS sfx_db per clip is printed at the end: it levels the loudest 120 ms of the new clip
against the old clip of the same weapon family (pistol.mp3, smg.mp3, ak47.mp3, shotgun.mp3, revolver.mp3) at
that family's current sfx_db, so a new gun is neither a whisper nor a wall of sound next to the old ones.

Run: python tools/build_class_weapon_audio.py [--report]      (numpy, scipy, imageio-ffmpeg)
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_weapon_audio import RATE, OUT, ROOT, decode, envelope, fade, filt, mix, noise, norm, onset, pad, save, seconds, decay  # noqa: E402

SRC = ROOT / "input/audio/weapons"
SFX = ROOT / "godot/assets/audio/sfx"

# clip name -> (recording, kind). Kinds: burst | shot | soft (needs a synthetic attack).
RECORDINGS = {
    "mp5": ("MP5.mp3", "burst"),
    "tommy_gun": ("Tommy_Gun.mp3", "burst"),
    "ar15": ("AR_15.mp3", "shot"),
    "sig_p226": ("SIG P226.mp3", "shot"),
    "nighthawk": ("Nighthawk.mp3", "shot"),
    "titanbreaker": ("Titan_Breaker.mp3", "shot"),
    "spas12": ("Spas 12.mp3", "soft"),
    "sawed_off": ("Sawed_Off_Shotgun.mp3", "soft"),
}
# loudness reference per clip: (old sfx file stem in assets/audio/sfx, its Weapons.DEFS sfx_db, offset dB)
REFERENCE = {
    "mp5": ("smg", 0.0, 0.0),
    "tommy_gun": ("smg", 0.0, 1.0),
    "ar15": ("ak47", -17.0, -1.0),
    "sig_p226": ("pistol", 2.0, 0.0),
    "nighthawk": ("pistol", 2.0, 3.0),
    "titanbreaker": ("revolver", -6.0, 0.0),
    "spas12": ("shotgun", -7.0, 0.0),
    "sawed_off": ("shotgun", -7.0, 1.0),
}


def loudest_window(x, length=0.12):
    """RMS (dBFS) of the loudest `length` seconds: what the ear takes as the level of a shot."""
    n = round(length * RATE)
    if len(x) <= n:
        return 20 * np.log10(max(float(np.sqrt(np.mean(x * x))), 1e-9))
    power = np.convolve(x * x, np.ones(n) / n, mode="valid")
    return 20 * np.log10(max(float(np.sqrt(np.max(power))), 1e-9))


def trim(x, lead=0.002, floor_db=54.0, max_len=1.4):
    """Attack to the front, natural tail kept until it sits floor_db under the peak, capped at max_len.

    The start is the report's own onset (walk back from the loudest transient to where the level
    collapses, build_weapon_audio.onset): the SIG recording carries 35 ms of room noise above a plain
    amplitude threshold, which read as a delayed shot."""
    start = onset(x, lead=lead)
    env = envelope(x)
    tail = np.flatnonzero(env > np.max(env) * 10 ** (-floor_db / 20))
    end = min(len(x), int(tail[-1]) + round(0.05 * RATE), start + round(max_len * RATE))
    return x[start:end], start


def round_peaks(x, min_gap=0.04):
    """Peaks of the individual rounds of a burst (1.5 ms envelope, at least min_gap apart)."""
    from scipy.signal import find_peaks
    env = envelope(x, 0.0015)
    idx, _ = find_peaks(env, distance=round(min_gap * RATE), height=np.max(env) * 0.35, prominence=np.max(env) * 0.2)
    return np.array(idx), env


def one_round(x, name):
    """One report out of a burst, with the burst's own after-tail and a short synthetic room decay.

    The cut runs from the quietest point before the second round's peak to the quietest point before the
    third: an onset found by walking back from a peak lands mid-attack of the next round, and the first
    attempt at this clip carried the following round's first 8 ms as a double tap."""
    x = filt(x, low=40.0, order=2)   # both bursts carry a 15 Hz wobble under the shots
    peaks, env = round_peaks(x)
    if len(peaks) < 3:
        raise ValueError(f"{name}: only {len(peaks)} rounds found in the burst")
    smooth = envelope(x, 0.006)
    valley = lambda a, b: a + int(np.argmin(smooth[a:b]))   # quietest point between two peaks
    k = 1  # the second round: complete attack, the third round bounds its decay
    begin = valley(peaks[k - 1], peaks[k])
    end = valley(peaks[k], peaks[k + 1])
    period = int(np.median(np.diff(peaks)))
    attack = x[begin:end].copy()
    # the burst's decay after the last round, taken from the same offset past its peak that the cut
    # ends at past the second one, so the timeline continues where the single round's clip stops
    last = peaks[-1]
    after = x[last + (end - peaks[k]):].copy()
    seam = round(0.004 * RATE)
    if len(after) > seam:
        blend = np.linspace(0, 1, seam)
        attack[-seam:] = attack[-seam:] * (1 - blend) + after[:seam] * blend
        body = np.concatenate([attack, after[seam:]])
    else:
        body = attack
    # a small room: the report's own last 30 ms, smeared into a 220 ms decaying noise bed at -20 dB
    room = noise(0.26, 180, 5200) * decay(0.26, 0.055)
    room = norm(room, float(np.max(np.abs(attack))) * 0.10)
    clip = mix(body, pad(room, len(attack) / RATE - 0.01))
    return fade(clip, 0.0005, 0.04), {"rounds": int(len(peaks)), "period_ms": round(period / RATE * 1000, 1), "rpm": round(60 / (period / RATE)), "round_used": k + 1, "cut_ms": round((end - begin) / RATE * 1000, 1)}


def soft_shot(x):
    """Recording without an attack: synthetic crack and sub thump in front, the recording as body/tail."""
    x, _ = trim(x, max_len=1.6)
    crack = norm(noise(0.014, 900, 9000) * decay(0.014, 0.0028), 0.95)
    thump = norm(np.sin(2 * np.pi * 68 * seconds(0.14)) * decay(0.14, 0.032), 0.7)
    knock = norm(noise(0.05, 120, 900) * decay(0.05, 0.012), 0.55)
    body = norm(x, 0.55) * np.concatenate([np.linspace(0.6, 1.0, round(0.008 * RATE)), np.ones(len(x) - round(0.008 * RATE))])
    return fade(mix(crack, thump, knock, pad(body, 0.003)), 0.0003, 0.05)


def build(report_only=False):
    OUT.mkdir(parents=True, exist_ok=True)
    provenance = json.loads((OUT / "sources.json").read_text(encoding="utf-8")) if (OUT / "sources.json").exists() else {"sources": {}, "clips": {}}
    clips = provenance.setdefault("clips", {})
    sources = provenance.setdefault("sources", {})
    suggestions = {}
    for name, (filename, kind) in RECORDINGS.items():
        source = SRC / filename
        x = decode(source)
        notes = {}
        if kind == "burst":
            clip, notes = one_round(x, name)
        elif kind == "soft":
            clip = soft_shot(x)
        else:
            clip, start = trim(x)
            clip = fade(clip, 0.001, 0.025)
            notes = {"trim_start_seconds": round(start / RATE, 5)}
        if not report_only:
            info = save(name, clip)
            info.update(notes)
            info["source"] = source.relative_to(ROOT).as_posix()
            info["source_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
            info["kind"] = kind
            clips[name] = info
            sources[name] = info["source"] + {
                "burst": " (one round cut from the burst, own after-tail, synthesised room decay)",
                "soft": " (synthesised crack and thump in front, recording as body)",
                "shot": " (silence trimmed, peak normalized)",
            }[kind]
        # level against the family's old clip
        ref_stem, ref_db, offset = REFERENCE[name]
        ref = decode(SFX / (ref_stem + ".mp3"))
        old_level = loudest_window(ref) + ref_db
        new_level = loudest_window(norm(clip, 0.82))
        suggestions[name] = round(old_level + offset - new_level, 1)
        print("%-12s %-22s %s  %5.3f s  old %-8s %6.1f dB  new %6.1f dB  -> sfx_db %5.1f  %s" % (
            name, filename, kind, len(clip) / RATE, ref_stem, old_level, new_level, suggestions[name], notes))
    if not report_only:
        provenance["class_weapons"] = {"built_by": "tools/build_class_weapon_audio.py", "recordings": "input/audio/weapons/", "sfx_db": suggestions}
        (OUT / "sources.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    return suggestions


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true", help="analyse and print the levels without writing")
    args = parser.parse_args()
    build(args.report)
