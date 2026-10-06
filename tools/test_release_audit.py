"""Broader release audit with isolated profiles and incremental reports.

Run core regressions with test_expansion_batch.py, then this extended matrix.
ENet, EOS, process-restart and actual release-pack checks have dedicated runners.
Start groups without --resume for a fresh audit; use --resume only to continue that audit.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
EXTENDED = """achievements aiming audio_events autorefill balance_report barricade_health
barricade_shooting batch27 batch28 batch29 bullet_impacts campsite_pickups cash_drops
cheat_menu connection_cancel cornfield crouch day_night deer_gait defence delivery_spawn
drone_quests drones earthworm_mesh_quality earthworms extra_quests farm_dog
firework_batteries fireworks forest_spirit fortune_wheels frame_pacing_guards
horde_animation horde_ground horde_hit_precision hunting hut_restock inventory_filters
key_phases key_rarity knife_speed leaderboard legacy_user_data loading_tips melee_weapons
merchant_roaming missing_models movement_sync mushroom_trade muzzle_alignment new_zombies
npc_discovery online_lobby perimeter pickup_capacity piercing pings
planes_boundary planes_buildings planes_cheat_key planes_cleanup planes_gameplay planes_life
planes_quests planes_refinements planes_sales planes_start_movement planes_xp player_avatar
progression pumpkins quest_balance quest_notifications quickbar rare_market sandbags
sniper_scope sound_files spawn_safety thrown_tree_roots
titan_collapse titan_horror titan_loot titan_mix titan_phases titan_siege_gate titan_variants
tower_effects tower_progression weapon_attachments weapon_effects weapon_recordings
weapon_specials weather zombie_hitboxes zombie_motion expedition
checkpoint_schema onboarding_polish gameplay_ux_audit""".split()


def cases(group):
    if group == "online":
        return [
            ("eos-source-relay", "tools/test_online_coop.ps1", ["-ForceRelay"]),
            ("eos-packed-forest", "tools/test_online_coop.ps1", ["-Packed", "-ForceRelay", "-Region", "forest"]),
            ("eos-packed-planes", "tools/test_online_coop.ps1", ["-Packed", "-ForceRelay", "-Region", "planes"]),
        ]
    if group == "packaged":
        return [("four-player-release", "tools/test_packed_coop.ps1", ["-Players", "4"])]
    if group == "integration":
        return [
            ("checkpoint-restarts", "tools/test_expansion_restart.py", []),
            ("expedition-forest", "tools/test_expansion_coop.py", ["forest"]),
            ("expedition-planes", "tools/test_expansion_coop.py", ["planes"]),
            ("four-player-forest", "tools/test_multiplayer.ps1", []),
            ("planes-coop", "tools/test_planes_coop.ps1", []),
            ("planes-late-join", "tools/test_planes_coop.ps1", ["-LateJoin"]),
            ("classes-coop", "tools/test_class_coop.ps1", []),
            ("earthworms-coop", "tools/test_earthworm_coop.ps1", []),
            ("drones-coop", "tools/test_drone_coop.ps1", []),
            ("field-coop", "tools/test_field_coop.ps1", []),
        ]
    if group == "performance":
        return [
            ("shader-hitches", "flare_hitch", ["--render"]),
            ("frame-pacing", "frame_pacing", ["--render", "--diagnostic", "--production-start", "--flag=--no-intro", "--flag=--pacing-report=full-audit"]),
            ("planes-combat", "planes_perf", ["--render", "--diagnostic", "--production-start", "--flag=--no-intro", "--flag=--planes-combat-perf", "--flag=--planes-perf=full-audit"]),
        ]
    if group == "extended":
        return [(name, name, ["--classic"] if name in ["earthworms", "defence", "forest_spirit", "planes_xp", "spawn_safety", "titan_variants"] else []) for name in EXTENDED]
    if group == "variants":
        return [
            ("class-balance-planes", "class_balance", ["--flag=--class-planes"]),
            ("onboarding-planes", "onboarding_polish", ["--flag=--planes-onboarding"]),
            ("gameplay-planes", "gameplay_ux_audit", ["--flag=--audit-planes"]),
            ("weapon-field-forest", "weapon_field_polish", ["--flag=--forest"]),
            ("weapon-field-planes", "weapon_field_polish", []),
            ("classic-smoke", "smoke", ["--classic"]),
            ("classic-planes", "planes_survival", ["--classic"]),
            ("expedition-planes", "planes_survival", []),
            ("navigation-planes", "planes_navigation", []),
            ("interaction-prompts", "interactions", []),
            ("intro-guidance", "intro_guidance", []),
        ]
    return [
        ("survival-menu", "survival_menu", ["--render"]),
        ("teleport-input", "teleport_input", ["--render"]),
        ("perimeter-beams", "perimeter_beams", ["--render"]),
        ("input-hud-de", "player_experience", ["--render", "--lang=de"]),
        ("fieldbook-de", "fieldbook_usability", ["--render", "--lang=de"]),
        ("fieldbook-en", "fieldbook_usability", ["--render", "--lang=en"]),
        ("vendor-de", "vendor_tutorial", ["--render", "--lang=de"]),
        ("sites-de", "expedition_sites", ["--render", "--lang=de"]),
        ("sites-en", "expedition_sites", ["--render", "--lang=en"]),
        ("startup", "start_exposure", ["--render", "--production-start"]),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("group", choices=["extended", "variants", "rendered", "performance", "integration", "packaged", "online"])
    parser.add_argument("--parallel", type=int, choices=[1, 2], default=2)
    parser.add_argument("--only", nargs="*", help="Rerun named cases; retains other results from this audit group")
    parser.add_argument("--resume", action="store_true", help="Continue this audit group, keeping its completed passing cases")
    args = parser.parse_args()
    selected = cases(args.group)
    if args.only:
        unknown = set(args.only)-{case[0] for case in selected}
        if unknown: parser.error("Unknown cases: "+", ".join(sorted(unknown)))
        selected = [case for case in selected if case[0] in args.only]
    target = ROOT/"artifacts/expansion-tests"/f"full-audit-{args.group}.json"
    results = json.loads(target.read_text(encoding="utf-8")) if (args.only or args.resume) and target.exists() else []
    current_cases = {case[0] for case in cases(args.group)}
    results = [item for item in results if item["case"] in current_cases]
    if args.resume:
        passed = {item["case"] for item in results if item["passed"]}
        selected = [case for case in selected if case[0] not in passed]
    locks = {suite: threading.Lock() for _, suite, _ in selected}

    def run(case):
        name, suite, flags = case
        environment = os.environ.copy()
        environment["APPDATA"] = str(ROOT/".test-user"/"integration"/name)
        if suite.startswith("tools/"):
            command = (["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT/suite)]
                       if suite.endswith(".ps1") else [sys.executable, "-X", "utf8", str(ROOT/suite)])+flags
        else:
            command = [sys.executable, "-X", "utf8", str(ROOT/"tools/test_expansion.py"), suite,
                       "--label=full-audit-"+name, *flags]
        with locks[suite]:
            started = time.monotonic()
            process = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, encoding="utf-8", errors="replace")
            if args.group == "online":
                # The native forest/Planes runner reuses two filenames. Retain each
                # case's evidence before starting the next map.
                evidence = target.parent/name
                evidence.mkdir(parents=True, exist_ok=True)
                names = ["packed-host.log", "packed-client.log"] if "-Packed" in flags else ["host.log", "client.log"]
                for filename in names:
                    source = ROOT/"artifacts/online"/filename
                    if source.exists(): shutil.copy2(source, evidence/filename)
        lines = process.stdout.splitlines()
        verdict = next((line for line in reversed(lines) if line.startswith(("PASS ", "FAIL ")) and "exit=" in line), process.stderr[-1000:])
        if suite.startswith("tools/"):
            (target.parent/f"integration-{name}.log").write_text(process.stdout+process.stderr, encoding="utf-8")
            verdict = f"{'PASS' if process.returncode == 0 else 'FAIL'} {name} exit={process.returncode} (integration-{name}.log)"
        return {"case": name, "suite": suite, "flags": flags, "passed": process.returncode == 0,
                "seconds": round(time.monotonic()-started, 1), "verdict": verdict}

    with ThreadPoolExecutor(max_workers=1 if args.group in ["rendered", "performance", "integration", "packaged", "online"] else args.parallel) as pool:
        for future in as_completed([pool.submit(run, case) for case in selected]):
            record = future.result()
            results = [item for item in results if item["case"] != record["case"]]+[record]
            target.write_text(json.dumps(results, indent=2)+"\n", encoding="utf-8")
            print(record["verdict"], flush=True)
    print(f"RELEASE_AUDIT_DONE group={args.group} passed={sum(item['passed'] for item in results)}/{len(results)}", flush=True)
    return 0 if all(item["passed"] for item in results) else 1


if __name__ == "__main__": sys.exit(main())
