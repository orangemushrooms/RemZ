"""Resumable Meshy production batch for the NPC progression expansion.

Originals and receipts live in meshy_output; assets/raw is the packer's input.
The secret is read locally and sent only to Meshy's authentication header.
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

sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
sys.path.insert(0, str(ROOT / '.claude/skills/meshy-3d-generation/scripts'))
import meshy_task as api

CATALOG = ROOT / 'tools/progression_assets.json'
OUT = ROOT / 'artifacts/progression'
LOCK = threading.Lock()
T2D = '/openapi/v2/text-to-3d'


def authenticate():
    if not os.environ.get('MESHY_API_KEY'):
        key = (ROOT / 'Meshy Key').read_text(encoding='utf-8').strip()
        match = re.search(r'msy_[A-Za-z0-9_-]+', key)
        os.environ['MESHY_API_KEY'] = match.group(0) if match else key


def inspect():
    OUT.mkdir(parents=True, exist_ok=True)
    balance = api.SESSION.get(api.BASE + '/openapi/v1/balance',
        headers=api._make_headers(api.load_api_key()), timeout=30)
    balance.raise_for_status()
    print('Balance:', balance.json(), flush=True)
    catalog = api.SESSION.get(api.BASE + '/web/public/animations/resources', timeout=30)
    catalog.raise_for_status()
    data = catalog.json()
    (OUT / 'animation-catalog.json').write_text(json.dumps(data, indent=2))
    for item in data.get('result', {}).get('list', []):
        if any(word in item.get('name', '').lower() for word in ('idle', 'talk', 'standing')):
            print({k: item.get(k) for k in ('id', 'name', 'category', 'subCategory')})


def generate(name, spec, idle):
    raw = ROOT / 'assets/raw' / name
    raw.mkdir(parents=True, exist_ok=True)
    state_file = raw / 'state.json'
    state = json.loads(state_file.read_text()) if state_file.exists() else {}

    def save():
        state_file.write_text(json.dumps(state, indent=2))

    def stage(label, endpoint, payload):
        if label not in state:
            state[label] = api.create_task(endpoint, payload)
            save()
        receipt = api.poll_task(endpoint, state[label], timeout=1800)
        with LOCK:
            if 'project' not in state:
                state['project'] = api.get_project_dir(state['preview'], name, 'text-to-3d')
            project = Path(state['project'])
            save()
            api.record_task(str(project), state[label], 'text-to-3d', label, spec['prompt'])
        (project / ('task_' + label + '.json')).write_text(json.dumps(receipt, indent=2))
        return project, receipt

    def fetch(url, filename, project):
        target = project / filename
        if not target.exists():
            api.download(url, str(target))
        shutil.copy2(target, raw / filename)

    payload = dict(mode='preview', prompt=spec['prompt'], ai_model='meshy-6',
        topology='triangle', target_polycount=12000 if spec.get('rig') else 10000, should_remesh=True)
    if spec.get('rig'):
        payload['pose_mode'] = 't-pose'
    project, _ = stage('preview', T2D, payload)
    project, result = stage('refine', T2D, dict(mode='refine', preview_task_id=state['preview'],
        enable_pbr=True, texture_prompt=spec['texture_prompt'], texture_resolution='2k'))
    fetch(result['model_urls']['glb'], 'model.glb', project)
    if result.get('thumbnail_url'):
        api.save_thumbnail(str(project), result['thumbnail_url'])
        shutil.copy2(project / 'thumbnail.png', raw / 'thumb.png')
    if spec.get('rig'):
        project, result = stage('rig', '/openapi/v1/rigging',
            dict(input_task_id=state['refine'], height_meters=spec.get('height', 1.75)))
        fetch(result['result']['rigged_character_glb_url'], 'rigged.glb', project)
        project, result = stage('idle', '/openapi/v1/animations', dict(rig_task_id=state['rig'], action_id=idle))
        fetch(result['result']['animation_glb_url'], 'anim_idle.glb', project)
    print('COMPLETE', name, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--inspect', action='store_true')
    parser.add_argument('--idle', type=int)
    parser.add_argument('--names', nargs='*')
    args = parser.parse_args()
    authenticate()
    if args.inspect:
        inspect()
    else:
        specs = json.loads(CATALOG.read_text())
        if args.idle is None:
            parser.error('--idle requires an ID verified in the live animation catalog')
        names = args.names or list(specs)
        with ThreadPoolExecutor(max_workers=3) as pool:
            jobs = [pool.submit(generate, name, specs[name], args.idle) for name in names]
            for job in jobs:
                job.result()
