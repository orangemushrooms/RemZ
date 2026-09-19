// Meshy's rigging export drops normal and metal/roughness maps. Restore them
// from the refined mesh only after checking that rigging retained the UV atlas.
// Run after: node tools/pack.mjs zombie_titan --size 2048
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, textureCompress } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const source = await io.read('assets/raw/zombie_titan/model.glb');
const target = await io.read('public/models/zombie_titan.glb');
function uvSet(doc) {
  const result = new Set();
  for (const mesh of doc.getRoot().listMeshes()) for (const primitive of mesh.listPrimitives()) {
    const uv = primitive.getAttribute('TEXCOORD_0')?.getArray();
    for (let i = 0; uv && i < uv.length; i += 2) result.add(`${Math.round(uv[i] * 10000)},${Math.round(uv[i+1] * 10000)}`);
  }
  return result;
}
const originalUV = uvSet(source), rigUV = uvSet(target);
let shared = 0;
for (const uv of rigUV) if (originalUV.has(uv)) shared++;
if (shared / rigUV.size < 0.99) throw new Error(`UV atlas changed (${shared}/${rigUV.size}); material transfer aborted.`);
const material = source.getRoot().listMaterials()[0];
function copy(texture, name) {
  return texture ? target.createTexture(name).setImage(texture.getImage()).setMimeType(texture.getMimeType()) : null;
}
const normals = copy(material.getNormalTexture(), 'titan_normal');
const orm = copy(material.getMetallicRoughnessTexture(), 'titan_metal_rough');
for (const mat of target.getRoot().listMaterials()) {
  mat.setNormalTexture(normals).setNormalScale(1);
  mat.setMetallicRoughnessTexture(orm).setMetallicFactor(1).setRoughnessFactor(1);
  mat.setEmissiveTexture(null).setEmissiveFactor([0, 0, 0]);
}
await target.transform(prune(), textureCompress({encoder: sharp, targetFormat: 'webp', resize: [2048,2048], quality: 90}));
await io.write('public/models/zombie_titan.glb', target);
fs.writeFileSync('public/models/zombie_titan.glb.json', JSON.stringify({b64: fs.readFileSync('public/models/zombie_titan.glb').toString('base64')}));
fs.copyFileSync('public/models/zombie_titan.glb', 'godot/assets/models/zombie_titan.glb');
console.log(`Titan material maps restored; ${shared}/${rigUV.size} matching UV coordinates.`);
