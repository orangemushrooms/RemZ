"""Bake exact convex planes; runtime requires only the generated Godot resource.

First run Godot's tests/export_zombie_hit_shapes.gd through tests/run.gd.
No mesh/texture/animation is modified, and interior-vertex removal is lossless.
"""
import json
from pathlib import Path

import numpy as np
from scipy.spatial import ConvexHull

ROOT = Path(__file__).resolve().parents[1]
source = json.loads((ROOT / 'artifacts/zombie-hit-shapes.json').read_text())
lines = ['[gd_resource type="Resource" format=3]', '', '[resource]', 'metadata/volumes = {']
count = 0
for key, bones in source.items():
    lines.append(f'{json.dumps(key)}: {{')
    for bone, data in bones.items():
        points = np.array(data['points'], dtype=np.float64)
        hull = ConvexHull(points)
        # Qhull normals point outwards, Godot's Plane uses n.dot(x) = d.
        planes = sorted(set(tuple(np.round([*equation[:3], -equation[3]], 9)) for equation in hull.equations))
        encoded = ', '.join('Plane(' + ', '.join(f'{value:.9g}' for value in plane) + ')' for plane in planes)
        lines.append(f'{int(bone)}: {{"hash": {json.dumps(data["hash"])}, "planes": Array[Plane]([{encoded}])}},')
        count += 1
    lines.append('},')
lines.append('}')
target = ROOT / 'godot/assets/data/zombie_hit_volumes.tres'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(f'Baked {count} exact convex hulls from {len(source)} meshes into {target.relative_to(ROOT)}')
