// Reduces a static Meshy web export (0.5-2 M triangles) to a game mesh while keeping the UV atlas, so every
// texture of the source still fits: meshoptimizer collapses edges only, the surviving vertices keep their
// positions and UVs, attribute seams stay intact. The emissive map is dropped (Meshy web exports carry a
// black one or a copy of the base colour, which would light the zombie up); zombie.gd owns the emission.
// Usage: node tools/decimate_glb.mjs <in.glb> <out.glb> --triangles 52000 [--error 0.05]
//        [--base-size 1024] [--base-only]      (the rigging input: base colour only, smaller upload)
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { weld, simplify, prune, dedup, textureCompress } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const [input, output] = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && !['--base-only'].includes(args[i - 1])));
const target = Number(opt('--triangles', 52000));
const error = Number(opt('--error', 0.05));
const baseSize = Number(opt('--base-size', 0));
const baseOnly = args.includes('--base-only');

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const count = () => root.listMeshes().flatMap(m => m.listPrimitives())
  .reduce((n, p) => n + (p.getIndices() ? p.getIndices().getCount() : p.getAttribute('POSITION').getCount()) / 3, 0);
for (const anim of root.listAnimations()) anim.dispose();
const before = count();
if (before > target) {
  await MeshoptSimplifier.ready;
  await doc.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: target / before, error }));
}
// tangents of the source no longer match the collapsed surface; the bake writes fresh ones
for (const mesh of root.listMeshes()) for (const prim of mesh.listPrimitives()) {
  const tangent = prim.getAttribute('TANGENT');
  if (tangent) { prim.setAttribute('TANGENT', null); tangent.dispose(); }
}
for (const material of root.listMaterials()) {
  material.setEmissiveTexture(null).setEmissiveFactor([0, 0, 0]);
  if (baseOnly) material.setNormalTexture(null).setMetallicRoughnessTexture(null).setOcclusionTexture(null);
}
const transforms = [dedup(), prune()];
if (baseSize > 0) transforms.push(textureCompress({ encoder: sharp, targetFormat: 'jpeg', resize: [baseSize, baseSize], quality: 90, slots: /^baseColorTexture$/ }));
await doc.transform(...transforms);
await io.write(output, doc);
const mb = (fs.statSync(output).size / 1048576).toFixed(2);
console.log(`${input} -> ${output}: ${before} -> ${count()} triangles, ${mb} MB, textures ${root.listTextures().map(t => t.getSize()?.join('x')).join(', ')}`);
