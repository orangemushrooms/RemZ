"""Write and load checkpoints in separate Godot processes on both maps."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    results = []
    for region in ("forest", "planes"):
        for phase in ("write", "read"):
            command = [sys.executable, str(ROOT / "tools/test_expansion.py"), "expedition_restart",
                       f"--flag=--checkpoint-phase={phase}", f"--flag=--test-region={region}",
                       "--label", f"{region}-{phase}"]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace")
            print(result.stdout.strip(), flush=True)
            if result.stderr: print(result.stderr, flush=True)
            results.append({"region": region, "phase": phase, "passed": result.returncode == 0})
            if result.returncode: break
    (ROOT / "artifacts/expansion-tests/restarts.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return 0 if len(results) == 4 and all(record["passed"] for record in results) else 1


if __name__ == "__main__": sys.exit(main())
