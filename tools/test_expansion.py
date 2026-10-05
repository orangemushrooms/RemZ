"""Isolated Godot suite runner. Prints a verdict; retains complete logs under artifacts.

python tools/test_expansion.py compile_all
python tools/test_expansion.py expedition --render --lang de
python tools/test_expansion.py smoke --classic
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("suite")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--classic", action="store_true")
    parser.add_argument("--lang", default="en")
    parser.add_argument("--flag", action="append", default=[])
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    folder = ROOT / "artifacts" / "expansion-tests"
    folder.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["APPDATA"] = str(folder / "userdata" / f"{args.suite}-{args.lang}{'-classic' if args.classic else ''}")
    if args.label and not re.fullmatch(r"[A-Za-z0-9_-]+", args.label): parser.error("Invalid log label")
    log = folder / f"{args.suite}-{args.lang}{'-render' if args.render else ''}{'-classic' if args.classic else ''}{'-'+args.label if args.label else ''}.log"
    command = [environment.get("GODOT", "C:/Users/miche/Desktop/Godot.exe")]
    if not args.render:
        command += ["--headless"]
    command += ["--path", str(ROOT / "godot"), "--script", "res://tests/run.gd", "--",
                f"--suite={args.suite}", "--smoke-test", "--no-intro", "--no-music", "--no-foliage", f"--lang={args.lang}"]
    if args.classic:
        command += ["--classic-run"]
    if args.render:
        command += ["--expedition-captures"]
    command += args.flag
    with log.open("w", encoding="utf-8") as output:
        try:
            result = subprocess.run(command, cwd=ROOT, env=environment, stdout=output, stderr=subprocess.STDOUT, timeout=900)
        except subprocess.TimeoutExpired:
            print(f"FAIL {args.suite}: timeout; {log}")
            return 1
    text = log.read_text(encoding="utf-8", errors="replace")
    markers = re.findall(r"(?:[A-Z0-9_]+_DONE[^\n]*|COMPILE_ALL scripts=\d+ broken=\d+)", text)
    # The restricted Windows environment cannot read its root certificate store;
    # this is also present in the untouched baseline. Gameplay errors remain fatal.
    errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or line.startswith("ERROR:") and "root certificate store" not in line]
    if not markers:
        markers = re.findall(r"[A-Z0-9_]+ checks=\d+ failures=\d+", text)
    clean = markers and ("failures=0" in markers[-1] or "broken=0" in markers[-1])
    ok = result.returncode == 0 and clean and not errors
    print(f"{'PASS' if ok else 'FAIL'} {args.suite} exit={result.returncode}: {markers[-1] if markers else 'no completion marker'}")
    if not ok:
        print("\n".join(text.splitlines()[-140:]))
    print(f"Log: {log}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
