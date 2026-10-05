"""Isolated regressions, with at most two heavy game worlds at once."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = "smoke class_system class_integration class_balance class_weapons weapon_mods new_weapons network_packets coop_snapshot_cost menu_flow language team_purse boss_music secret_night field_update planes planes_survival range_steps planes_atmosphere planes_parity towers tower_batch tower_planner roof_defences forest_finds doors_keys brewing downed assassin_teleport army_waves hut_health barricades aggro campaign_map".split()


def run(suite):
    command = [sys.executable, str(ROOT / "tools/test_expansion.py"), suite]
    if suite == "language": command += ["--lang", "de"]
    if suite in ["campaign_map", "campaign_coop"]: command += ["--classic"]
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    lines = result.stdout.splitlines()
    record = {"suite": suite, "passed": result.returncode == 0, "seconds": round(time.monotonic()-started, 1), "verdict": lines[0] if lines else result.stderr[-1000:]}
    print(record["verdict"], flush=True)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("suites", nargs="*")
    parser.add_argument("--parallel", type=int, default=2, choices=[1, 2])
    parser.add_argument("--merge", action="store_true", help="Replace selected suite results in the existing full report")
    args = parser.parse_args()
    suites = args.suites or DEFAULT
    missing = [name for name in suites if not (ROOT / f"godot/tests/{name}.gd").exists()]
    if missing: raise SystemExit("Missing suites: " + ", ".join(missing))
    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        results = list(pool.map(run, suites))
    target = ROOT / "artifacts/expansion-tests/regressions.json"
    if args.merge and target.exists():
        previous = {item["suite"]: item for item in json.loads(target.read_text(encoding="utf-8"))}
        previous.update({item["suite"]: item for item in results})
        results = list(previous.values())
    target.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"REGRESSIONS_DONE passed={sum(item['passed'] for item in results)}/{len(results)}", flush=True)
    return 0 if all(item["passed"] for item in results) else 1


if __name__ == "__main__": sys.exit(main())
