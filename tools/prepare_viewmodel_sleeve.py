"""Extract the Meshy sleeve, preserving its UVs and all original PBR textures.

The authored glove supplies the finger rig. Sleeve vertices are stored around a
straight centreline with longitudinal Z in [0, 1], ready to fit each weapon pose.
No texture pixels are altered. Run after tools/meshy_hands.py generate.
"""
from pathlib import Path
import json
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
state = json.loads((ROOT / 'meshy_output/hand_study/state.json').read_text())
source = Path(state['directory']) / 'model.glb'
blob = source.read_bytes()
json_size = struct.unpack_from('<I', blob, 12)[0]
doc = json.loads(blob[20:20 + json_size])
binary = bytearray(blob[28 + json_size:])
primitive = doc['meshes'][0]['primitives'][0]

def accessor(index):
    desc = doc['accessors'][index]
    view = doc['bufferViews'][desc['bufferView']]
    dtype = {5126: '<f4', 5125: '<u4', 5123: '<u2'}[desc['componentType']]
    width = {'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[desc['type']]
    offset = view.get('byteOffset', 0) + desc.get('byteOffset', 0)
    return np.frombuffer(binary, dtype=dtype, count=desc['count'] * width,
                         offset=offset).reshape(-1, width).copy()

positions = accessor(primitive['attributes']['POSITION'])
normals = accessor(primitive['attributes']['NORMAL'])
uvs = accessor(primitive['attributes']['TEXCOORD_0'])
triangles = accessor(primitive['indices']).reshape(-1, 3)
cut = 0.015
bottom = float(positions[:, 1].min())
# Sample and smooth the centreline so the bent source arm can follow a new pose.
levels = np.linspace(bottom, cut, 40)
centres = []
radii = []
for level in levels:
    section = positions[np.abs(positions[:, 1] - level) < 0.035][:, [0, 2]]
    lo, hi = section.min(axis=0), section.max(axis=0)
    centres.append((lo + hi) * 0.5)
    radii.append((hi - lo) * 0.5)
centres = np.array(centres)
for _ in range(3):
    centres[1:-1] = (centres[:-2] + centres[1:-1] * 2 + centres[2:]) / 4
cuff_radius = np.array(radii[-1])

vertices, texcoords, transformed_normals = [], [], []
slopes = np.gradient(centres, levels, axis=0)
# Clip triangles at the cuff instead of dropping entire triangles: no ragged gap.
for triangle in triangles:
    polygon = [np.r_[positions[i], uvs[i], normals[i]] for i in triangle]
    clipped = []
    for i, end in enumerate(polygon):
        start = polygon[i - 1]
        in_start, in_end = start[1] <= cut, end[1] <= cut
        if in_start != in_end:
            fraction = (cut - start[1]) / (end[1] - start[1])
            clipped.append(start + (end - start) * fraction)
        if in_end:
            clipped.append(end)
    for i in range(1, len(clipped) - 1):
        for vert in [clipped[0], clipped[i], clipped[i + 1]]:
            centre = np.array([np.interp(vert[1], levels, centres[:, axis]) for axis in range(2)])
            radial = (vert[[0, 2]] - centre) / cuff_radius
            vertices.append([radial[0], radial[1], (cut - vert[1]) / (cut - bottom)])
            texcoords.append(vert[3:5])
            slope = np.array([np.interp(vert[1], levels, slopes[:, axis]) for axis in range(2)])
            nx, ny, nz = vert[5:8]
            normal = np.array([nx * cuff_radius[0], nz * cuff_radius[1],
                               -(ny + nx * slope[0] + nz * slope[1]) * (cut - bottom)])
            transformed_normals.append(normal / max(np.linalg.norm(normal), 1e-8))
vertices = np.asarray(vertices, dtype='<f4')
texcoords = np.asarray(texcoords, dtype='<f4')
# Preserve authored smooth normals, including across UV seams.
normals = np.asarray(transformed_normals, dtype='<f4')

def append_array(values, kind, component=5126):
    while len(binary) % 4:
        binary.append(0)
    start = len(binary)
    binary.extend(values.tobytes())
    view_index = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': start, 'byteLength': values.nbytes})
    desc = {'bufferView': view_index, 'componentType': component, 'count': len(values), 'type': kind}
    if kind == 'VEC3':
        desc.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
    index = len(doc['accessors'])
    doc['accessors'].append(desc)
    return index

attributes = {'POSITION': append_array(vertices, 'VEC3'),
              'NORMAL': append_array(normals, 'VEC3'),
              'TEXCOORD_0': append_array(texcoords, 'VEC2')}
doc['meshes'] = [{'name': 'MeshyTailoredSleeve', 'primitives': [{'attributes': attributes, 'mode': 4, 'material': 0}]}]
doc['buffers'][0]['byteLength'] = len(binary)
for material in doc['materials']:
    material['doubleSided'] = False
encoded = json.dumps(doc, separators=(',', ':')).encode('utf-8')
encoded += b' ' * (-len(encoded) % 4)
binary += b'\0' * (-len(binary) % 4)
out = struct.pack('<III', 0x46546c67, 2, 12 + 8 + len(encoded) + 8 + len(binary))
out += struct.pack('<II', len(encoded), 0x4e4f534a) + encoded
out += struct.pack('<II', len(binary), 0x004e4942) + binary
target = ROOT / 'godot/assets/viewmodel/meshy_sleeve.glb'
target.write_bytes(out)
print(f'Sleeve prepared: {len(vertices) // 3} triangles; PBR textures preserved; {target}')
