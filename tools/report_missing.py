"""Write local provenance without credentials or transient signed download URLs."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
specs = json.loads((ROOT / 'tools/missing_assets.json').read_text())
lines = ['# Meshy models from the project audit', '',
    'Generated 2026-09-21 with Meshy 7.1 preview + textured refine. GLB is the requested and returned model format. Game copies retain 2K PBR textures; originals, local thumbnails and complete receipts are in the folders below.', '',
    '| Game asset | Bytes | Preview task | Refine task | Credits |',
    '| --- | ---: | --- | --- | ---: |']
details, total = [], 0
for name in specs:
    state = json.loads((ROOT / 'meshy_output' / ('missing_' + name + '_state.json')).read_text())
    folder = Path(state['folder'])
    receipts = [json.loads((folder / (stage + '_task.json')).read_text()) for stage in ['preview','refine']]
    cost = sum(r['consumed_credits'] for r in receipts)
    total += cost
    game = ROOT / 'godot/assets/models' / (name + '.glb')
    lines.append(f"| `{name}.glb` | {game.stat().st_size} | `{state['preview']}` | `{state['refine']}` | {cost} |")
    details.append(f"- **{name}**: `{folder.relative_to(ROOT).as_posix()}/` — `preview.glb`, `refine.glb`, `refine.png`, `preview_task.json`, `refine_task.json`. Formats: {', '.join(k for k,v in receipts[1]['model_urls'].items() if v)}.")
    for failed in state.get('failed_attempts', []):
        details.append(f"  Meshy internal error on task `{failed['task_id']}`: FAILED, {failed['credits']} credits charged. Retried after checking the server receipt; failed receipt retained in the same folder.")
lines += ['', f'Total consumed by these 15 assets: **{total} credits**.', '',
    '## Originals and thumbnails', '', *details, '',
    '## Reproduction', '',
    '`tools/meshy_missing.py` resumes generation without duplicating completed tasks. `tools/prepare_missing.mjs` fits metres, aligns the standard turret muzzle, authors the owl wing rig, and compresses textures at their original 2K resolution. `tools/missing_assets.json` records prompts and fitting parameters. See `docs/MODELLSCAN.md` for integration and verification.', '']
(ROOT / 'godot/assets/models/missing.SOURCES.md').write_text('\n'.join(lines), encoding='utf-8')
print('ASSET_CREDITS', total)
