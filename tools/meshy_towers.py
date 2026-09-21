"""Resumable Meshy tower weapon assets; never prints credentials."""
import json
import sys
from contextlib import redirect_stderr
from io import StringIO
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Lock
from progression_assets import api, authenticate, ROOT

ENDPOINT = '/openapi/v2/text-to-3d'
LOCK = Lock()
SPECS = {
    'flame': 'A heavy mounted flamethrower weapon assembly, long thick nozzle barrel pointing horizontally forward along positive Z, twin red fuel cylinders beside the rear breech, armored hoses, ignition nozzle and rear operator handles.',
    'mortar': 'A heavy short wide mortar launcher weapon assembly, a single thick open steel tube pointing horizontally forward along positive Z, heavy breech at rear, recoil cylinder, side trunnion pivots and elevation handwheel. Bore visibly open.',
    'tesla': 'A vertical Tesla coil weapon assembly, large copper wound central column rising from a compact electrical equipment box, broad silver toroidal electrode at the top, ceramic insulators, thick cables, aged brass terminals. No lightning.',
    'mg42': 'A heavy MG42 inspired mounted machine gun weapon assembly, single long perforated barrel shroud pointing horizontally forward along positive Z, rectangular receiver, wooden rear stock, side ammunition belt and olive drab ammunition box, rear operator handles. No insignia.',
}

def generate(kind):
    state_path = ROOT / 'meshy_output' / ('tower_' + kind + '_state.json')
    state_path.parent.mkdir(exist_ok=True)
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    prompt = SPECS[kind] + ' Realistic post apocalyptic survival game prop, convincing functional proportions, weathered steel and copper. Weapon only, no tower, no pedestal, no tripod, no people, no scenery, no ground, no text. Isolated complete object.'
    for stage in ['preview', 'refine']:
        if stage not in state:
            payload = dict(mode='preview', prompt=prompt, ai_model='meshy-7.1', geometry_resolution='2k', should_remesh=True, topology='triangle', target_polycount=14000, target_formats=['glb']) if stage == 'preview' else dict(mode='refine', preview_task_id=state['preview'], enable_pbr=True, texture_resolution='2k', texture_prompt='Realistic worn gunmetal, brushed steel, subtle rust and scratches, copper and ceramic details, muted olive drab painted housing. PBR materials, no baked lighting, no text.', target_formats=['glb'])
            state[stage] = api.create_task(ENDPOINT, payload)
            state_path.write_text(json.dumps(state, indent=2))
        with LOCK:
            if 'folder' not in state:
                state['folder'] = api.get_project_dir(state['preview'], 'tower_' + kind, 'text-to-3d')
                state_path.write_text(json.dumps(state, indent=2))
        folder = Path(state['folder'])
        receipt_path = folder / (stage + '_task.json')
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else api.poll_task(ENDPOINT, state[stage], timeout=1800)
        receipt_path.write_text(json.dumps(receipt, indent=2))
        target = folder / (stage + '.glb')
        if not target.exists(): api.download(receipt['model_urls']['glb'], str(target))
        thumb = folder / (stage + '.png')
        if receipt.get('thumbnail_url') and not thumb.exists(): api.download(receipt['thumbnail_url'], str(thumb))
        with LOCK: api.record_task(str(folder), state[stage], 'text-to-3d', stage, prompt, [target.name])
        print(kind, stage, 'credits', receipt.get('consumed_credits'), flush=True)

if __name__ == '__main__':
    authenticate()  # Reuses the project's existing Meshy credential source.
    if '--balance' in sys.argv:
        with redirect_stderr(StringIO()):  # Suppress the CLI's credential prefix notice.
            api._cmd_balance(None)
    else:
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(generate, SPECS))
