// Adds library clips to a finished game GLB without repacking it (27 Sep 2026: the "arise" of the older skins).
// The mesh, skin and textures stay bit for bit, so the baked shot volumes keep their hashes; only the new
// animation is copied onto the joints by name. Refuses when the clip file's skeleton does not match the model
// (other inverse bind matrices = another rig, the keys would twist the body).
// Usage: node tools/add_clips.mjs <game.glb> <out.glb> <label>=<anim.glb> [<label>=<anim.glb> ...]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

const [input, output, ...pairs] = process.argv.slice(2);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const skin = root.listSkins()[0];
const joints = new Map(skin.listJoints().map((j, i) => [j.getName(), i]));
const ibm = skin.getInverseBindMatrices().getArray();
const nodes = new Map(root.listNodes().map(n => [n.getName(), n]));
for (const pair of pairs) {
  const [label, file] = pair.split('=');
  const clipDoc = await io.read(file);
  const clipSkin = clipDoc.getRoot().listSkins()[0];
  const clipIbm = clipSkin.getInverseBindMatrices().getArray();
  let worst = 0;
  clipSkin.listJoints().forEach((j, i) => {
    const k = joints.get(j.getName());
    if (k === undefined) throw new Error(`${file}: joint ${j.getName()} missing on the model`);
    for (let e = 0; e < 16; e++) worst = Math.max(worst, Math.abs(clipIbm[i * 16 + e] - ibm[k * 16 + e]));
  });
  if (worst > 1e-3) throw new Error(`${file}: skeleton differs from the model (inverse bind matrices off by ${worst.toFixed(4)})`);
  for (const old of root.listAnimations().filter(a => a.getName() === label)) old.dispose();
  const source = clipDoc.getRoot().listAnimations()[0];
  const anim = doc.createAnimation(label);
  const buffer = root.listBuffers()[0];
  const copy = a => doc.createAccessor(a.getName()).setType(a.getType()).setArray(a.getArray().slice()).setBuffer(buffer);
  const samplers = new Map();
  let channels = 0;
  for (const ch of source.listChannels()) {
    const target = nodes.get(ch.getTargetNode()?.getName());
    if (!target) continue;
    let sampler = samplers.get(ch.getSampler());
    if (!sampler) {
      const s = ch.getSampler();
      sampler = doc.createAnimationSampler().setInput(copy(s.getInput())).setOutput(copy(s.getOutput())).setInterpolation(s.getInterpolation());
      samplers.set(s, sampler);
      anim.addSampler(sampler);
    }
    anim.addChannel(doc.createAnimationChannel().setTargetNode(target).setTargetPath(ch.getTargetPath()).setSampler(sampler));
    channels++;
  }
  console.log(`${label}: ${channels} channels from ${file} (skeleton match ${worst.toExponential(1)})`);
}
await io.write(output, doc);
console.log('written', output);
