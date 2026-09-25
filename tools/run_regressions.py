"""Run the headless test suites three at a time (the 16 GB dev PC cannot hold more Godot worlds) and
write logs/t_<name>.log per suite plus logs/regressions_summary.txt with the PASS/FAIL line of each.

  python tools/run_regressions.py [--parallel 3] [names...]
Names default to the batch of 26 Sep 2026 below; a name is "<log name>=<suite>[ extra flags]".
"""
import argparse
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "C:/Users/miche/Desktop/Godot.exe")
SMOKE = "--smoke-test --no-intro --no-music --no-foliage"
DEFAULT = [
    "language_de=language %s --lang=de" % SMOKE,
    "cheat_menu=cheat_menu %s" % SMOKE,
    "team_purse=team_purse %s" % SMOKE,
    "perimeter=perimeter --smoke-test --no-intro --no-music",
    "menu_flow=menu_flow %s" % SMOKE,
    "coop_snapshot_cost=coop_snapshot_cost %s" % SMOKE,
    "network_packets=network_packets",
    "online_lobby=online_lobby %s" % SMOKE,
    "smoke=smoke --smoke-test",
    "zombie_hitboxes=zombie_hitboxes",
    "horde_hit_precision=horde_hit_precision",
    "day_night=day_night --smoke-test --no-music",
    "titan_siege_gate=titan_siege_gate %s" % SMOKE,
    "boss_music=boss_music --smoke-test --no-intro --no-foliage",
    "secret_night=secret_night %s" % SMOKE,
    "hut_health=hut_health %s" % SMOKE,
    "forest_finds=forest_finds %s" % SMOKE,
    "tower_planner=tower_planner %s" % SMOKE,
    "barricades=barricades --smoke-test",
    "missing_models=missing_models",
    "weapon_mods=weapon_mods %s" % SMOKE,
    "earthworms=earthworms %s" % SMOKE,
    "titan_variants=titan_variants %s" % SMOKE,
    "aggro=aggro %s" % SMOKE,
    "coop_intro_route=coop_intro_route --smoke-test --no-music --no-foliage",
]


def run(entry):
    name, spec = entry.split("=", 1)
    parts = spec.split()
    suite, flags = parts[0], parts[1:]
    log = os.path.join(ROOT, "logs", "t_%s.log" % name)
    started = time.time()
    with open(log, "w", encoding="utf-8") as out:
        try:
            code = subprocess.call([GODOT, "--headless", "--path", "godot", "--script", "res://tests/run.gd", "--",
                                    "--suite=" + suite] + flags, stdout=out, stderr=subprocess.STDOUT, cwd=ROOT, timeout=1500)
        except subprocess.TimeoutExpired:
            code = -9
    text = open(log, encoding="utf-8", errors="replace").read()
    done = re.findall(r"^[A-Z_]+_DONE.*$", text, re.M)
    fails = [line for line in text.splitlines() if "FAIL" in line and "FAILED" not in line][:6]
    errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line][:4]
    verdict = "OK" if code == 0 and done and "failures=0" in (done[-1] if done else "") else "BAD"
    return "%-20s %s exit=%s %.0fs %s %s %s" % (name, verdict, code, time.time() - started, done[-1] if done else "(no done line)",
                                                 " | ".join(fails), " | ".join(errors))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("names", nargs="*")
    parser.add_argument("--parallel", type=int, default=3)
    args = parser.parse_args()
    entries = args.names or DEFAULT
    summary = os.path.join(ROOT, "logs", "regressions_summary.txt")
    with open(summary, "w", encoding="utf-8") as out:
        out.write("started %s\n" % time.strftime("%H:%M:%S"))
    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        for line in pool.map(run, entries):
            print(line, flush=True)
            with open(summary, "a", encoding="utf-8") as out:
                out.write(line + "\n")
    with open(summary, "a", encoding="utf-8") as out:
        out.write("REGRESSIONS_DONE %s\n" % time.strftime("%H:%M:%S"))
    print("REGRESSIONS_DONE")


if __name__ == "__main__":
    main()
