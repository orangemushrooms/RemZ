// Static landscape variants of the existing Meshy plants. Bake their own
// atlas colours before welding UV seams, which otherwise block useful LODs.
// The detailed Forest / inventory models remain unchanged.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {prune} from '@gltf-transform/functions';
import {MeshoptSimplifier} from 'meshoptimizer';
import sharp from 'sharp';

await MeshoptSimplifier.ready;
MeshoptSimplifier.useExperimentalFeatures = true;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const linear = value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
const ids = [...Array.from({length: 6}, (_, i) => `field_flower_${i + 1}`),
  'mushroom_cluster', 'mushroom_fly', 'mushroom_pfifferling', 'mushroom_maronenroehrling', 'mushroom_parasol'];
for (const id of ids) {
  const doc = await io.read(`godot/assets/models/${id}.glb`);
  const buffer = doc.getRoot().listBuffers()[0];
  for (const mesh of doc.getRoot().listMeshes()) for (const primitive of mesh.listPrimitives()) {
    const src = primitive.getAttribute('POSITION'), uv = primitive.getAttribute('TEXCOORD_0');
    const material = primitive.getMaterial(), tint = material.getBaseColorFactor();
    const atlas = material.getBaseColorTexture();
    const pixels = atlas ? await sharp(atlas.getImage()).ensureAlpha().raw().toBuffer({resolveWithObject: true}) : null;
    const lookup = new Map(), vertices = [], colours = [], counts = [], mapping = [];
    for (let i = 0; i < src.getCount(); i++) {
      const position = src.getElement(i, []), tex = uv ? uv.getElement(i, []) : [0, 0];
      const key = position.map(v => Math.round(v * 1e4)).join(',');
      let index = lookup.get(key);
      if (index === undefined) {
        index = vertices.length / 3;
        lookup.set(key, index);
        vertices.push(...position);
        colours.push(0, 0, 0, 1);
        counts.push(0);
      }
      const x = pixels ? Math.min(pixels.info.width - 1, Math.max(0, Math.floor(tex[0] * pixels.info.width))) : 0;
      const y = pixels ? Math.min(pixels.info.height - 1, Math.max(0, Math.floor(tex[1] * pixels.info.height))) : 0;
      for (let k = 0; k < 3; k++) colours[index * 4 + k] += (pixels ? linear(pixels.data[(y * pixels.info.width + x) * 4 + k] / 255) : 1) * tint[k];
      counts[index]++;
      mapping.push(index);
    }
    for (let i = 0; i < counts.length; i++) for (let k = 0; k < 3; k++) colours[i * 4 + k] /= counts[i];
    const positions = new Float32Array(vertices), colorArray = new Float32Array(colours);
    // Some flowers contain coincident front/back faces. Their material is
    // already double-sided; duplicate triangles also prevent simplification.
    const mapped = Uint32Array.from(primitive.getIndices().getArray(), i => mapping[i]);
    const faces = new Set(), unique = [];
    for (let i = 0; i < mapped.length; i += 3) {
      const face = [...mapped.slice(i, i + 3)];
      if (new Set(face).size < 3) continue;
      const key = [...face].sort((a, b) => a - b).join(',');
      if (faces.has(key)) continue;
      faces.add(key);
      unique.push(...face);
    }
    const indices = new Uint32Array(unique);
    const target = id.startsWith('field_flower_') ? 1200 : 700;
    let [reduced] = MeshoptSimplifier.simplifyWithAttributes(indices, positions, 3,
      colorArray, 4, [0.08, 0.08, 0.08], null, Math.min(indices.length, target * 3), 0.2, ['Prune']);
    if (reduced.length > 6000) [reduced] = MeshoptSimplifier.simplify(indices, positions, 3,
      Math.min(indices.length, target * 3), 0.2, ['Prune']);
    if (reduced.length > 6000) throw new Error(`${id} exceeded its budget: ${reduced.length / 3} triangles`);
    const normals = new Float32Array(vertices.length);
    for (let i = 0; i < reduced.length; i += 3) {
      const [a, b, c] = [reduced[i] * 3, reduced[i + 1] * 3, reduced[i + 2] * 3];
      const u = [0, 1, 2].map(k => positions[b + k] - positions[a + k]);
      const v = [0, 1, 2].map(k => positions[c + k] - positions[a + k]);
      const normal = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
      for (const at of [a, b, c]) for (let k = 0; k < 3; k++) normals[at + k] += normal[k];
    }
    for (let i = 0; i < normals.length; i += 3) {
      const length = Math.hypot(...normals.slice(i, i + 3)) || 1;
      for (let k = 0; k < 3; k++) normals[i + k] /= length;
    }
    for (const name of primitive.listSemantics()) primitive.setAttribute(name, null);
    const used = [...new Set(reduced)], remap = new Map(used.map((old, index) => [old, index]));
    const compact = (array, stride) => Float32Array.from(used.flatMap(old => [...array.slice(old * stride, (old + 1) * stride)]));
    const accessor = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
    primitive.setAttribute('POSITION', accessor('VEC3', compact(positions, 3))).setAttribute('NORMAL', accessor('VEC3', compact(normals, 3)))
      .setAttribute('COLOR_0', accessor('VEC4', compact(colorArray, 4))).setIndices(accessor('SCALAR', Uint32Array.from(reduced, index => remap.get(index))));
    primitive.setMaterial(doc.createMaterial().setDoubleSided(true).setRoughnessFactor(1));
    console.log(`${id}: ${indices.length / 3} -> ${reduced.length / 3} triangles`);
  }
  await doc.transform(prune());
  await io.write(`godot/assets/planes/${id}.glb`, doc);
}
