"""Resumable Meshy batch for the eight-weapon expansion (2 pistols, 2 SMGs, 2 snipers, 2 heavies).

Same shape as tools/progression_assets.py, but static weapons only (no rig, no animations) and
all eight run at once. Receipts land in meshy_output, the packer's input in assets/raw/<name>.
The key is read locally and only ever goes into Meshy's authentication header.

  python tools/weapons_expansion.py                     # all eight, resumes what exists
  python tools/weapons_expansion.py --names deagle      # single asset (re-roll: delete its state.json)
  python tools/weapons_expansion.py --status            # what is done, running, missing
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import sys
import threading
import time

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
sys.path.insert(0, str(ROOT / '.claude/skills/meshy-3d-generation/scripts'))
import meshy_task as api

CATALOG = ROOT / 'tools/weapons_expansion.json'
LOCK = threading.Lock()
T2D = '/openapi/v2/text-to-3d'
POLYCOUNT = 12000  # first person weapons are on screen at arm's length


def authenticate():
    if not os.environ.get('MESHY_API_KEY'):
        key = (ROOT / 'Meshy Key').read_text(encoding='utf-8').strip()
        match = re.search(r'msy_[A-Za-z0-9_-]+', key)
        os.environ['MESHY_API_KEY'] = match.group(0) if match else key


def balance():
    response = api.SESSION.get(api.BASE + '/openapi/v1/balance',
        headers=api._make_headers(api.load_api_key()), timeout=30)
    response.raise_for_status()
    return response.json().get('balance')


def generate(name, spec):
    raw = ROOT / 'assets/raw' / name
    raw.mkdir(parents=True, exist_ok=True)
    state_file = raw / 'state.json'
    state = json.loads(state_file.read_text()) if state_file.exists() else {}

    def save():
        state_file.write_text(json.dumps(state, indent=2))

    def submit(payload):
        # Meshy caps how many tasks one account may have in flight; a refused POST makes the skill
        # helper call sys.exit, which in a worker thread would silently kill this asset. Only a
        # transient refusal is worth waiting out - a 400 means the payload itself is wrong (the
        # prompt field is capped at 800 characters), so it fails immediately instead of looping.
        for attempt in range(12):
            try:
                return api.create_task(T2D, payload)
            except BaseException as error:  # SystemExit from the helper included
                if '400' in str(error):
                    raise RuntimeError('rejected payload (prompt over 800 characters?): %s' % error)
                print('RETRY', name, attempt + 1, type(error).__name__, error, flush=True)
                time.sleep(20 + attempt * 10)
        raise RuntimeError('submission refused twelve times')

    def stage(label, payload):
        if label not in state:
            state[label] = submit(payload)
            save()
            print('SUBMITTED', name, label, state[label], flush=True)
        receipt = api.poll_task(T2D, state[label], timeout=1800)
        with LOCK:
            if 'project' not in state:
                state['project'] = api.get_project_dir(state['preview'], name, 'text-to-3d')
            project = Path(state['project'])
            save()
            api.record_task(str(project), state[label], 'text-to-3d', label, spec['prompt'])
        (project / ('task_' + label + '.json')).write_text(json.dumps(receipt, indent=2))
        return project, receipt

    project, _ = stage('preview', dict(mode='preview', prompt=spec['prompt'], ai_model='meshy-6',
        topology='triangle', target_polycount=POLYCOUNT, should_remesh=True))
    project, result = stage('refine', dict(mode='refine', preview_task_id=state['preview'],
        enable_pbr=True, texture_prompt=spec['texture_prompt'], texture_resolution='2k'))
    target = project / 'model.glb'
    if not target.exists():
        api.download(result['model_urls']['glb'], str(target))
    shutil.copy2(target, raw / 'model.glb')
    if result.get('thumbnail_url'):
        api.save_thumbnail(str(project), result['thumbnail_url'])
        if (project / 'thumbnail.png').exists():
            shutil.copy2(project / 'thumbnail.png', raw / 'thumb.png')
    print('COMPLETE', name, (raw / 'model.glb').stat().st_size // 1024, 'KB', flush=True)
    return name


def status(specs):
    for name in specs:
        raw = ROOT / 'assets/raw' / name
        state = json.loads((raw / 'state.json').read_text()) if (raw / 'state.json').exists() else {}
        done = (raw / 'model.glb').exists()
        print('%-16s %-8s preview=%s refine=%s' % (name, 'GLB' if done else '-',
            state.get('preview', '-')[:8], state.get('refine', '-')[:8]))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--names', nargs='*')
    parser.add_argument('--status', action='store_true')
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    specs = json.loads(CATALOG.read_text(encoding='utf-8'))
    if args.status:
        status(args.names or list(specs))
        raise SystemExit(0)
    authenticate()
    print('Balance before:', balance(), flush=True)
    names = args.names or list(specs)
    failed = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {name: pool.submit(generate, name, specs[name]) for name in names}
        for name, job in jobs.items():
            try:
                job.result()
            except Exception as error:  # one bad roll must not abort the other seven
                failed.append(name)
                print('FAILED', name, type(error).__name__, error, flush=True)
    print('Balance after:', balance(), flush=True)
    print('DONE', len(names) - len(failed), 'of', len(names), 'failed:', failed or 'none', flush=True)
