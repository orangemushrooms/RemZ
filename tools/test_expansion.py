"""Isolated Godot suite runner. Prints a verdict; retains complete logs under artifacts.

python tools/test_expansion.py compile_all
python tools/test_expansion.py expedition --render --lang de
python tools/test_expansion.py smoke --classic
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("suite")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--classic", action="store_true")
    parser.add_argument("--lang", default="en")
    parser.add_argument("--flag", action="append", default=[])
    parser.add_argument("--label", default="")
    parser.add_argument("--profile", default="", help="Share an isolated profile between related processes, e.g. checkpoint write/read")
    parser.add_argument("--production-start", action="store_true", help="Keep normal loading, intro and foliage for rendered startup checks")
    parser.add_argument("--diagnostic", action="store_true", help="Accept a diagnostic completion marker without claiming assertions")
    args = parser.parse_args()
    folder = ROOT / "artifacts" / "expansion-tests"
    folder.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    if args.label and not re.fullmatch(r"[A-Za-z0-9_-]+", args.label): parser.error("Invalid log label")
    if args.profile and not re.fullmatch(r"[A-Za-z0-9_-]+", args.profile): parser.error("Invalid profile label")
    profile = args.profile or args.label
    # Keep Windows shader-cache paths below MAX_PATH even for long suite labels.
    identity = f"{args.suite}-{args.lang}-{args.classic}-{profile}"
    environment["APPDATA"] = str(ROOT / ".test-user" / "audit" / hashlib.sha256(identity.encode()).hexdigest()[:12])
    log = folder / f"{args.suite}-{args.lang}{'-render' if args.render else ''}{'-classic' if args.classic else ''}{'-'+args.label if args.label else ''}.log"
    command = [environment.get("GODOT", "C:/Users/miche/Desktop/Godot.exe")]
    if not args.render:
        command += ["--headless"]
    command += ["--path", str(ROOT / "godot"), "--script", "res://tests/run.gd", "--",
                f"--suite={args.suite}", "--no-music", f"--lang={args.lang}"]
    if not args.production_start:
        command += ["--smoke-test", "--no-intro", "--no-foliage"]
    if args.classic:
        command += ["--classic-run"]
    if args.render:
        command += ["--expedition-captures"]
    command += args.flag
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 900
        try:
            while process.poll() is None:
                text = log.read_text(encoding="utf-8", errors="replace")
                fatal = any("SCRIPT ERROR" in line or line.startswith("ERROR:") and "root certificate store" not in line for line in text.splitlines())
                if fatal or time.monotonic() >= deadline:
                    print(f"FAIL {args.suite}: {'engine/script error' if fatal else 'timeout'}; {log}", flush=True)
                    process.terminate()
                    break
                time.sleep(0.25)
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=15)
        result = process
    text = log.read_text(encoding="utf-8", errors="replace")
    markers = re.findall(r"(?:[A-Z0-9_]+_DONE[^\n]*|COMPILE_ALL scripts=\d+ broken=\d+)", text)
    # The restricted Windows environment cannot read its root certificate store;
    # this is also present in the untouched baseline. Gameplay errors remain fatal.
    errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or line.startswith("ERROR:") and "root certificate store" not in line]
    if not markers:
        markers = re.findall(r"[A-Z0-9_]+ checks=\d+ failures=\d+", text)
    clean = markers and ("failures=0" in markers[-1] or "broken=0" in markers[-1])
    if args.diagnostic:
        clean = bool(markers) and not any("FAIL:" in line for line in text.splitlines())
    ok = result.returncode == 0 and clean and not errors
    print(f"{'PASS' if ok else 'FAIL'} {args.suite} exit={result.returncode}: {markers[-1] if markers else 'no completion marker'}")
    if not ok:
        print("\n".join(text.splitlines()[-140:]))
    print(f"Log: {log}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
