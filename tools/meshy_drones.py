"""Three resumable Meshy attack drones. Originals/receipts stay in meshy_output."""
import json
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from threading import Lock
from pathlib import Path
from progression_assets import api, authenticate, ROOT

LOCK = Lock()
ENDPOINT = '/openapi/v2/text-to-3d'
DESIGNS = {
    'scout': 'Compact realistic military quadcopter attack drone, four separate circular ducted rotors on X arms, slim angular olive green fuselage, front optical camera with blue glass, one forward underslung machine gun, black carbon fiber struts, exposed wiring, battery clips, landing skids, vents, bolts. Lightweight precise engineering. Rotor axes vertical, gun pointing forward. Complete aircraft, isolated, no base, no scenery, no people, no lettering.',
    'viper': 'Detailed medium military attack quadcopter gunship, four large separate ducted rotors on broad X arms, swept angular gunmetal armored fuselage, two parallel forward underslung autocannon barrels, front gimbal with amber optics, titanium motor housings, copper power cables, cooling vents, rivets, shock absorbing landing skids. Aggressive functional aircraft design. Rotor axes vertical. Complete isolated aircraft, no base, no scenery, no people, no lettering.',
    'tempest': 'Highly detailed heavy military hexacopter assault gunship, six separate ducted lift rotors on radial arms, broad angular dark graphite armored body, central forward underslung rotary minigun, red optical sensor, ammunition feed, exposed pistons, layered armor panels, heat sinks, recessed bolts, reinforced landing skids, yellow warning stripes. Believable premium survival game aircraft. Rotor axes vertical. Complete isolated aircraft, no base, no scenery, no people, no lettering.',
}

def generate(kind):
    path = ROOT / 'meshy_output' / ('drone_' + kind + '_state.json')
    state = json.loads(path.read_text()) if path.exists() else {}
    for stage in ('preview', 'refine'):
        if stage not in state:
            payload = dict(mode='preview', prompt=DESIGNS[kind], ai_model='meshy-7.1', geometry_resolution='2k', should_remesh=True, topology='triangle', target_polycount=30000, target_formats=['glb']) if stage == 'preview' else dict(mode='refine', preview_task_id=state['preview'], enable_pbr=True, texture_resolution='4k', texture_prompt='Premium photorealistic worn military aircraft: carbon fiber weave, machined titanium, painted armor, rough rubber, subtle edge wear, contrasting glass sensors, readable mechanical details. Physically based materials, no baked lighting, no text.', target_formats=['glb'])
            state[stage] = api.create_task(ENDPOINT, payload)
            path.write_text(json.dumps(state, indent=2))
        with LOCK:
            if 'folder' not in state:
                state['folder'] = api.get_project_dir(state['preview'], 'drone_' + kind, 'text-to-3d')
                path.write_text(json.dumps(state, indent=2))
        folder = Path(state['folder'])
        receipt_path = folder / (stage + '_task.json')
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else api.poll_task(ENDPOINT, state[stage], timeout=1800)
        if receipt.get('status') != 'SUCCEEDED':
            raise RuntimeError(f'{kind} {stage} did not succeed')
        receipt_path.write_text(json.dumps(receipt, indent=2))
        for url, name in [(receipt['model_urls']['glb'], stage + '.glb'), (receipt.get('thumbnail_url'), stage + '.png')]:
            if url and not (folder / name).exists(): api.download(url, str(folder / name))
        with LOCK:
            api.record_task(str(folder), state[stage], 'text-to-3d', stage, DESIGNS[kind], [stage + '.glb'])
        print(kind, stage, 'credits', receipt.get('consumed_credits'), flush=True)

if __name__ == '__main__':
    authenticate()
    with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
        try:
            api._cmd_check_env(None)
        except SystemExit as result:
            if result.code: raise
    with redirect_stderr(StringIO()):
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(generate, DESIGNS))
