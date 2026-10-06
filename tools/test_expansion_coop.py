"""Run the expedition suite over real local ENet connections, with isolated profiles."""
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    region = sys.argv[1] if len(sys.argv) > 1 else "planes"
    if region not in {"planes", "forest"}:
        raise ValueError("region must be planes or forest")
    folder = ROOT / "artifacts" / "expansion-tests" / f"coop-{region}"
    folder.mkdir(parents=True, exist_ok=True)
    # Delete only this runner's named synchronisation files inside its verified folder.
    for name in ("host-ready", "test-ready", "client-choice", "heal-ready", "client-heal", "restored", "client-restored", "outpost-ready", "client-outpost", "structure-ready", "client-structure", "finale-ready", "client-finale", "done", "client-done"):
        (folder / name).unlink(missing_ok=True)
    processes = []
    streams = []
    try:
        for role in ("host", "client"):
            environment = os.environ.copy()
            environment["APPDATA"] = str(folder / f"userdata-{role}")
            command = [environment.get("GODOT", "C:/Users/miche/Desktop/Godot.exe"), "--headless", "--max-fps", "60",
                       "--path", str(ROOT / "godot"), "--script", "res://tests/run.gd", "--", "--suite=expedition_coop",
                       "--smoke-test", "--no-intro", "--no-music", "--no-foliage", "--class-auto-lock"]
            if role == "host": command.append("--test-host")
            if region == "forest": command.append("--test-forest")
            stream = (folder / f"{role}.log").open("w", encoding="utf-8")
            streams.append(stream)
            processes.append(subprocess.Popen(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT))
        deadline = time.monotonic()+600
        while any(process.poll() is None for process in processes):
            if time.monotonic() > deadline or any(process.poll() not in (None, 0) for process in processes):
                print("FAIL: cooperative peer failed or timed out")
                return 1
            time.sleep(0.5)
        result = 0
        for role, process in zip(("host", "client"), processes):
            text = (folder / f"{role}.log").read_text(encoding="utf-8", errors="replace")
            markers = [line for line in text.splitlines() if line.startswith("EXPEDITION_COOP_DONE")]
            errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or line.startswith("ERROR:") and "root certificate store" not in line]
            ok = process.returncode == 0 and markers and "failures=0" in markers[-1] and not errors
            print(f"{'PASS' if ok else 'FAIL'} {region} {role}: {markers[-1] if markers else 'no completion marker'}")
            if not ok:
                print("\n".join(text.splitlines()[-60:]))
                result = 1
        return result
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        for stream in streams: stream.close()


if __name__ == "__main__": sys.exit(main())
