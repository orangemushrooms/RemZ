"""Reference-first replacement worm assets; resumable, using bundled Meshy helpers.

Run `design`, inspect both design.png files, then `model`. Originals and task
receipts remain under meshy_output; prepare_earthworms.mjs builds runtime GLBs.
"""
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Lock
from progression_assets import authenticate, api, ROOT

OUT = ROOT / 'meshy_output' / 'earthworm_quality'
LOCK = Lock()
BASE = '''A single production-quality photoreal survival-horror creature asset, isolated on a plain mid-grey studio background, soft neutral diffuse light. Entire creature visible with generous margins, three-quarter FRONT view, camera nearly level. An enormous undead EARTHWORM, absolutely limbless and eyeless. One continuous muscular annelid body, standing nearly STRAIGHT VERTICALLY, tapering steadily to a closed small tail at the BOTTOM. The entire tail points straight DOWN, no coil, no U bend, no hooked tail. Length 5 times maximum body diameter. ONE huge circular mouth at the TOP, tilted 35 degrees forwards towards camera so we see its deep funnel-shaped throat. No human face, eyes, nose, arms, legs, tentacles or antennae. Mouth diameter about 1.2 times body width. Three irregular nested rings of individually sculpted backward-curving ivory teeth rooted in dark burgundy gums, a deep pitch-black throat. The mouth is part of the body's end, not on the side. Thick muscular collar below the maw. Natural irregular annular segments with deep creases, fine longitudinal wrinkles, pores, sparse tiny broken bristles, asymmetrical scars and patches of attached dried soil. Detailed organic sculpture, convincing weight and thickness, subtle anatomical asymmetry, realistic diseased flesh. NOT smooth plastic, not a toy, not cartoon, no perfect accordion rings, no humanoid teeth, no white highlights painted onto skin. No ground, rocks, base, props, fog, scenery, text or multiple views. High-end realistic game creature sculpt with detailed PBR materials.'''
SPECS = {
    'zombie_earthworm': BASE + ' Colour: mottled desaturated liver-brown and bruised violet flesh, grey necrotic patches and muddy seams. Predominantly matte leathery outer skin, moist mouth interior only. Powerful thick body, broad ragged fleshy lip with short irregular hooked teeth.',
    'zombie_earthworm_ancient': BASE + ' Ancient variant: heavier upper body and flared armoured collar. Ash-grey and charcoal dead skin with irregular overlapping chalky calcified plates embedded in the rings, chipped ridges and old healed scars. Larger ragged ivory fangs around a dark maroon maw. Discontinuous bone armour organically follows the body, no long spikes. Matte weathered surface; moist mouth interior only.',
}


def generate(name, stage):
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    statefile = folder / 'state.json'
    state = json.loads(statefile.read_text()) if statefile.exists() else {}
    is_design = stage.startswith('design')
    endpoint = '/openapi/v1/text-to-image' if is_design else '/openapi/v1/image-to-3d'
    if is_design:
        prompt = SPECS[name]
        if stage == 'design_straight':
            prompt = prompt.replace('standing nearly STRAIGHT VERTICALLY', 'FLOATING freely in mid-air, suspended from the head with its entire straight body hanging down vertically')
            prompt += ' Mandatory pose: the whole tail hangs freely DOWN like a hanging carrot, floating well above any surface. Absolutely no contact with floor. No resting on tail, no curl, no coil, no side-pointing tail. Thin tail tip is at the lowest point directly below the head.'
        payload = dict(ai_model='nano-banana-pro', prompt=prompt, aspect_ratio='3:4')
    else:
        assert 'design' in state, 'Generate and visually inspect design.png first'
        payload = dict(input_task_id=state.get('design_straight', state['design']), ai_model='meshy-7.1',
            geometry_resolution='4k', should_remesh=True, topology='triangle',
            target_polycount=60000 if name == 'zombie_earthworm' else 70000,
            should_texture=True, enable_pbr=True, texture_resolution='4k',
            image_enhancement=False, multi_view_thumbnails=True, target_formats=['glb'])
    if stage not in state:
        (folder / (stage + '_request.json')).write_text(json.dumps(payload, indent=2))
        state[stage] = api.create_task(endpoint, payload)
        statefile.write_text(json.dumps(state, indent=2))
    receipt_file = folder / (stage + '_task.json')
    receipt = json.loads(receipt_file.read_text()) if receipt_file.exists() else api.poll_task(endpoint, state[stage], timeout=1800)
    receipt_file.write_text(json.dumps(receipt, indent=2))
    if is_design:
        urls = receipt.get('image_urls') or receipt.get('result', {}).get('image_urls')
        assert urls, 'No design image in task result'
        downloads = {stage + '.png': urls[0]}
    else:
        downloads = {'model.glb': receipt['model_urls']['glb']}
        if receipt.get('thumbnail_url'): downloads['thumbnail.png'] = receipt['thumbnail_url']
        thumbs = receipt.get('thumbnail_urls', {})
        if isinstance(thumbs, dict):
            for view, url in thumbs.items(): downloads['view_' + view + '.png'] = url
    for filename, url in downloads.items():
        target = folder / filename
        if not target.exists(): api.download(url, str(target))
    with LOCK:
        api.record_task(str(folder), state[stage], endpoint.rsplit('/', 1)[-1], stage, name, list(downloads))
    print('READY', name, stage, 'credits', receipt.get('consumed_credits'), flush=True)


if __name__ == '__main__':
    authenticate()
    stage = sys.argv[1]
    if stage == 'balance':
        result = api.SESSION.get(api.BASE + '/openapi/v1/balance', headers=api._make_headers(api.load_api_key()), timeout=30)
        result.raise_for_status()
        print('Balance:', result.json())
        sys.exit(0)
    assert stage in ['design', 'design_straight', 'model']
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [pool.submit(generate, name, stage) for name in (sys.argv[2:] or SPECS)]
        for job in jobs: job.result()
