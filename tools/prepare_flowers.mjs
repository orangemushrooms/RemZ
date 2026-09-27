// Derived game assets only; keep all six supplied Flower_*.glb originals intact.
// node tools/prepare_flowers.mjs
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { weld, simplify, prune, dedup, textureCompress } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import fs from 'node:fs';
const dir = 'godot/assets/models';
const files = fs.readdirSync(dir).filter(f => /^Flower_[1-6]_.*\.glb$/.test(f)).sort();
if (files.length !== 6) throw new Error('Expected the six supplied Flower GLBs');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
await MeshoptSimplifier.ready;
for (const [i, file] of files.entries()) {
  const doc = await io.read(`${dir}/${file}`);
  const root = doc.getRoot();
  const count = () => root.listMeshes().flatMap(m => m.listPrimitives()).reduce((n,p) => n + p.getIndices().getCount()/3,0);
  const before = count();
  await doc.transform(weld(), simplify({simplifier: MeshoptSimplifier, ratio: Math.min(1,6500/before), error: 0.15}), dedup(), prune(),
    textureCompress({encoder: sharp, targetFormat: 'webp', resize: [1024,1024], quality: 88}));
  for (const mat of root.listMaterials()) { mat.setMetallicFactor(0); mat.setRoughnessFactor(0.9); }
  await io.write(`${dir}/field_flower_${i+1}.glb`, doc);
  console.log(`${file}: ${before} -> ${count()} triangles`);
}
