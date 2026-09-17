"""Bounded Meshy hand study; API credentials remain in this process only."""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.claude/skills/meshy-3d-generation/scripts'))
from meshy_task import SESSION, create_task, poll_task, download, get_project_dir, record_task, save_thumbnail

PROMPT = (
    'A single anatomically accurate adult RIGHT hand wearing a fitted charcoal tactical shooting glove, '
    'with wrist and forearm in an olive ripstop jacket sleeve ending at the elbow. '
    'The hand holds an imaginary narrow vertical pistol grip: middle, ring and little fingers naturally curled, '
    'index finger slightly extended towards the trigger, thumb resting along the upper side. '
    'Exactly five anatomically correct fingers with realistic proportions. Continuous hand and wrist anatomy, '
    'tailored glove seams, supple leather palm, textile back, natural cloth folds and fitted cuff. '
    'Professional photoreal first-person game asset, no toy shapes, no weapon, no other objects, no base.'
)
PREVIEW = {'mode': 'preview', 'prompt': PROMPT, 'ai_model': 'meshy-7',
           'ultra_mode': True, 'should_remesh': True, 'topology': 'triangle',
           'target_polycount': 24000, 'target_formats': ['glb']}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['balance', 'plan', 'generate'])
    args = parser.parse_args()
    os.chdir(ROOT)
    os.environ['MESHY_API_KEY'] = (ROOT / 'Meshy Key').read_text(encoding='utf-8-sig').strip()
    if args.action == 'balance':
        response = SESSION.get('https://api.meshy.ai/openapi/v1/balance',
                               headers={'Authorization': 'Bearer ' + os.environ['MESHY_API_KEY']}, timeout=20)
        print('Meshy authentication status:', response.status_code)
        if response.ok:
            print(json.dumps(response.json()))
        return
    folder = ROOT / 'meshy_output/hand_study'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'planned_preview.json').write_text(json.dumps(PREVIEW, indent=2), encoding='utf-8')
    print('Plan: one Meshy 7 Ultra preview (25 credits) + 4K PBR refine (10 credits); GLB; total 35 credits.')
    if args.action == 'plan':
        return
    state_file = folder / 'state.json'
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    def save():
        state_file.write_text(json.dumps(state, indent=2), encoding='utf-8')
    if 'preview' not in state:
        state['preview'] = create_task('/openapi/v2/text-to-3d', PREVIEW)
        state['directory'] = get_project_dir(state['preview'], 'realistic gloved right hand')
        save()
    project = Path(state['directory'])
    task = poll_task('/openapi/v2/text-to-3d', state['preview'], timeout=1200)
    (project / 'preview_task.json').write_text(json.dumps(task, indent=2), encoding='utf-8')
    if not (project / 'preview.glb').exists():
        download(task['model_urls']['glb'], str(project / 'preview.glb'))
        if task.get('thumbnail_url'):
            download(task['thumbnail_url'], str(project / 'preview.png'))
        record_task(str(project), state['preview'], 'text-to-3d', 'preview', PROMPT, ['preview.glb'])
    if 'refine' not in state:
        state['refine'] = create_task('/openapi/v2/text-to-3d', {
            'mode': 'refine', 'preview_task_id': state['preview'], 'enable_pbr': True,
            'texture_resolution': '4k', 'target_formats': ['glb'],
            'texture_prompt': 'Photoreal worn charcoal leather and grey textile tactical glove, fine stitching, subtle roughness, olive ripstop sleeve with fabric weave and natural creases. No logos, no painted lighting.'})
        save()
    task = poll_task('/openapi/v2/text-to-3d', state['refine'], timeout=1200)
    (project / 'refine_task.json').write_text(json.dumps(task, indent=2), encoding='utf-8')
    if not (project / 'model.glb').exists():
        download(task['model_urls']['glb'], str(project / 'model.glb'))
        if task.get('thumbnail_url'):
            download(task['thumbnail_url'], str(project / 'refined.png'))
        record_task(str(project), state['refine'], 'text-to-3d', 'refined', PROMPT, ['model.glb'])
    print('MESHY_HAND_DONE', project)

if __name__ == '__main__':
    main()
