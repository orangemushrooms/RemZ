// Upper-arm and forearm directions (world, degrees) of a packed GLB at clip moments: abduction = angle out to
// the side from hanging straight down (frontal plane), flexion = forward (sagittal plane). Compare two rigs in
// the same library clip to catch a bad retarget (27 Sep 2026: the bride's arms-down rig lifted the upper arms
// 60-70 deg above the wraith's in every clip; after the A-pose re-rig they agree within ~10 deg).
// Usage: node tools/arm_pose.mjs <packed.glb> walk2@0.5 scream@1.2 ...
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const [file, ...moments] = process.argv.slice(2);
const doc = await io.read(file);
const root = doc.getRoot();
const parentOf = new Map();
for (const n of root.listNodes()) for (const c of n.listChildren()) parentOf.set(c, n);
const mul = (a, b) => { const r = new Array(16).fill(0); for (let c = 0; c < 4; c++) for (let rr = 0; rr < 4; rr++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + rr] * b[c * 4 + k]; r[c * 4 + rr] = s; } return r; };
const compose = (t, q, s) => { const [x, y, z, w] = q; return [(1 - 2 * (y * y + z * z)) * s[0], 2 * (x * y + w * z) * s[0], 2 * (x * z - w * y) * s[0], 0, 2 * (x * y - w * z) * s[1], (1 - 2 * (x * x + z * z)) * s[1], 2 * (y * z + w * x) * s[1], 0, 2 * (x * z + w * y) * s[2], 2 * (y * z - w * x) * s[2], (1 - 2 * (x * x + y * y)) * s[2], 0, t[0], t[1], t[2], 1]; };
function sample(sampler, t) {
  const input = sampler.getInput().getArray(), out = sampler.getOutput().getArray(), width = out.length / input.length;
  let k = 0; while (k < input.length - 2 && input[k + 1] < t) k++;
  const f = Math.max(0, Math.min(1, (t - input[k]) / Math.max(input[k + 1] - input[k], 1e-9)));
  const a = out.slice(k * width, k * width + width), b = out.slice((k + 1) * width, (k + 1) * width + width);
  if (width === 4) { let d = 0; for (let i = 0; i < 4; i++) d += a[i] * b[i]; const s = d < 0 ? -1 : 1; const q = [0, 1, 2, 3].map(i => a[i] * (1 - f) + b[i] * f * s); const n = Math.hypot(...q); return q.map(v => v / n); }
  return Array.from(a).map((v, i) => v * (1 - f) + b[i] * f);
}
const byName = n => root.listNodes().find(x => x.getName() === n);
for (const moment of moments) {
  const [clip, time] = moment.split('@');
  const anim = root.listAnimations().find(a => a.getName() === clip);
  const over = new Map();
  for (const ch of anim.listChannels()) { const e = over.get(ch.getTargetNode()) || {}; e[{ translation: 't', rotation: 'r', scale: 's' }[ch.getTargetPath()]] = sample(ch.getSampler(), Number(time)); over.set(ch.getTargetNode(), e); }
  const cache = new Map();
  const world = n => { if (cache.has(n)) return cache.get(n); const o = over.get(n) || {}; const m0 = compose(o.t || n.getTranslation(), o.r || n.getRotation(), o.s || n.getScale()); const p = parentOf.get(n); const m = p ? mul(world(p), m0) : m0; cache.set(n, m); return m; };
  const pos = n => { const m = world(byName(n)); return [m[12], m[13], m[14]]; };
  const angles = (a, b) => { const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]; return [Math.atan2(Math.abs(d[0]), -d[1]) * 180 / Math.PI, Math.atan2(d[2], -d[1]) * 180 / Math.PI]; };
  const out = [];
  for (const s of ['Left', 'Right']) {
    const [ab, fl] = angles(pos(s + 'Arm'), pos(s + 'ForeArm'));
    const [ab2, fl2] = angles(pos(s + 'ForeArm'), pos(s + 'Hand'));
    out.push(`${s[0]} upper out ${ab.toFixed(0)} fwd ${fl.toFixed(0)} | fore out ${ab2.toFixed(0)} fwd ${fl2.toFixed(0)}`);
  }
  console.log(`${file.split('/').pop().padEnd(24)} ${moment.padEnd(12)} ${out.join('   ')}`);
}
