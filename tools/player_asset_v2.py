"""Image-guided Meshy survivor; resumable stages, originals retained for review."""
import base64
import json
from pathlib import Path
from progression_assets import authenticate, api

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/raw/player_survivor_v2'
STATE = OUT / 'state.json'
I2D = '/openapi/v1/image-to-3d'
RIG = '/openapi/v1/rigging'


def main():
    authenticate()
    OUT.mkdir(parents=True, exist_ok=True)
    state = json.loads(STATE.read_text()) if STATE.exists() else {}

    def stage(name, endpoint, payload):
        if name not in state:
            state[name] = api.create_task(endpoint, payload)
            STATE.write_text(json.dumps(state, indent=2))
        result = api.poll_task(endpoint, state[name], timeout=1800)
        (OUT / ('task_' + name + '.json')).write_text(json.dumps(result, indent=2))
        return result

    def fetch(url, name):
        if url and not (OUT / name).exists():
            api.download(url, str(OUT / name))

    payload = dict(ai_model='meshy-7.1', geometry_resolution='2k',
                   image_enhancement=False, should_texture=True, enable_pbr=True,
                   texture_resolution='4k', should_remesh=True,
                   target_polycount=60000, topology='triangle',
                   save_pre_remeshed_model=True, pose_mode='t-pose')
    (OUT / 'settings.json').write_text(json.dumps(payload, indent=2))
    payload['image_url'] = 'data:image/png;base64,' + base64.b64encode(
        (OUT / 'reference.png').read_bytes()).decode('ascii')
    print('Generating reference-guided survivor in Meshy', flush=True)
    result = stage('model', I2D, payload)
    fetch(result['model_urls']['glb'], 'model.glb')
    fetch(result.get('thumbnail_url'), 'thumb.png')
    print('Rigging at 1.80 metres', flush=True)
    result = stage('rig', RIG, dict(input_task_id=state['model'], height_meters=1.8))
    rig = result['result']
    fetch(rig['rigged_character_glb_url'], 'rigged.glb')
    for clip, key in [('walk', 'walking_glb_url'), ('run', 'running_glb_url')]:
        fetch(rig.get('basic_animations', {}).get(key), 'anim_' + clip + '.glb')
    print('PLAYER_V2_GENERATED', flush=True)


if __name__ == '__main__':
    main()
