"""Check old-protocol/build rejection and current ENet handshake in real processes."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = ("protocol7", "fingerprint", "matching")


def run_case(case):
    folder = ROOT / "artifacts" / "expansion-tests" / "network-compatibility" / case
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("host-ready", "client-done", "host-done", "client-finished"):
        (folder / name).unlink(missing_ok=True)
    processes = []
    streams = []
    try:
        for role in ("host", "client"):
            environment = os.environ.copy()
            environment["APPDATA"] = str(folder / f"userdata-{role}")
            command = [environment.get("GODOT", "C:/Users/miche/Desktop/Godot.exe"),
                       "--headless", "--max-fps", "60", "--path", str(ROOT / "godot"),
                       "--script", "res://tests/run.gd", "--", "--suite=network_compatibility",
                       f"--compat-case={case}", f"--compat-folder={folder}"]
            if role == "host":
                command.append("--test-host")
            stream = (folder / f"{role}.log").open("w", encoding="utf-8")
            streams.append(stream)
            processes.append(subprocess.Popen(command, cwd=ROOT, env=environment,
                                               stdout=stream, stderr=subprocess.STDOUT))
        deadline = time.monotonic() + 45
        while any(process.poll() is None for process in processes):
            if time.monotonic() > deadline or any(process.poll() not in (None, 0) for process in processes):
                break
            time.sleep(0.1)
        outcomes = []
        for role, process in zip(("host", "client"), processes):
            text = (folder / f"{role}.log").read_text(encoding="utf-8", errors="replace")
            markers = [line for line in text.splitlines() if line.startswith("NETWORK_COMPATIBILITY_DONE")]
            errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or
                      line.startswith("ERROR:") and "root certificate store" not in line]
            passed = bool(process.poll() == 0 and markers and "failures=0" in markers[-1] and not errors)
            verdict = markers[-1] if markers else "no completion marker"
            print(f"{'PASS' if passed else 'FAIL'} {case} {role}: {verdict}", flush=True)
            if not passed:
                print("\n".join(text.splitlines()[-40:]), flush=True)
            outcomes.append({"case": case, "role": role, "passed": passed, "verdict": verdict})
        return outcomes
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        for stream in streams:
            stream.close()


def main():
    outcomes = [outcome for case in CASES for outcome in run_case(case)]
    report = ROOT / "artifacts" / "expansion-tests" / "network-compatibility.json"
    report.write_text(json.dumps(outcomes, indent=2) + "\n", encoding="utf-8")
    return 0 if all(outcome["passed"] for outcome in outcomes) else 1


if __name__ == "__main__":
    sys.exit(main())
