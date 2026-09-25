"""Zombie skins, third generation (Sep 2026): Meshy 7.1, PBR 4k, T-pose rig, full clip set.

Resumable per skin: assets/raw/<name>_v3/state.json keeps every task id, so a killed run
continues where it stopped and never pays twice. Stages: design (text-to-image, nano-banana-pro,
T-pose reference sheet - look at design.png before paying for the mesh) -> model (image-to-3d,
Meshy 7.1, 4k geometry, 4k PBR) -> rig (1.7 m) -> anims (library clips per role).
    python tools/zombies_v3.py balance
    python tools/zombies_v3.py plan
    python tools/zombies_v3.py generate [names...] [--stage design|model|rig|anims|all] [--workers 4]
    python tools/zombies_v3.py redesign <name>        # throw a bad reference sheet away and draw a new one
    python tools/zombies_v3.py status
Afterwards: node tools/pack.mjs <name>_v3 --size 2048 --albedo-size 4096 (see pack.mjs) and
node tools/restore_pbr.mjs <name>_v3, then copy public/models/<name>_v3.glb to
godot/assets/models/<name>.glb and run Godot.exe --headless --path godot --import.
The key stays in this process; it is only sent in the Authorization header to api.meshy.ai.
"""
import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Lock

from progression_assets import ROOT, api, authenticate

T2I = '/openapi/v1/text-to-image'
I2D = '/openapi/v1/image-to-3d'
RIG = '/openapi/v1/rigging'
ANIM = '/openapi/v1/animations'
LOCK = Lock()
RIG_HEIGHT = 1.7            # Zombie._fit_model scales every rig from 1.7 m to the type height
GEOMETRY = '4k'
TEXTURE = '4k'

POSE = (' Full-body photo, front view, strict T-pose: arms straight out horizontally to the sides, palms down, '
        'legs straight and slightly apart, facing the camera, whole body from head to feet visible and centred with '
        'margin, plain uniform mid-grey studio background, soft even light, photorealistic, highly detailed, '
        'no weapon, no text, no watermark.')
DECAY = ' Undead: pale grey necrotic skin, dark veins, sunken eyes, open wounds, dried black blood.'
SKIN_TEX = ('Photorealistic 4K PBR. Pale grey-green necrotic skin with visible pores, dark veins, bruises, open '
            'wounds and dried blackened blood; ')
TEX_END = ' Mud and grime, fine fabric weave, natural wear, no painted lighting, no text, no logos.'

# Meshy animation library action ids (https://api.meshy.ai/web/public/animations/resources):
# 112 Frankenstein Walk, 562 Stumble Walk, 553 Elderly Shaky Walk, 119 Slow Orc Walk, 123 Unsteady Walk,
# 16 Run Fast, 512 Male Head-down Charge, 510 Standard Forward Charge, 214 Punch Forward with Both Fists,
# 221 Charged Upward Slash, 212 Elbow Strike, 128 Heavy Hammer Swing, 127 Charged Ground Slam,
# 184 Shot and Fall Forward, 189 Dying Backwards, 183 Shot and Fall Backward, 178/179 Hit Reaction,
# 177 Gunshot Reaction, 0/12 Idle, 255 Angry Ground Stomp, 386 Zombie Scream.
# 25 Sep 2026: death4 = 185 Shot and Slow Fall Backward, death5 = 188 Fall Dead from Abdominal Injury; 183
# (the stiff plank fall with spread arms) stays in the files but zombie._death_clip never picks it.
SHAMBLE = {'walk': 112, 'walk2': 562, 'attack': 214, 'attack2': 221, 'death': 184, 'death2': 189, 'death3': 183,
           'death4': 185, 'death5': 188, 'hit': 178, 'hit2': 177, 'idle': 0, 'scream': 386}
RUNNER = {'run': 16, 'walk': 123, 'attack': 214, 'attack2': 212, 'death': 184, 'death2': 183, 'death3': 189,
          'death4': 185, 'death5': 188, 'hit': 177, 'hit2': 179, 'idle': 12, 'scream': 386}
TITAN = {'walk': 119, 'walk2': 112, 'attack': 127, 'attack2': 128, 'death': 189, 'death2': 184, 'idle': 255,
         'scream': 386}

SPECS = {
    'zombie_shambler': dict(
        prompt='Photorealistic AAA game character, a rotting male zombie villager: torn red-and-black plaid flannel '
               'shirt over a stained undershirt, worn blue jeans with ripped knee, muddy leather work boots, '
               'unkempt short hair, slack jaw.' + DECAY + POSE,
        texture=SKIN_TEX + 'faded red-black plaid flannel with frayed tears, dirty denim, scuffed brown leather boots.' + TEX_END,
        anims=SHAMBLE, polycount=50000),
    'zombie_farmer': dict(
        prompt='Photorealistic AAA game character, a Swiss farmer turned zombie: faded blue work dungarees over a torn '
               'green checked shirt, sleeves rolled up, green rubber boots, weathered face with grey stubble, '
               'slack jaw.' + DECAY + POSE,
        texture=SKIN_TEX + 'faded blue denim dungarees with brass buckles, dirty green checked flannel, dark green rubber boots caked in dried mud.' + TEX_END,
        anims=SHAMBLE, polycount=50000),
    'zombie_hiker': dict(
        prompt='Photorealistic AAA game character, a zombie hiker: torn red softshell outdoor jacket, grey hiking '
               'trousers, brown leather hiking boots, small grey daypack with straps, short hair, head tilted, '
               'mouth open.' + DECAY + POSE,
        texture=SKIN_TEX + 'weathered red softshell fabric with ripped seams, grey ripstop trousers, brown leather boots, dusty grey daypack.' + TEX_END,
        anims=SHAMBLE, polycount=50000),
    'zombie_grandma': dict(
        prompt='Photorealistic AAA game character, an elderly woman zombie: faded floral apron dress to the shins, '
               'beige knitted cardigan, grey hair in a loose bun, thick stockings, worn felt slippers, hunched '
               'thin frame, wrinkled sunken face.' + DECAY + POSE,
        texture=SKIN_TEX + 'wrinkled pale skin, faded floral cotton dress, beige knitted wool cardigan with loose threads, grey hair, worn felt slippers.' + TEX_END,
        anims=dict(SHAMBLE, walk2=553), polycount=50000),
    'zombie_runner': dict(
        prompt='Photorealistic AAA game character, a lean athletic infected zombie: ripped dark grey hoodie with the '
               'hood down, torn cargo pants, worn sneakers, emaciated body, tendons visible, bloody screaming '
               'mouth, wide eyes.' + DECAY + POSE,
        texture=SKIN_TEX + 'ripped dark grey cotton hoodie with blood splatter, olive cargo pants, dirty white sneakers.' + TEX_END,
        anims=RUNNER, polycount=50000),
    'zombie_jogger': dict(
        prompt='Photorealistic AAA game character, a thin fast zombie jogger: neon yellow running shirt, black '
               'running shorts, running shoes with white socks, emaciated grey body, open screaming mouth, '
               'veins on the neck.' + DECAY + POSE,
        texture=SKIN_TEX + 'neon yellow synthetic mesh shirt with blood stains, black polyester shorts, worn running shoes, white socks.' + TEX_END,
        anims=dict(RUNNER, run=512), polycount=50000),
    'zombie_nurse': dict(
        prompt='Photorealistic AAA game character, an undead nurse: blood-stained white uniform dress to the knees, '
               'torn sleeves, white stockings and clogs, hair tied back, name badge, gaunt face with bloody '
               'mouth.' + DECAY + POSE,
        texture=SKIN_TEX + 'white cotton nurse uniform heavily stained with dark dried blood, torn sleeves, white stockings, scuffed white clogs.' + TEX_END,
        anims=dict(RUNNER, run=510), polycount=50000),
    'zombie_soldier': dict(
        prompt='Photorealistic AAA game character, an undead Swiss army soldier: ripped woodland camouflage uniform, '
               'black tactical vest with pouches, combat helmet with cover, black combat boots, knee pads, '
               'rotting face under the helmet.' + DECAY + POSE,
        texture=SKIN_TEX + 'torn muddy woodland camouflage fabric, black nylon tactical vest with worn pouches, scuffed black leather boots, helmet cover.' + TEX_END,
        anims=SHAMBLE, polycount=50000),
    'zombie_forester': dict(
        prompt='Photorealistic AAA game character, a zombie forestry worker: orange high-visibility work jacket with '
               'grey reflective stripes, dark green chainsaw protection trousers, steel-toe boots, orange forestry '
               'helmet with mesh visor and ear muffs, rotting face.' + DECAY + POSE,
        texture=SKIN_TEX + 'orange hi-vis polyester with grey reflective stripes and dirt, dark green chainsaw trousers, scratched orange helmet, brown leather boots.' + TEX_END,
        anims=SHAMBLE, polycount=50000),
    'zombie_bloater': dict(
        prompt='Photorealistic AAA game character, a huge bloated zombie brute: massively swollen bare torso with '
               'burst skin, boils and stretched veins, thick arms, torn blue overalls hanging from the waist, bare '
               'feet, small head sunk into the shoulders, gaping jaw.' + DECAY + POSE,
        texture=SKIN_TEX + 'bloated pale yellow-grey skin with pus-filled boils, burst stretch marks, torn dirty blue overalls.' + TEX_END,
        anims=dict(SHAMBLE, walk=119, walk2=112, attack2=128, idle=255), polycount=55000),
    # 26 Sep 2026: the three special infected of the weather / mutation batch (spitter, screamer, stalker)
    'zombie_spitter': dict(
        prompt='Photorealistic AAA game character, a bloated acid zombie: grotesquely swollen bare torso, translucent '
               'yellow-green skin with glowing acid sacs on the throat, chest and belly, burst boils, green slime '
               'dripping from the mouth, torn brown overalls hanging from the waist, bare feet, head sunk into the '
               'shoulders, jaw hanging open.' + DECAY + POSE,
        texture=SKIN_TEX + 'translucent yellow-green bloated skin lit from within by lime-green acid sacs, burst boils, green slime, torn brown overalls.' + TEX_END,
        anims=dict(SHAMBLE, walk=119, walk2=112, attack2=128, idle=255), polycount=55000),
    'zombie_screamer': dict(
        prompt='Photorealistic AAA game character, a screamer zombie woman: gaunt emaciated body, chalk-white dead '
               'skin, black veins spreading from a torn-open gaping mouth with the jaw ripped wide, black hollow eye '
               'sockets, long matted black hair, shredded grey hospital gown to the knees, bare feet.' + DECAY + POSE,
        texture=SKIN_TEX + 'chalk-white necrotic skin with black veins, black hollow eye sockets, torn grey cotton gown with dark blood, matted black hair.' + TEX_END,
        anims=dict(RUNNER, run=510), polycount=50000),
    'zombie_stalker': dict(
        prompt='Photorealistic AAA game character, a stalker zombie that hides in maize fields: lean wiry body, '
               'soot-black mud-caked skin and rags, dried corn husks and leaves stuck all over the body and head, '
               'ragged dark trousers, bare feet, hunched posture, pale glinting eyes, mouth open.' + DECAY + POSE,
        texture=SKIN_TEX + 'soot-black mud-caked skin, very dark matte rags, dried yellow corn husks and leaves stuck to the body, pale eyes.' + TEX_END,
        anims=dict(RUNNER, walk=559), polycount=50000),
    'zombie_titan': dict(
        prompt='Photorealistic AAA game character, a colossal grotesque zombie titan: emaciated giant humanoid with '
               'overlong arms and huge clawed hands, exposed ribcage and spine, torn grey rotting skin hanging in '
               'strips, several milky eyes, gaping jaw with broken teeth, remnants of clothing.' + POSE,
        texture='Photorealistic 4K PBR. Grey-green rotting flesh with deep creases and pores, black veins, exposed yellowed bone, dried dark blood, torn cloth rags.' + TEX_END,
        anims=TITAN, polycount=60000),
    'zombie_colossus': dict(
        prompt='Photorealistic AAA game character, a colossal forest zombie titan: gaunt giant humanoid with an '
               'elongated skull, sunken chest, long arms with clawed hands, mossy bark-like grey-green skin with '
               'roots and fungus growing from the shoulders and back, exposed ribs, cluster of pale eyes, torn '
               'jaw.' + POSE,
        texture='Photorealistic 4K PBR. Grey-green necrotic skin with bark-like cracks, patches of moss and fungus, black veins, exposed bone, dried blood.' + TEX_END,
        anims=TITAN, polycount=60000),
}

STAGES = ['design', 'model', 'rig', 'anims']


def log(*parts):
    with LOCK:
        print(time.strftime('%H:%M:%S'), *parts, flush=True)


def headers():
    return api._make_headers(api.load_api_key())


def request(method, path, payload=None, tries=6):
    for attempt in range(tries):
        try:
            response = api.SESSION.request(method, api.BASE + path, headers=headers(), json=payload, timeout=60)
        except Exception as error:          # network hiccup: retry
            log('retry', path, error)
            time.sleep(15)
            continue
        if response.status_code in (429, 500, 502, 503, 504):
            log('retry', path, response.status_code, response.text[:200])
            time.sleep(20 * (attempt + 1))
            continue
        if response.status_code == 402:
            raise RuntimeError('Insufficient Meshy credits')
        if not response.ok:
            raise RuntimeError('%s %s -> %d %s' % (method, path, response.status_code, response.text[:300]))
        return response.json()
    raise RuntimeError('gave up on ' + path)


def create(endpoint, payload):
    return request('POST', endpoint, payload)['result']


def wait(endpoint, task_id, label, timeout=2400):
    started = time.time()
    shown = -1
    while time.time() - started < timeout:
        task = request('GET', '%s/%s' % (endpoint, task_id))
        status = task.get('status')
        progress = int(task.get('progress') or 0)
        if progress // 25 != shown:
            shown = progress // 25
            log(label, status, str(progress) + '%')
        if status == 'SUCCEEDED':
            return task
        if status in ('FAILED', 'CANCELED', 'EXPIRED'):
            raise RuntimeError('%s %s: %s' % (label, status, (task.get('task_error') or {}).get('message', '')))
        time.sleep(12)
    raise RuntimeError(label + ' timed out')


def fetch(url, target):
    if url and not target.exists():
        api.download(url, str(target))


class Skin:
    def __init__(self, name):
        self.name = name
        self.spec = SPECS[name]
        self.folder = ROOT / 'assets/raw' / (name + '_v3')
        self.folder.mkdir(parents=True, exist_ok=True)
        self.state_file = self.folder / 'state.json'
        self.state = json.loads(self.state_file.read_text()) if self.state_file.exists() else {}

    def save(self):
        with LOCK:
            self.state_file.write_text(json.dumps(self.state, indent=2))

    def receipt(self, stage, endpoint, task_id):
        path = self.folder / ('task_%s.json' % stage)
        if path.exists():
            task = json.loads(path.read_text())
            if task.get('status') == 'SUCCEEDED':
                return task
        task = wait(endpoint, task_id, '%s %s' % (self.name, stage))
        path.write_text(json.dumps(task, indent=2))
        log(self.name, stage, 'done, credits', task.get('consumed_credits'))
        return task

    def design(self):
        if 'design' not in self.state:
            payload = dict(ai_model='nano-banana-pro', prompt=self.spec['prompt'], pose_mode='t-pose', aspect_ratio='3:4')
            (self.folder / 'design_request.json').write_text(json.dumps(payload, indent=2))
            self.state['design'] = create(T2I, payload)
            self.save()
            log(self.name, 'design task', self.state['design'])
        task = self.receipt('design', T2I, self.state['design'])
        urls = task.get('image_urls') or task.get('result', {}).get('image_urls') or []
        if urls:
            fetch(urls[0], self.folder / 'design.png')
        return task

    def model(self):
        if 'model' not in self.state:
            payload = dict(input_task_id=self.state['design'], ai_model='meshy-7.1', geometry_resolution=GEOMETRY,
                           should_remesh=True, topology='triangle', target_polycount=self.spec['polycount'],
                           should_texture=True, enable_pbr=True, texture_resolution=TEXTURE, pose_mode='t-pose',
                           image_enhancement=False, multi_view_thumbnails=True, target_formats=['glb'])
            (self.folder / 'model_request.json').write_text(json.dumps(payload, indent=2))
            self.state['model'] = create(I2D, payload)
            self.save()
            log(self.name, 'model task', self.state['model'])
        task = self.receipt('model', I2D, self.state['model'])
        fetch(task['model_urls']['glb'], self.folder / 'model.glb')
        fetch(task.get('thumbnail_url'), self.folder / 'thumb.png')
        views = task.get('thumbnail_urls') or {}
        if isinstance(views, dict):
            for view, url in views.items():
                fetch(url, self.folder / ('view_%s.png' % view))
        return task

    def rig(self):
        if 'rig' not in self.state:
            self.state['rig'] = create(RIG, dict(input_task_id=self.state['model'], height_meters=RIG_HEIGHT))
            self.save()
            log(self.name, 'rig task', self.state['rig'])
        task = self.receipt('rig', RIG, self.state['rig'])
        result = task['result']
        fetch(result['rigged_character_glb_url'], self.folder / 'rigged.glb')
        basic = result.get('basic_animations', {})
        fetch(basic.get('walking_glb_url'), self.folder / 'basic_walking.glb')
        fetch(basic.get('running_glb_url'), self.folder / 'basic_running.glb')
        return task

    def anims(self):
        tasks = self.state.setdefault('anims', {})
        for label, action in self.spec['anims'].items():
            if label not in tasks:
                tasks[label] = create(ANIM, dict(rig_task_id=self.state['rig'], action_id=int(action)))
                self.save()
                log(self.name, 'anim', label, action, tasks[label])
                time.sleep(1.5)
        for label, task_id in tasks.items():
            target = self.folder / ('anim_%s.glb' % label)
            if target.exists():
                continue
            task = self.receipt('anim_' + label, ANIM, task_id)
            fetch(task['result']['animation_glb_url'], target)

    def run(self, until):
        try:
            for stage in STAGES:
                getattr(self, stage)()
                if stage == until:
                    break
            log(self.name, 'READY up to', until)
            return True
        except Exception as error:
            log(self.name, 'FAILED:', error)
            return False


def status():
    for name in SPECS:
        skin = Skin(name)
        have = [stage for stage in STAGES if stage in skin.state]
        clips = sorted(p.name[5:-4] for p in skin.folder.glob('anim_*.glb'))
        print('%-18s stages=%s rigged=%s clips=%s' % (name, ','.join(have), (skin.folder / 'rigged.glb').exists(), clips))


def plan():
    total = 0
    for name, spec in SPECS.items():
        cost = 9 + 35 + 5 + 3 * len(spec['anims'])
        total += cost
        print('%-18s polys=%d clips=%d ~%d credits (%d chars prompt)' % (
            name, spec['polycount'], len(spec['anims']), cost, len(spec['prompt'])))
    print('estimated total ~%d credits for %d skins' % (total, len(SPECS)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['balance', 'plan', 'status', 'generate', 'redesign'])
    parser.add_argument('names', nargs='*')
    parser.add_argument('--stage', default='anims', choices=STAGES + ['all'])
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    if args.action == 'plan':
        plan()
        return
    if args.action == 'status':
        status()
        return
    authenticate()
    if args.action == 'balance':
        print('Balance:', request('GET', '/openapi/v1/balance'))
        return
    names = args.names or list(SPECS)
    for name in names:
        assert name in SPECS, 'unknown skin ' + name
    if args.action == 'redesign':
        for name in names:
            skin = Skin(name)
            for key in ('design', 'model', 'rig', 'anims'):
                skin.state.pop(key, None)
            skin.save()
            for stale in list(skin.folder.glob('design*')) + list(skin.folder.glob('task_*.json')) + list(skin.folder.glob('*.glb')) + list(skin.folder.glob('view_*.png')) + list(skin.folder.glob('thumb.png')):
                stale.unlink()
            skin.design()
        return
    until = 'anims' if args.stage == 'all' else args.stage
    log('generating', names, 'up to', until)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda name: Skin(name).run(until), names))
    print('Balance:', request('GET', '/openapi/v1/balance'))
    failed = [name for name, ok in zip(names, results) if not ok]
    print('ZOMBIES_V3_DONE ok=%d failed=%s' % (len(names) - len(failed), failed))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
