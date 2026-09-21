"""Read-only scan of Godot's model references and procedural visual sites."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / 'godot'
specs = json.loads((ROOT / 'tools/missing_assets.json').read_text())
references, primitives, catalogue_references = [], [], []
paths = sorted((GODOT / 'scripts').glob('*.gd')) + sorted((GODOT / 'scenes').glob('*.tscn'))
for path in paths:
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        for resource in re.findall(r'res://assets/[^"\s]+\.(?:glb|res)', line):
            if '%' not in resource and '{' not in resource:
                references.append(dict(file=str(path.relative_to(ROOT)), line=number,
                    resource=resource, exists=(GODOT / resource.removeprefix('res://')).exists()))
        if re.search(r'(?:Box|Cylinder|Sphere|Capsule|Prism|Torus)Mesh\.new', line):
            primitives.append(dict(file=str(path.relative_to(ROOT)), line=number, source=line.strip()))
        for name in re.findall(r'"model"\s*:\s*"([\w-]+)"', line):
            catalogue_references.append(dict(file=str(path.relative_to(ROOT)), line=number,
                model=name, exists=(GODOT / 'assets/models' / (name + '.glb')).exists()))
result = dict(models=len(list((GODOT / 'assets/models').glob('*.glb'))),
    literal_references=references, missing_literal_references=[r for r in references if not r['exists']],
    missing_catalogue_references=[r for r in catalogue_references if not r['exists']],
    generated_batch={name:(GODOT / 'assets/models' / (name + '.glb')).exists() for name in specs},
    procedural_sites=primitives)
output = ROOT / 'artifacts/model-audit'
output.mkdir(parents=True, exist_ok=True)
(output / 'scan.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k not in ['literal_references','procedural_sites']}, indent=2))
