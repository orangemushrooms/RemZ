"""Check native release startup, then test the same PCK through Godot's script runner.

The release template ignores --script, so native startup is monitored by its map-ready
marker. Functional assertions load production resources with --main-pack; test code
remains outside the distributable pack.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    executable = ROOT / "builds/windows/RemZ.exe"
    folder = ROOT / "artifacts/expansion-tests"
    # Editor Godot requests the debug GDExtension, whereas the real release executable
    # correctly uses the shipped release DLL. Supply the matching debug dependency only
    # in the isolated probe directory. The tested PCK is a hard link to the release PCK.
    probe = folder / "pack-probe"
    probe.mkdir(parents=True, exist_ok=True)
    pack = probe / "RemZ.pck"
    if pack.exists(): pack.unlink()
    os.link(executable.with_suffix(".pck"), pack)
    source = ROOT / "godot/addons/epic-online-services-godot/bin/windows"
    target = probe / "addons/epic-online-services-godot/bin/windows"
    (target / "x64").mkdir(parents=True, exist_ok=True)
    for name in ("libeosg.windows.template_debug.dev.x86_64.dll", "EOSSDK-Win64-Shipping.dll", "x64/xaudio2_9redist.dll"):
        shutil.copy2(source / name, target / name)
    records = []
    for region in ("forest", "planes"):
        environment = dict(os.environ, APPDATA=str(folder / "userdata" / f"packed-{region}"))
        native_log = folder / f"native-{region}.log"
        native_command = [str(executable), "--headless", "--max-fps", "60", "--", "--smoke-test",
                          "--no-intro", "--no-music", "--no-foliage", "--lang=de"]
        if region == "planes": native_command.append("--explore-planes")
        ready_marker = "PLANES_READY" if region == "planes" else "COOP_LOAD MAP_READY"
        native_ready = False
        with native_log.open("w", encoding="utf-8") as output:
            native = subprocess.Popen(native_command, cwd=executable.parent, env=environment,
                                      stdout=output, stderr=subprocess.STDOUT)
            deadline = time.monotonic()+180
            try:
                while native.poll() is None and time.monotonic() < deadline:
                    native_text = native_log.read_text(encoding="utf-8", errors="replace")
                    if ready_marker in native_text:
                        native_ready = True
                        break
                    time.sleep(0.25)
            finally:
                if native.poll() is None:
                    native.terminate()
                    native.wait(timeout=10)
        native_text = native_log.read_text(encoding="utf-8", errors="replace")
        native_errors = [line for line in native_text.splitlines() if "SCRIPT ERROR" in line or
                         line.startswith("ERROR:") and "root certificate store" not in line]
        native_ok = native_ready and not native_errors
        print(f"{'PASS' if native_ok else 'FAIL'} native {region}: {ready_marker}", flush=True)
        log = folder / f"packed-{region}.log"
        command = [os.environ.get("GODOT", "C:/Users/miche/Desktop/Godot.exe"), "--headless",
                   "--path", str(probe), "--main-pack", str(pack), "--script", str(ROOT / "godot/tests/expedition_pack.gd"),
                   "--", "--smoke-test", "--no-intro", "--no-music", "--no-foliage", "--lang=de", f"--test-region={region}"]
        with log.open("w", encoding="utf-8") as output:
            try:
                result = subprocess.run(command, cwd=probe, env=environment,
                                        stdout=output, stderr=subprocess.STDOUT, timeout=360)
            except subprocess.TimeoutExpired:
                print(f"FAIL packed {region}: timeout", flush=True)
                records.append({"region": region, "passed": False})
                continue
        text = log.read_text(encoding="utf-8", errors="replace")
        markers = re.findall(r"EXPEDITION_PACK_DONE[^\n]*", text)
        errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or
                  line.startswith("ERROR:") and "root certificate store" not in line]
        ok = native_ok and result.returncode == 0 and bool(markers) and "failures=0" in markers[-1] and not errors
        records.append({"region": region, "passed": ok, "native_startup": native_ok, "verdict": markers[-1] if markers else "no completion marker"})
        print(f"{'PASS' if ok else 'FAIL'} packed {region}: {records[-1]['verdict']}", flush=True)
        if not ok: print("\n".join(text.splitlines()[-45:]), flush=True)
    (folder / "packed.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
    return 0 if all(record["passed"] for record in records) else 1


if __name__ == "__main__": sys.exit(main())
