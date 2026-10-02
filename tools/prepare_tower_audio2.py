"""The sounds of the eight towers of 2 Oct 2026 -> godot/assets/audio/sfx/towers/ (second block).

Same house rules as prepare_tower_audio.py and build_weapon_audio.py: the user's library is the organic layer,
anything else is synthesised here, nothing runs at game time, originals stay untouched.

  sniper_shot     Weapons/Sniper_Rifle_Gunshot.mp3  the rifle crack with its tail
  rocket_salvo    anti_tank_tower.mp3               four launch whooshes 110 ms apart cut from the launch body
  harpoon_shot    Shotgun_Tower.mp3                 the thump, plus a synthesised cable whirr and winch click
  frost_loop      Water_Tower.mp3                   the hiss, looped like the flamethrower's bed
  graviton_pulse  time_stop.mp3 + synth             the warp tail of the recording under a sub drop
  siren_wail      synthesised                       an air raid siren: 12 s rise / fall sweep with motor grit
  searchlight_lock synthesised                      relay clack and a short carbon arc hum
  supply_pulse    Reload.mp3 + click.mp3            the magazine clink and a latch click

Run: python tools/prepare_tower_audio2.py        (numpy, scipy, imageio-ffmpeg)
"""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_weapon_audio import RATE, decode, envelope, fade, filt, loop, mix, noise, norm, onset, pad, seconds, decay, sweep  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = Path(r"C:\Users\miche\Desktop\Developement\music")
OUT = ROOT / "godot/assets/audio/sfx/towers"
RNG = np.random.default_rng(20261002)


def save(name, x, peak=0.75):
    x = norm(x, peak)
    wavfile.write(OUT / (name + ".wav"), RATE, np.round(x * 32767).astype(np.int16))
    return {"seconds": round(len(x) / RATE, 4), "peak": round(float(np.max(np.abs(x))), 4)}


def shot(x, length, lead=0.004, release=0.06):
    begin = onset(x, lead)
    clip = x[begin:begin + round(length * RATE)].copy()
    if clip.size < round(length * RATE):
        clip = np.concatenate([clip, np.zeros(round(length * RATE) - clip.size)])
    return fade(clip, 0.001, release)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sources = {}
    clips = {}

    def use(relative):
        sources[relative] = hashlib.sha256((LIBRARY / relative).read_bytes()).hexdigest()
        return decode(relative)

    # Sniper nest: the rifle crack, dry and long.
    rifle = use("Weapons/Sniper_Rifle_Gunshot.mp3")
    clips["sniper_shot"] = save("sniper_shot", shot(rifle, 1.2, release=0.3))

    # Rocket pod: the launch body of the anti tank recording, four times at the salvo's own cadence.
    launch = use("anti_tank_tower.mp3")
    one = fade(shot(launch, 0.42, release=0.18), 0.002, 0.18)
    whoosh = norm(filt(noise(0.45, 300, 4200) * decay(0.45, 0.11), 150), 0.5)
    salvo = np.zeros(round((0.11 * 3 + 0.9) * RATE))
    for i in range(4):
        piece = mix(one * (0.85 + 0.15 * RNG.random()), whoosh * 0.6)
        at = round(0.11 * i * RATE)
        salvo[at:at + len(piece)] += piece
    clips["rocket_salvo"] = save("rocket_salvo", fade(salvo, 0.001, 0.2))

    # Harpoon launcher: the thump of the shotgun tower recording, then the cable paying out off the drum.
    thump = use("Shotgun_Tower.mp3")
    whirr = norm(filt(noise(0.7, 900, 5200) * (0.3 + 0.7 * np.abs(np.sin(2 * np.pi * 38 * seconds(0.7)))) * decay(0.7, 0.4), 500), 0.35)
    click = norm(filt(noise(0.05, 1500, 7000) * decay(0.05, 0.008), 800), 0.5)
    clips["harpoon_shot"] = save("harpoon_shot", mix(shot(thump, 0.55, release=0.2), pad(whirr, 0.08), pad(click, 0.72)))

    # Frost cannon: the water tower hiss as a seamless bed, high passed into dry cold gas.
    hiss = use("Water_Tower.mp3")
    bed = filt(hiss[round(0.35 * RATE):round(1.35 * RATE)], 700, 9000)
    clips["frost_loop"] = save("frost_loop", loop(bed, 0.1), peak=0.6)

    # Graviton trap: the warp recording's tail under a falling sub, the trap closing.
    warp = use("time_stop.mp3")
    body = filt(warp[round(0.6 * RATE):round(1.9 * RATE)], 70, 3500) * (decay(1.3, 0.45) * 0.85 + 0.15)
    drop = sweep(0.7, 140, 28, curve=0.9) * decay(0.7, 0.2)
    clips["graviton_pulse"] = save("graviton_pulse", fade(mix(norm(body, 0.7), norm(drop, 0.8)), 0.003, 0.3))

    # Decoy siren: a two tone air raid wail, rising for 2.5 s, holding, falling, with the motor's grit; 12 s.
    length = 12.0
    t = seconds(length)
    pitch = np.interp(t, [0, 2.5, 8.5, 12.0], [220, 640, 640, 180])
    phase = 2 * np.pi * np.cumsum(pitch) / RATE
    tone = np.sin(phase) * 0.6 + np.sin(phase * 2) * 0.25 + np.sin(phase * 3) * 0.1
    grit = filt(RNG.normal(0, 1, len(t)), 400, 3000) * 0.08 * (pitch / 640)
    beat = 0.85 + 0.15 * np.sin(2 * np.pi * 5.5 * t)
    wail = (tone + grit) * beat * np.interp(t, [0, 0.4, 9.5, 12.0], [0.0, 1.0, 1.0, 0.0])
    clips["siren_wail"] = save("siren_wail", wail, peak=0.7)

    # Searchlight lock: the carbon arc striking - a relay clack, a short hum swelling in.
    clack = norm(filt(noise(0.04, 900, 6000) * decay(0.04, 0.006), 300), 0.9)
    hum = (np.sin(2 * np.pi * 100 * seconds(0.5)) + 0.5 * np.sin(2 * np.pi * 200 * seconds(0.5))) * np.interp(seconds(0.5), [0, 0.08, 0.5], [0, 1, 0.15])
    fizz = filt(noise(0.5, 2500, 9000) * decay(0.5, 0.12), 2000) * 0.25
    clips["searchlight_lock"] = save("searchlight_lock", fade(mix(clack, pad(norm(hum, 0.5), 0.03), pad(fizz, 0.03)), 0.001, 0.08), peak=0.6)

    # Supply post: the magazine clink of the reload recording and a latch click.
    reload = use("Reload.mp3")
    latch = use("click.mp3")
    clink = shot(reload, 0.35, release=0.1)
    clips["supply_pulse"] = save("supply_pulse", mix(norm(shot(latch, 0.2, release=0.08), 0.6), pad(clink, 0.12)), peak=0.6)

    manifest_path = OUT / "sources.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    manifest.setdefault("sources", {}).update(sources)
    manifest.setdefault("clips", {}).update(clips)
    manifest["second_block"] = {"built_by": "tools/prepare_tower_audio2.py", "synthesised": ["siren_wail", "searchlight_lock"],
                                "layered": ["rocket_salvo", "harpoon_shot", "graviton_pulse", "supply_pulse"]}
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(clips, indent=2))


if __name__ == "__main__":
    main()
