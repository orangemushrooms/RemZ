// Puts every clip of a packed zombie GLB onto the floor (27 Sep 2026). Meshy retargets its library clips by
// hip height, and on the long-dress rigs (bride, wraith) that left the whole body 10-13 cm in the air in
// walk and attack (the older skins float 6-8 cm in some clips). The tool skins the mesh on
// the CPU (lowest vertex per frame, metres over the rest pose's floor) and shifts the Hips translation keys:
//   standing clips (walk, run, idle, attack, hit, scream)  one constant offset: the 15th percentile of the
//                                                          lowest vertex goes to 0 (the stance foot touches,
//                                                          a run keeps its flight phase);
//   death clips      the standing contact at the start, fading out by half the clip: the corpse keeps the
//                    clip's own lying pose (on the ground the lowest vertex is hair, claws or a hem);
//   arise            the clip's own lying start, the end pose standing on the floor.
// Usage: node tools/ground_clips.mjs <in.glb> <out.glb> [--frames 48] [--dry]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && args[i - 1] !== '--dry'));
const [input, output] = plain;
const FRAMES = Number(opt('--frames', 48));
const DRY = args.includes('--dry');

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const skinNode = root.listNodes().find(n => n.getSkin() && n.getMesh());
const skin = skinNode.getSkin();
const joints = skin.listJoints();
const ibmArray = skin.getInverseBindMatrices().getArray();
const IBM = joints.map((_, i) => Array.from(ibmArray.slice(i * 16, i * 16 + 16)));
const prim = skinNode.getMesh().listPrimitives()[0];
const bind = prim.getAttribute('POSITION').getArray();
const count = bind.length / 3;
const influences = [];
{
  const JOI = prim.getAttribute('JOINTS_0'), WEI = prim.getAttribute('WEIGHTS_0');
  const j = [0, 0, 0, 0], w = [0, 0, 0, 0];
  for (let v = 0; v < count; v++) {
    JOI.getElement(v, j); WEI.getElement(v, w);
    const list = [];
    for (let k = 0; k < 4; k++) if (w[k] > 1e-4) list.push([j[k], w[k]]);
    influences.push(list);
  }
}
const hips = joints.find(j => j.getName() === 'Hips');
const parentOf = new Map();
for (const node of root.listNodes()) for (const child of node.listChildren()) parentOf.set(child, node);

const mul = (a, b) => {
  const r = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let rr = 0; rr < 4; rr++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + rr] * b[c * 4 + k]; r[c * 4 + rr] = s; }
  return r;
};
const compose = (t, q, s) => {
  const [x, y, z, w] = q;
  const xx = x * x, yy = y * y, zz = z * z, xy = x * y, xz = x * z, yz = y * z, wx = w * x, wy = w * y, wz = w * z;
  return [(1 - 2 * (yy + zz)) * s[0], 2 * (xy + wz) * s[0], 2 * (xz - wy) * s[0], 0, 2 * (xy - wz) * s[1], (1 - 2 * (xx + zz)) * s[1], 2 * (yz + wx) * s[1], 0,
    2 * (xz + wy) * s[2], 2 * (yz - wx) * s[2], (1 - 2 * (xx + yy)) * s[2], 0, t[0], t[1], t[2], 1];
};
function sample(sampler, t) {
  const input = sampler.getInput().getArray(), out = sampler.getOutput().getArray();
  const width = out.length / input.length, last = input.length - 1;
  if (t <= input[0]) return Array.from(out.slice(0, width));
  if (t >= input[last]) return Array.from(out.slice(last * width, last * width + width));
  let lo = 0, hi = last;
  while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (input[mid] <= t) lo = mid; else hi = mid; }
  const f = (t - input[lo]) / Math.max(input[hi] - input[lo], 1e-9);
  const a = out.slice(lo * width, lo * width + width), b = out.slice(hi * width, hi * width + width);
  if (width === 4) {
    let d = 0; for (let i = 0; i < 4; i++) d += a[i] * b[i];
    const s = d < 0 ? -1 : 1, q = [0, 1, 2, 3].map(i => a[i] * (1 - f) + b[i] * f * s), n = Math.hypot(...q);
    return q.map(v => v / n);
  }
  return Array.from(a).map((v, i) => v * (1 - f) + b[i] * f);
}
function lowestAt(animation, t, lift = 0) {
  const overrides = new Map();
  for (const ch of animation.listChannels()) {
    const key = { translation: 't', rotation: 'r', scale: 's' }[ch.getTargetPath()];
    if (!key || !ch.getTargetNode()) continue;
    const entry = overrides.get(ch.getTargetNode()) || {};
    entry[key] = sample(ch.getSampler(), t);
    overrides.set(ch.getTargetNode(), entry);
  }
  const cache = new Map();
  const world = node => {
    if (cache.has(node)) return cache.get(node);
    const o = overrides.get(node) || {};
    const local = compose(o.t || node.getTranslation(), o.r || node.getRotation(), o.s || node.getScale());
    const parent = parentOf.get(node);
    const m = parent ? mul(world(parent), local) : local;
    cache.set(node, m);
    return m;
  };
  const mats = joints.map((j, i) => mul(world(j), IBM[i]));
  let low = Infinity;
  for (let v = 0; v < count; v++) {
    const x = bind[v * 3], y = bind[v * 3 + 1], z = bind[v * 3 + 2];
    let py = 0;
    for (const [jt, w] of influences[v]) { const m = mats[jt]; py += (m[1] * x + m[5] * y + m[9] * z + m[13]) * w; }
    if (py < low) low = py;
  }
  return low + lift;
}
// metres of world height per unit of the Hips translation (the armature is scaled 0.01)
const parentScale = (() => { let s = 1; for (let p = parentOf.get(hips); p; p = parentOf.get(p)) s *= p.getScale()[1]; return s; })();
const percentile = (values, q) => { const s = [...values].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(q * (s.length - 1)))]; };
const smooth = x => x * x * (3 - 2 * x);

for (const animation of root.listAnimations()) {
  const name = animation.getName();
  const channel = animation.listChannels().find(ch => ch.getTargetNode() === hips && ch.getTargetPath() === 'translation');
  if (!channel) { console.log(`${name}: no Hips translation, skipped`); continue; }
  const sampler = channel.getSampler();
  const times = sampler.getInput().getArray();
  const length = times[times.length - 1];
  const frames = Array.from({ length: FRAMES + 1 }, (_, f) => length * f / FRAMES);
  const low = frames.map(t => lowestAt(animation, t));
  let offset;                                   // metres to add at time t
  if (name.startsWith('death')) {
    // the fall starts from the standing contact and ends in the clip's own lying pose: a body on the ground
    // is measured by its torso (hips 10-20 cm up), the lowest vertex there is hair, claws or a hem pressed
    // into the floor and would lift the corpse half a metre
    const start = -low[0];
    offset = t => start * (1 - smooth(Math.min(1, t / (0.5 * length))));
  } else if (name.startsWith('arise')) {
    // lying as the clip has it (same reason), the end pose standing on the floor over the last 30 %
    const end = -low[low.length - 1];
    offset = t => end * smooth(Math.min(1, Math.max(0, (t / length - 0.7) / 0.3)));
  } else {
    const d = -percentile(low, 0.15);
    offset = () => d;
  }
  const after = frames.map((t, i) => low[i] + offset(t));
  console.log(`${name.padEnd(8)} lowest ${Math.min(...low).toFixed(3)}..${Math.max(...low).toFixed(3)} -> ${Math.min(...after).toFixed(3)}..${Math.max(...after).toFixed(3)} (offset ${offset(0).toFixed(3)} .. ${offset(length).toFixed(3)} m)`);
  if (DRY) continue;
  const out = sampler.getOutput();
  const values = out.getArray().slice();
  for (let k = 0; k < times.length; k++) values[k * 3 + 1] += offset(times[k]) / parentScale;
  // the output accessor may be shared with another clip: give this one its own copy
  sampler.setOutput(doc.createAccessor().setType('VEC3').setArray(values).setBuffer(out.getBuffer()));
}
if (!DRY) {
  await io.write(output, doc);
  console.log(`written ${output} (${(fs.statSync(output).size / 1048576).toFixed(2)} MB)`);
}
