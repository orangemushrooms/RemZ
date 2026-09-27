"""Zombie skins of 27 Sep 2026 from the user's own Meshy web exports (fourth batch).

The sources come from the Meshy web app, whose tasks the API cannot see, so they enter as files:
  zombie_businessman  <- Zombie_Businessman_0927080636_texture.glb          (510 k triangles, T-pose)
  zombie_wastelander  <- Zombie_Risen_Wastelander_0927080523_texture.glb    (2.0 M, A-pose)
  zombie_wraith       <- Zombie_The_Ashen_Wraith_0927061543_texture.glb     (1.9 M, arms down)
  zombie_bride        <- Zombie_Boss_The_Wretched_Bride_0927080436_texture.glb (1.6 M, arms down)
  zombie_wanderer     <- Zombie_The_Decayed_Wanderer_biped_Animation_*_withSkin.glb (web rig, Mixamo
                         bone names and rotated bone frames: the API clips cannot be copied onto it)
The originals lie in assets/raw/<name>_v3/source.glb (web_<clip>.glb for the wanderer). Before this script:
  node tools/decimate_glb.mjs source.glb model.glb --triangles 33000        (bride 40000)
  node tools/decimate_glb.mjs model.glb rig_input.glb --triangles 999999 --base-only --base-size 1024
  node tools/unskin_glb.mjs web_Walking.glb model.glb                        (wanderer: bind pose, static)
Stages (resumable, assets/raw/<name>_v3/state.json keeps every task id):
  rig   -> POST /openapi/v1/rigging with rig_input.glb as a data URI, 1.7 m (5 credits)
  anims -> the library clips of the role below (3 credits each)
    python tools/new_zombies.py status
    python tools/new_zombies.py generate [names...] [--stage rig|anims] [--workers 5]
    python tools/new_zombies.py finish [names...]      # pack, repair, bake, ground, copy (see FINISH)
    python tools/new_zombies.py bride_repose           # the bride's A-pose upload from her first rig (see FINISH)
then Godot.exe --headless --path godot --import and rebake the shot volumes (CLAUDE.md).
The key stays in this process; it is only sent in the Authorization header to api.meshy.ai.
"""
import argparse
import base64
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import zombies_v3 as v3
from progression_assets import authenticate

# Library ids (https://api.meshy.ai/web/public/animations/resources, previews checked with
# tools/anim_contact_sheet.mjs): 3 Arise (getting up from lying face down - the spawn rise),
# 123 Unsteady Walk, 553 Elderly Shaky Walk (legs close: the dresses stay whole), 113 Mummy Stagger,
# 111 Injured Walk, 513 Female Head-down Charge, 219 Right-hand Sword Slash (an open-hand claw swipe),
# 0 / 11 hunched idles (12 flexes the arms like a bodybuilder), 391 Head Hold in Pain.
# The deaths leave out 183, the stiff plank fall that zombie._death_clip never picks.
DEATHS = {'death': 184, 'death2': 189, 'death3': 185, 'death4': 188}
SHAMBLE = dict(DEATHS, walk=112, walk2=113, attack=214, attack2=221, hit=178, hit2=177, idle=0, scream=386, arise=3)
SPECS = {
    # shambler skins
    'zombie_businessman': dict(anims=SHAMBLE),
    'zombie_wanderer': dict(anims=dict(SHAMBLE, walk=123, walk2=553)),
    # runner skin
    'zombie_wastelander': dict(anims=dict(DEATHS, run=16, walk=123, attack=214, attack2=221, hit=177, hit2=179,
                                          idle=11, scream=386, arise=3)),
    # stalker skin: the pale wraith appears only in a flashlight beam. Her narrow shoulder joints make 184 read
    # as a plank fall (zombie.is_plank), so 186 Strangled and Fall Forward is her forward fall.
    'zombie_wraith': dict(anims=dict(DEATHS, death5=186, walk=553, walk2=123, run=513, attack=221, attack2=219,
                                     hit=178, hit2=177, idle=0, scream=386, arise=3)),
    # the wretched bride leads the boss waves; 184 and 185 spread her arms like a mannequin, so she also
    # clutches her throat (186) and convulses to her knees (181 Electrocuted Fall)
    'zombie_bride': dict(anims=dict(DEATHS, death5=186, death6=181, walk=111, walk2=123, run=513, attack=221,
                                    attack2=219, hit=178, hit2=391, idle=0, scream=386, arise=3)),
}

# The finish of every skin after the clips (python tools/new_zombies.py finish [names]), all local:
#   pack.mjs (clips merged, 2k base colour restored from model.glb) -> skin_fix.mjs --fix for the arms-down
#   rigs (hair off the arms, claws off the thighs, the dresses as a hip / thigh blend) -> bake_normals.mjs
#   (the high-poly's detail into the normal map, MikkTSpace tangents) or only the material factors ->
#   ground_clips.mjs (every clip on the floor) -> godot/assets/models/<name>.glb. The T- and A-pose rigs keep
#   Meshy's weights: skin_fix made them worse (150 -> 1096 edges stretched past 2.5x on the businessman).
FINISH = {
    'zombie_businessman': dict(bake=True),
    'zombie_wanderer': dict(fix=['--hand-length', '0.2'], material='metallic=0,roughness=0.88'),
    'zombie_wastelander': dict(bake=True),
    'zombie_wraith': dict(fix=['--hair', '0.12', '--arm-reach', '3.0', '--skirt', 'hem=0.38,skin=0.07,leg=0.85,shin=0.25',
                               '--hand-length', '0.22'], bake=True),
    # re-rigged from an A-pose (bride_repose below): her own arms-down rig lifted the arms 60-70 deg too high
    # in every clip. The repaired weights of the first rig are transferred (tools/transfer_weights.mjs), the
    # normal map was baked before the re-pose and comes back through pack's restore; normals / tangents new.
    'zombie_bride': dict(transfer='zombie_bride_rig1_v3', retangent=True),
}
# the first rig of the bride (arms hanging), kept in assets/raw/zombie_bride_rig1_v3 with its receipts
BRIDE_RIG1_FIX = ['--hair', '0.12', '--arm-reach', '3.3', '--skirt', 'hem=0.14,skin=0.06,leg=0.8,shin=0.15', '--hand-length', '0.3']


def bride_repose():
    """First rig -> repaired weights -> bake -> A-pose upload for the rig in zombie_bride_v3 (rig and clips then
    come from generate zombie_bride, the finish transfers the first rig's weights)."""
    import subprocess
    first = v3.ROOT / 'assets/raw/zombie_bride_rig1_v3'
    folder = v3.ROOT / 'assets/raw/zombie_bride_v3'
    node = lambda *parts: subprocess.run(['node', '--max-old-space-size=8000', *map(str, parts)], cwd=v3.ROOT, check=True)
    node('tools/pack.mjs', 'zombie_bride_rig1_v3', '--size', 2048, '--albedo-size', 2048, '--quality', 90, '--restore-base', '--as', 'zombie_bride_rig1')
    node('tools/skin_fix.mjs', v3.ROOT / 'public/models/zombie_bride_rig1.glb', first / 'stage_fixed.glb', '--fix', *BRIDE_RIG1_FIX, '--report', 3)
    node('tools/bake_normals.mjs', first / 'stage_fixed.glb', first / 'stage_baked.glb', '--high', folder / 'source.glb')
    node('tools/repose_glb.mjs', first / 'stage_baked.glb', folder / 'model.glb', '--abduct', 40, '--straighten')
    node('tools/repose_glb.mjs', first / 'stage_baked.glb', folder / 'rig_input.glb', '--abduct', 40, '--straighten', '--base-only', '--base-size', 1024)
    for stale in ('public/models/zombie_bride_rig1.glb', 'public/models/zombie_bride_rig1.glb.json'):
        (v3.ROOT / stale).unlink(missing_ok=True)


def finish(name):
    import shutil
    import subprocess
    spec = FINISH[name]
    folder = v3.ROOT / 'assets/raw' / (name + '_v3')
    node = lambda *parts: subprocess.run(['node', '--max-old-space-size=8000', *map(str, parts)], cwd=v3.ROOT, check=True)
    node('tools/pack.mjs', name + '_v3', '--size', 2048, '--albedo-size', 2048, '--quality', 90, '--restore-base', '--as', name)
    current = v3.ROOT / 'public/models' / (name + '.glb')
    if spec.get('transfer'):
        first = v3.ROOT / 'assets/raw' / spec['transfer']
        node('tools/transfer_weights.mjs', first / 'stage_baked.glb', folder / 'model.glb', current, folder / 'stage_fixed.glb')
        current = folder / 'stage_fixed.glb'
    if spec.get('fix'):
        node('tools/skin_fix.mjs', current, folder / 'stage_fixed.glb', '--fix', *spec['fix'], '--report', 3)
        current = folder / 'stage_fixed.glb'
    if spec.get('bake'):
        node('tools/bake_normals.mjs', current, folder / 'stage_baked.glb', '--high', folder / 'source.glb')
    elif spec.get('retangent'):
        node('tools/bake_normals.mjs', current, folder / 'stage_baked.glb', '--retangent')
    else:
        node('tools/bake_normals.mjs', current, folder / 'stage_baked.glb', '--material', spec['material'])
    node('tools/ground_clips.mjs', folder / 'stage_baked.glb', folder / 'stage_grounded.glb')
    shutil.copyfile(folder / 'stage_grounded.glb', v3.ROOT / 'godot/assets/models' / (name + '.glb'))
    v3.log(name, 'finished -> godot/assets/models/%s.glb (run Godot --headless --import)' % name)


class WebSkin(v3.Skin):
    def __init__(self, name):
        self.name = name
        self.spec = SPECS[name]
        self.folder = v3.ROOT / 'assets/raw' / (name + '_v3')
        self.folder.mkdir(parents=True, exist_ok=True)
        self.state_file = self.folder / 'state.json'
        self.state = v3.json.loads(self.state_file.read_text()) if self.state_file.exists() else {}

    def rig(self):
        if 'rig' not in self.state:
            data = (self.folder / 'rig_input.glb').read_bytes()
            payload = dict(model_url='data:model/gltf-binary;base64,' + base64.b64encode(data).decode('ascii'),
                           height_meters=v3.RIG_HEIGHT)
            self.state['rig'] = v3.create(v3.RIG, payload)
            self.save()
            v3.log(self.name, 'rig task', self.state['rig'], '(%.1f MB upload)' % (len(data) / 1048576))
        task = self.receipt('rig', v3.RIG, self.state['rig'])
        result = task['result']
        v3.fetch(result['rigged_character_glb_url'], self.folder / 'rigged.glb')
        basic = result.get('basic_animations', {})
        v3.fetch(basic.get('walking_glb_url'), self.folder / 'basic_walking.glb')
        v3.fetch(basic.get('running_glb_url'), self.folder / 'basic_running.glb')
        return task

    def run(self, until):
        try:
            for stage in ('rig', 'anims'):
                getattr(self, stage)()
                if stage == until:
                    break
            v3.log(self.name, 'READY up to', until)
            return True
        except Exception as error:
            v3.log(self.name, 'FAILED:', error)
            return False


def status():
    for name in SPECS:
        skin = WebSkin(name)
        clips = sorted(p.name[5:-4] for p in skin.folder.glob('anim_*.glb'))
        print('%-20s rig=%s rigged=%s clips %d/%d %s' % (name, skin.state.get('rig', '-'), (skin.folder / 'rigged.glb').exists(),
                                                      len(clips), len(skin.spec['anims']), clips))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['status', 'generate', 'plan', 'finish', 'bride_repose'])
    parser.add_argument('names', nargs='*')
    parser.add_argument('--stage', default='anims', choices=['rig', 'anims'])
    parser.add_argument('--workers', type=int, default=5)
    args = parser.parse_args()
    if args.action == 'status':
        status()
        return
    if args.action == 'bride_repose':
        bride_repose()
        return
    if args.action == 'finish':
        for name in args.names or list(FINISH):
            finish(name)
        return
    if args.action == 'plan':
        total = 0
        for name, spec in SPECS.items():
            cost = 5 + 3 * len(spec['anims'])
            total += cost
            print('%-20s clips=%d ~%d credits' % (name, len(spec['anims']), cost))
        print('estimated total ~%d credits' % total)
        return
    authenticate()
    names = args.names or list(SPECS)
    for name in names:
        assert name in SPECS, 'unknown skin ' + name
    v3.log('generating', names, 'up to', args.stage)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda name: WebSkin(name).run(args.stage), names))
    print('Balance:', v3.request('GET', '/openapi/v1/balance'))
    failed = [name for name, ok in zip(names, results) if not ok]
    print('NEW_ZOMBIES_DONE ok=%d failed=%s' % (len(names) - len(failed), failed))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
