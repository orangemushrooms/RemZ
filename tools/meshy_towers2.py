"""Resumable Meshy weapon assemblies for the eight towers of 2 Oct 2026; never prints credentials.

Same route as the first five towers (tools/meshy_towers.py, 21 Sep 2026): text-to-3d preview with meshy-7.1
(25 credits) and a PBR refine (10 credits) per assembly. The state file meshy_output/tower_<kind>_state.json
makes every stage resumable, and --stage preview stops before the refine so the free preview thumbnail can be
judged first (the budget on 2 Oct was 260 credits for six to seven assemblies, no room for blind retries).

  python tools/meshy_towers2.py --stage preview rocket frost harpoon graviton sniper searchlight
  python tools/meshy_towers2.py --stage refine rocket ...        after the previews were looked at
  python tools/meshy_towers2.py --balance

Then: node tools/prepare_towers2.mjs <kind...>  (fit to the shared gun pivot) and the Godot import.
"""
import argparse
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
STYLE = (' Realistic post apocalyptic survival game prop, convincing functional proportions, weathered steel. '
         'Weapon assembly only, no tower, no pedestal, no tripod, no people, no scenery, no ground, no text. '
         'Isolated complete object.')
TEXTURE = ('Realistic worn gunmetal, brushed steel, subtle rust and scratches, muted olive drab painted housing, '
           'copper and rubber details. PBR materials, no baked lighting, no text.')
SPECS = {
    'rocket': 'A heavy mounted four-tube rocket launcher pod weapon assembly: a square two by two cluster of thick '
              'rocket tubes with open front muzzles pointing horizontally forward, a riveted blast shield plate around '
              'the muzzles, rear breech block with cables and a pressure gauge, side trunnion pivots, rear operator handles.',
    'frost': 'A heavy mounted cryogenic freeze cannon weapon assembly: a thick insulated nozzle barrel wrapped in '
             'frost covered copper cooling rings pointing horizontally forward, two blue liquid nitrogen tanks with '
             'pressure gauges and braided hoses beside the rear, a bulky compressor housing with vents, rear operator handles.',
    'harpoon': 'A heavy mounted harpoon gun weapon assembly like a whaling cannon: a short thick barrel pointing '
               'horizontally forward with a barbed steel harpoon loaded in the muzzle, a large rope winch drum with coiled '
               'steel cable under the breech, side trunnion pivots, a cocking lever, rear operator handles.',
    'graviton': 'A mounted gravity emitter weapon assembly: a short wide barrel pointing horizontally forward that '
                'ends in three open concentric steel rings held by struts, a dark glass core sphere inside the rings, '
                'thick power cables to a rear capacitor housing with heat sink fins and glowing violet indicator lamps, rear operator handles.',
    'sniper': 'A heavy mounted anti materiel sniper rifle weapon assembly: a very long slender barrel with a large '
              'muzzle brake pointing horizontally forward, a big telescopic scope on top of a rectangular receiver, a '
              'side box magazine, folded bipod under the barrel, rear operator handles.',
    'searchlight': 'A heavy military searchlight assembly: a large cylindrical lamp drum with a wide round glass lens '
                   'facing horizontally forward, a protective wire grid over the lens, louvre vents and handles on the drum, '
                   'mounted in a steel yoke with trunnions, a thick power cable, rear operator handles.',
    'siren': 'A heavy mounted air raid siren assembly: two large flared steel horn speakers side by side facing '
             'horizontally forward on a motor head, a red beacon lamp dome on top, an electric motor housing with cooling '
             'fins at the rear, cables, rear operator handles.',
    'supply': 'A field supply station assembly: a stack of olive drab ammunition crates with stencil free lids, a '
              'medical kit box with a white cross, a radio set with a whip antenna and a small water canister, strapped '
              'together on a steel pallet frame.',
}


def generate(kind, stage_limit):
    state_path = ROOT / 'meshy_output' / ('tower_' + kind + '_state.json')
    state_path.parent.mkdir(exist_ok=True)
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    prompt = SPECS[kind] + STYLE
    for stage in ['preview', 'refine']:
        if stage == 'refine' and stage_limit == 'preview':
            break
        if stage not in state:
            if stage == 'preview':
                payload = dict(mode='preview', prompt=prompt, ai_model='meshy-7.1', geometry_resolution='2k',
                               should_remesh=True, topology='triangle', target_polycount=14000, target_formats=['glb'])
            else:
                payload = dict(mode='refine', preview_task_id=state['preview'], enable_pbr=True,
                               texture_resolution='2k', texture_prompt=TEXTURE, target_formats=['glb'])
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
        if not target.exists() and receipt.get('model_urls', {}).get('glb'):
            api.download(receipt['model_urls']['glb'], str(target))
        thumb = folder / (stage + '.png')
        if receipt.get('thumbnail_url') and not thumb.exists():
            api.download(receipt['thumbnail_url'], str(thumb))
        with LOCK:
            api.record_task(str(folder), state[stage], 'text-to-3d', stage, prompt, [target.name])
        print(kind, stage, 'status', receipt.get('status'), 'credits', receipt.get('consumed_credits'), '->', folder.name, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('kinds', nargs='*')
    parser.add_argument('--stage', default='all', choices=['preview', 'refine', 'all'])
    parser.add_argument('--balance', action='store_true')
    args = parser.parse_args()
    authenticate()
    if args.balance:
        with redirect_stderr(StringIO()):
            api._cmd_balance(None)
        sys.exit(0)
    kinds = args.kinds or list(SPECS)
    unknown = [k for k in kinds if k not in SPECS]
    if unknown:
        sys.exit('unknown tower kinds: ' + ', '.join(unknown))
    with ThreadPoolExecutor(max_workers=max(1, len(kinds))) as pool:
        list(pool.map(lambda kind: generate(kind, args.stage), kinds))
