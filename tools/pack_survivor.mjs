// Preserve the reference-guided survivor's 4K PBR materials and locomotion clips.
// Usage: node tools/pack_survivor.mjs
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, resample, textureCompress } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

const name = 'player_survivor_v2';
const raw = `assets/raw/${name}`;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const source = await io.read(`${raw}/model.glb`);
const target = await io.read(`${raw}/rigged.glb`);
function uvSet(doc) {
  const result = new Set();
  for (const mesh of doc.getRoot().listMeshes()) for (const primitive of mesh.listPrimitives()) {
    const uv = primitive.getAttribute('TEXCOORD_0')?.getArray();
    for (let i = 0; uv && i < uv.length; i += 2) result.add(`${Math.round(uv[i] * 10000)},${Math.round(uv[i+1] * 10000)}`);
  }
  return result;
}
const originalUV = uvSet(source), rigUV = uvSet(target);
const shared = [...rigUV].filter(uv => originalUV.has(uv)).length;
if (!rigUV.size || shared / rigUV.size < 0.99) throw new Error('Rigging changed the UV atlas; manual material review required.');
if (source.getRoot().listMaterials().length !== 1) throw new Error('Multiple source materials need explicit mapping.');
const src = source.getRoot().listMaterials()[0];
const copy = (texture, label) => texture ? target.createTexture(label).setImage(texture.getImage()).setMimeType(texture.getMimeType()) : null;
const albedo = copy(src.getBaseColorTexture(), 'survivor_albedo');
const normal = copy(src.getNormalTexture(), 'survivor_normal');
const roughness = copy(src.getMetallicRoughnessTexture(), 'survivor_metal_rough');
if (!albedo || !normal || !roughness) throw new Error('Missing PBR texture map.');
for (const mat of target.getRoot().listMaterials()) {
  mat.setBaseColorTexture(albedo).setBaseColorFactor(src.getBaseColorFactor());
  mat.setNormalTexture(normal).setNormalScale(src.getNormalScale());
  mat.setMetallicRoughnessTexture(roughness).setMetallicFactor(src.getMetallicFactor()).setRoughnessFactor(src.getRoughnessFactor());
  mat.setEmissiveTexture(null).setEmissiveFactor([0, 0, 0]);
}
for (const anim of target.getRoot().listAnimations()) anim.dispose();
const nodes = new Map(target.getRoot().listNodes().map(node => [node.getName(), node]));
for (const clip of ['walk', 'run']) {
  const input = await io.read(`${raw}/anim_${clip}.glb`);
  const sourceAnim = input.getRoot().listAnimations()[0];
  if (!sourceAnim) throw new Error(`Missing ${clip} animation`);
  const anim = target.createAnimation(clip);
  const samplers = new Map();
  for (const channel of sourceAnim.listChannels()) {
    const node = nodes.get(channel.getTargetNode()?.getName());
    if (!node) throw new Error(`Unmatched animated bone: ${channel.getTargetNode()?.getName()}`);
    const sourceSampler = channel.getSampler();
    if (!samplers.has(sourceSampler)) {
      const accessor = value => target.createAccessor().setType(value.getType()).setArray(value.getArray().slice()).setBuffer(target.getRoot().listBuffers()[0]);
      const sampler = target.createAnimationSampler().setInput(accessor(sourceSampler.getInput())).setOutput(accessor(sourceSampler.getOutput())).setInterpolation(sourceSampler.getInterpolation());
      samplers.set(sourceSampler, sampler);
      anim.addSampler(sampler);
    }
    anim.addChannel(target.createAnimationChannel().setTargetNode(node).setTargetPath(channel.getTargetPath()).setSampler(samplers.get(sourceSampler)));
  }
}
await target.transform(resample(), dedup(), prune(), textureCompress({encoder: sharp, targetFormat: 'webp', resize: [4096,4096], quality: 94}));
const out = `godot/assets/models/${name}.glb`;
await io.write(out, target);
let triangles = 0;
for (const mesh of target.getRoot().listMeshes()) for (const primitive of mesh.listPrimitives()) triangles += (primitive.getIndices()?.getCount() ?? primitive.getAttribute('POSITION').getCount()) / 3;
const report = {triangles, bytes: fs.statSync(out).size, uvMatch: shared / rigUV.size, animations: target.getRoot().listAnimations().map(a => a.getName()), textures: []};
for (const texture of target.getRoot().listTextures()) {
  const meta = await sharp(texture.getImage()).metadata();
  report.textures.push({name: texture.getName(), width: meta.width, height: meta.height});
}
fs.writeFileSync(`${raw}/packed-report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
