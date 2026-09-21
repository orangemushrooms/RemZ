"""Resume the audited missing models using the project's bundled Meshy client."""
import json
import sys
from argparse import Namespace
from concurrent.futures import ThreadPoolExecutor
from threading import Lock
from pathlib import Path
from contextlib import redirect_stderr
from io import StringIO
from progression_assets import api, authenticate, ROOT

CATALOG = json.loads((ROOT / 'tools/missing_assets.json').read_text())
ENDPOINT = '/openapi/v2/text-to-3d'
LOCK = Lock()


def reset_failed(name):
    path = ROOT / 'meshy_output' / ('missing_' + name + '_state.json')
    state = json.loads(path.read_text())
    stage = 'refine' if 'refine' in state else 'preview'
    receipt_path = Path(state['folder']) / ('failed_' + stage + '_' + state[stage] + '.json')
    with redirect_stderr(StringIO()):
        api._cmd_get(Namespace(endpoint=ENDPOINT, task_id=state[stage], save=str(receipt_path)))
    receipt = json.loads(receipt_path.read_text())
    if receipt.get('status') != 'FAILED' or receipt.get('consumed_credits') != 0:
        raise RuntimeError('Only confirmed failed, refunded tasks may be reset')
    state.setdefault('failed_attempts', []).append(dict(stage=stage, task_id=state.pop(stage), credits=0))
    path.write_text(json.dumps(state, indent=2))


def generate(name):
    spec = CATALOG[name]
    state_path = ROOT / 'meshy_output' / ('missing_' + name + '_state.json')
    state_path.parent.mkdir(exist_ok=True)
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    prompt = spec['prompt'] + ' Photorealistic high fidelity game asset, physically plausible proportions, detailed real world materials. Isolated complete object, no scenery, no ground plane, no display base, no text, no cartoon stylization.'
    for stage in ['preview', 'refine']:
        if stage not in state:
            payload = dict(mode='preview', prompt=prompt, ai_model='meshy-7.1',
                geometry_resolution='2k', should_remesh=True, topology='triangle',
                target_polycount=18000 if name in ['owl_real', 'tower_standard'] else 10000,
                target_formats=['glb']) if stage == 'preview' else dict(mode='refine',
                preview_task_id=state['preview'], enable_pbr=True, texture_resolution='2k',
                texture_prompt=spec['prompt'] + ' Photorealistic PBR materials, fine natural surface detail, calibrated albedo, roughness and normal maps, no baked lighting or shadows, no text.',
                target_formats=['glb'])
            state[stage] = api.create_task(ENDPOINT, payload)
            state_path.write_text(json.dumps(state, indent=2))
        with LOCK:
            if 'folder' not in state:
                state['folder'] = api.get_project_dir(state['preview'], name, 'text-to-3d')
                state_path.write_text(json.dumps(state, indent=2))
        folder = Path(state['folder'])
        receipt_path = folder / (stage + '_task.json')
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else api.poll_task(ENDPOINT, state[stage], timeout=1800)
        if receipt.get('status') != 'SUCCEEDED':
            raise RuntimeError(f'{name} {stage} failed; inspect receipt before retrying')
        receipt_path.write_text(json.dumps(receipt, indent=2))
        for label, url in [(stage + '.glb', receipt['model_urls']['glb']), (stage + '.png', receipt.get('thumbnail_url'))]:
            if url and not (folder / label).exists(): api.download(url, str(folder / label))
        with LOCK:
            api.record_task(str(folder), state[stage], 'text-to-3d', stage, prompt, [stage + '.glb'])
        print('ASSET', name, stage, 'credits', receipt.get('consumed_credits'), flush=True)


if __name__ == '__main__':
    authenticate()
    if '--balance' in sys.argv:
        with redirect_stderr(StringIO()): api._cmd_balance(None)
    else:
        retry = '--retry-failed' in sys.argv
        names = [arg for arg in sys.argv[1:] if arg != '--retry-failed'] or list(CATALOG)
        if any(name not in CATALOG for name in names): raise SystemExit('Unknown asset')
        if retry:
            for name in names: reset_failed(name)
        with ThreadPoolExecutor(max_workers=4) as pool:
            for result in pool.map(generate, names): pass
