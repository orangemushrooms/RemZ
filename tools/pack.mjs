// Packs a raw Meshy asset into a game-ready GLB:
//   - base mesh = rigged.glb (if present) else model.glb
//   - animations from anim_<label>.glb are merged in and renamed to <label>
//   - textures resized to 1024px and encoded as WebP, unused data pruned
// Usage: node tools/pack.mjs <name> [--size 1024] [--all]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, textureCompress, resample } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RAW = path.join(ROOT, 'assets', 'raw');
const OUT = path.join(ROOT, 'public', 'models');
const args = process.argv.slice(2);
const size = Number(args[args.indexOf('--size') + 1] || 1024);
const names = args.includes('--all') ? fs.readdirSync(RAW).filter(n => fs.existsSync(path.join(RAW, n, 'model.glb'))) : args.filter(a => !a.startsWith('--') && a !== String(size));

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

for (const name of names) {
  const dir = path.join(RAW, name);
  const base = fs.existsSync(path.join(dir, 'rigged.glb')) ? 'rigged.glb' : 'model.glb';
  const doc = await io.read(path.join(dir, base));
  // drop any animation shipped with the base file, we add our own clips
  for (const a of doc.getRoot().listAnimations()) a.dispose();
  for (const f of fs.readdirSync(dir)) {
    const m = /^anim_(walk|attack|death|idle|talk)\.glb$/.exec(f);
    if (!m) continue;
    const ad = await io.read(path.join(dir, f));
    if (mergeAnimation(doc, ad, m[1])) console.log(`  + clip ${m[1]}`);
  }
  await doc.transform(
    resample(),
    dedup(),
    prune(),
    textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [size, size], quality: 82 }),
  );
  fs.mkdirSync(OUT, { recursive: true });
  const out = path.join(OUT, `${name}.glb`);
  await io.write(out, doc);
  // the Artifact host only serves standard web types, so the game loads models as base64 JSON
  fs.writeFileSync(out + '.json', JSON.stringify({ b64: fs.readFileSync(out).toString('base64') }));
  const mb = (fs.statSync(out).size / 1048576).toFixed(2);
  console.log(`${name}: ${base} -> ${out} (${mb} MB, clips: ${doc.getRoot().listAnimations().map(a => a.getName()).join(', ') || 'none'})`);
}
