"""Export a release test harness, restoring the normal export configuration.

Run RemZ.exe from builds/crash-test with -- --suite=horde_hit_precision,
or start three copies with --suite=coop_intro_route --route-role=host|one|two
--route-walk --route-shoot --smoke-test --no-foliage.
The distributable build in builds/windows is not touched.
"""
from pathlib import Path
import argparse
import os
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', default=str(Path.home() / 'Desktop/Godot.exe'))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
project = root / 'godot/project.godot'
presets = root / 'godot/export_presets.cfg'
original = {p: p.read_bytes() for p in (project, presets)}
(root / 'builds/crash-test').mkdir(parents=True, exist_ok=True)
(root / 'logs').mkdir(exist_ok=True)
environment = dict(os.environ, APPDATA=str(root / '.test-user'))
try:
    project.write_bytes(original[project].replace(b'run/main_scene="res://scenes/main.tscn"', b'run/main_scene="res://tests/packed_runner.tscn"'))
    presets.write_bytes(original[presets].replace(b'exclude_filter="tests/*,assets/ph/*"', b'exclude_filter="assets/ph/*"'))
    result = subprocess.run([args.godot, '--headless', '--path', str(root / 'godot'), '--log-file', str(root / 'logs/crash-test-export.log'), '--export-release', 'Windows Desktop', str(root / 'builds/crash-test/RemZ.exe')], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, timeout=180)
finally:
    for path, contents in original.items(): path.write_bytes(contents)
raise SystemExit(result.returncode)
