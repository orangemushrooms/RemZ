// Packs a raw Meshy asset into a game-ready GLB:
//   - base mesh = rigged.glb (if present) else model.glb
//   - animations from anim_<label>.glb are merged in and renamed to <label> (any label, e.g. walk2, hit, scream)
//   - Meshy's rigging export keeps only the base colour: when model.glb (the refined PBR mesh) lies next to
//     rigged.glb and rigging kept the UV atlas, its normal and metallic/roughness maps are restored
//   - textures resized (base colour to --albedo-size, everything else to --size) and encoded as WebP
// Usage: node tools/pack.mjs <name> [--size 1024] [--albedo-size 4096] [--quality 82] [--simplify 0.62] [--as <game name>] [--all]
//   --simplify keeps that share of the triangles (meshoptimizer, seams and UVs preserved): the 50k Meshy rigs
//   render at the cost of the old 31k ones while the 4k PBR maps keep the detail
//   --as writes public/models/<game name>.glb (for a raw folder like zombie_shambler_v3 that replaces zombie_shambler)
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, textureCompress, resample, weld, simplify } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RAW = path.join(ROOT, 'assets', 'raw');
const OUT = path.join(ROOT, 'public', 'models');
const args = process.argv.slice(2);
function option(flag, fallback) {
  const i = args.indexOf(flag);
  return i >= 0 ? Number(args[i + 1]) : fallback;
}
const size = option('--size', 1024);
const albedoSize = option('--albedo-size', size);
const quality = option('--quality', 82);
const simplifyRatio = option('--simplify', 0);
const asIndex = args.indexOf('--as');
const gameName = asIndex >= 0 ? args[asIndex + 1] : null;
const consumed = new Set();
if (gameName) consumed.add(gameName);
for (const flag of ['--size', '--albedo-size', '--quality', '--simplify']) {
  const i = args.indexOf(flag);
  if (i >= 0) consumed.add(args[i + 1]);
}
const names = args.includes('--all')
  ? fs.readdirSync(RAW).filter(n => fs.existsSync(path.join(RAW, n, 'model.glb')))
  : args.filter(a => !a.startsWith('--') && !consumed.has(a));

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);

function mergeAnimation(doc, animDoc, label) {
  const root = doc.getRoot();
  const nodesByName = new Map(root.listNodes().map(n => [n.getName(), n]));
  const src = animDoc.getRoot().listAnimations()[0];
  if (!src) return false;
  const anim = doc.createAnimation(label);
  const samplerMap = new Map();
  for (const ch of src.listChannels()) {
    const target = nodesByName.get(ch.getTargetNode()?.getName());
    if (!target) continue;
    const s = ch.getSampler();
    let sampler = samplerMap.get(s);
    if (!sampler) {
      const mk = a => doc.createAccessor(a.getName()).setType(a.getType()).setArray(a.getArray().slice()).setBuffer(root.listBuffers()[0]);
      sampler = doc.createAnimationSampler().setInput(mk(s.getInput())).setOutput(mk(s.getOutput())).setInterpolation(s.getInterpolation());
      samplerMap.set(s, sampler); anim.addSampler(sampler);
    }
    anim.addChannel(doc.createAnimationChannel().setTargetNode(target).setTargetPath(ch.getTargetPath()).setSampler(sampler));
  }
  return true;
}

// UV coordinates rounded to 1/10000: rigging must not have re-unwrapped the mesh.
function uvSet(doc) {
  const result = new Set();
  for (const mesh of doc.getRoot().listMeshes()) for (const primitive of mesh.listPrimitives()) {
    const uv = primitive.getAttribute('TEXCOORD_0')?.getArray();
    for (let i = 0; uv && i < uv.length; i += 2) result.add(`${Math.round(uv[i] * 10000)},${Math.round(uv[i + 1] * 10000)}`);
  }
  return result;
}

// Meshy's rig export drops the normal and metallic/roughness maps of the refined mesh: put them back.
function restorePbr(doc, source, name) {
  const materials = doc.getRoot().listMaterials();
  if (materials.length === 0 || materials.some(m => m.getNormalTexture())) return 'kept';
  const original = source.getRoot().listMaterials()[0];
  if (!original || (!original.getNormalTexture() && !original.getMetallicRoughnessTexture())) return 'no source maps';
  const originalUV = uvSet(source), rigUV = uvSet(doc);
  let shared = 0;
  for (const uv of rigUV) if (originalUV.has(uv)) shared++;
  if (rigUV.size === 0 || shared / rigUV.size < 0.99) return `UV atlas changed (${shared}/${rigUV.size}), maps not restored`;
  const copy = (texture, label) => texture ? doc.createTexture(label).setImage(texture.getImage()).setMimeType(texture.getMimeType()) : null;
  // Godot extracts embedded images as <glb name>_<image name>.webp next to the model
  const normal = copy(original.getNormalTexture(), 'normal');
  const orm = copy(original.getMetallicRoughnessTexture(), 'metal_rough');
  for (const material of materials) {
    if (normal) material.setNormalTexture(normal).setNormalScale(1);
    if (orm) material.setMetallicRoughnessTexture(orm).setMetallicFactor(1).setRoughnessFactor(1);
    material.setEmissiveTexture(null).setEmissiveFactor([0, 0, 0]);
  }
  return `restored (${shared}/${rigUV.size} UVs)`;
}

for (const name of names) {
  const dir = path.join(RAW, name);
  const rigged = fs.existsSync(path.join(dir, 'rigged.glb'));
  const base = rigged ? 'rigged.glb' : 'model.glb';
  const doc = await io.read(path.join(dir, base));
  // drop any animation shipped with the base file, we add our own clips
  for (const a of doc.getRoot().listAnimations()) a.dispose();
  for (const f of fs.readdirSync(dir).sort()) {
    const m = /^anim_([a-z][a-z0-9_]*)\.glb$/.exec(f);
    if (!m) continue;
    const ad = await io.read(path.join(dir, f));
    if (mergeAnimation(doc, ad, m[1])) console.log(`  + clip ${m[1]}`);
  }
  let pbr = 'n/a';
  if (rigged && fs.existsSync(path.join(dir, 'model.glb'))) {
    pbr = restorePbr(doc, await io.read(path.join(dir, 'model.glb')), name);
    console.log(`  pbr maps: ${pbr}`);
  }
  if (simplifyRatio > 0 && simplifyRatio < 1) {
    await MeshoptSimplifier.ready;
    const before = doc.getRoot().listMeshes().flatMap(m => m.listPrimitives()).reduce((n, p) => n + (p.getIndices()?.getCount() || 0) / 3, 0);
    await doc.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: simplifyRatio, error: 0.005 }));
    const after = doc.getRoot().listMeshes().flatMap(m => m.listPrimitives()).reduce((n, p) => n + (p.getIndices()?.getCount() || 0) / 3, 0);
    console.log(`  simplified ${before} -> ${after} triangles`);
  }
  await doc.transform(
    resample(),
    dedup(),
    prune(),
    textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [albedoSize, albedoSize], quality, slots: /^baseColorTexture$/ }),
    textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [size, size], quality, slots: /^(?!baseColorTexture$).*/ }),
  );
  fs.mkdirSync(OUT, { recursive: true });
  const out = path.join(OUT, `${gameName || name}.glb`);
  await io.write(out, doc);
  // the Artifact host only serves standard web types, so the game loads models as base64 JSON
  fs.writeFileSync(out + '.json', JSON.stringify({ b64: fs.readFileSync(out).toString('base64') }));
  const mb = (fs.statSync(out).size / 1048576).toFixed(2);
  const textures = doc.getRoot().listTextures().map(t => `${t.getName() || t.getURI() || 'tex'}:${t.getSize()?.join('x')}`).join(', ');
  console.log(`${name}: ${base} -> ${out} (${mb} MB, clips: ${doc.getRoot().listAnimations().map(a => a.getName()).join(', ') || 'none'}; textures: ${textures})`);
}
