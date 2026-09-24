"""Refresh builds/windows/BUILD-INFO.json after an export (tools/publish-itch.ps1 checks the hashes in it).

    python tools/build_info.py --label zombies-v3 --summary "..." --suites "..."

Writes the build id (remz-windows-<date>-<time>-<label>), the source commit, whether the working tree had
uncommitted changes, engine, size and SHA-256 of RemZ.exe / RemZ.pck and the validation texts. Other keys of
the previous file (notes, sources) are kept.
"""
import argparse
import datetime
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'builds/windows'
INFO = BUILD / 'BUILD-INFO.json'


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b''):
            digest.update(chunk)
    return digest.hexdigest()


def git(*args: str) -> str:
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True, help='short build label, e.g. zombies-v3')
    parser.add_argument('--summary', default='', help='what changed since the previous build')
    parser.add_argument('--suites', default='', help='which suites validated the build')
    parser.add_argument('--engine', default='Godot 4.7.2 stable')
    args = parser.parse_args()
    info = json.loads(INFO.read_text(encoding='utf-8')) if INFO.exists() else {}
    now = datetime.datetime.now(datetime.timezone.utc)
    exe = BUILD / 'RemZ.exe'
    pck = BUILD / 'RemZ.pck'
    for path in (exe, pck):
        if not path.exists():
            raise SystemExit(f'missing {path}')
    dirty = git('status', '--porcelain', '--untracked-files=no') != ''
    info.update({
        'created_utc': now.isoformat(),
        'engine': args.engine,
        'build': now.astimezone().strftime('remz-windows-%Y%m%d-%H%M-') + args.label,
        'source_commit': git('rev-parse', 'HEAD'),
        'source_includes_working_tree_changes': dirty,
        'configuration': 'Windows Desktop release x86_64',
        'export': 'passed',
        'files': [{'name': path.name, 'bytes': path.stat().st_size, 'sha256': sha256(path)} for path in (exe, pck)],
    })
    validation = dict(info.get('validation', {}))
    if args.summary:
        validation['summary'] = args.summary
    if args.suites:
        validation['source_suites'] = args.suites
    info['validation'] = validation
    INFO.write_text(json.dumps(info, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(info['build'], info['source_commit'][:12], 'dirty' if dirty else 'clean', *(f"{f['name']} {f['bytes']}" for f in info['files']))


if __name__ == '__main__':
    main()
