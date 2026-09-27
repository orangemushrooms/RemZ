// Poses a skinned GLB into a new static rest pose for re-rigging (27 Sep 2026). The wretched bride came from
// the web app with her arms hanging, the forearms bent 44 deg forward and the claws in front of the thighs;
// Meshy's retargeting lifted her upper arms 60-70 deg too high in every library clip (the wraith, in the same
// clip, did not). With the repaired weights of skin_fix.mjs the arms can be swung out cleanly: --abduct turns
// both upper arms out to the side (degrees, about the body's forward axis), --straighten lines each forearm up
// with its upper arm. Positions, normals and tangents are skinned; the result is a static textured mesh
// (same UVs, so pack.mjs can restore the maps) - once with every map, once --base-only at --base-size for
// the upload.
// Usage: node tools/repose_glb.mjs <skinned.glb> <out.glb> [--abduct 40] [--straighten] [--base-only] [--base-size 1024]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, dedup, textureCompress } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const SWITCHES = ['--straighten', '--base-only'];
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && !SWITCHES.includes(args[i - 1])));
const [input, output] = plain;
const ABDUCT = Number(opt('--abduct', 40)) * Math.PI / 180;
const STRAIGHTEN = args.includes('--straighten');
const BASE_ONLY = args.includes('--base-only');
const BASE_SIZE = Number(opt('--base-size', 0));

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const node = root.listNodes().find(n => n.getSkin() && n.getMesh());
const skin = node.getSkin();
const joints = skin.listJoints();
const ibmArray = skin.getInverseBindMatrices().getArray();
const IBM = joints.map((_, i) => Array.from(ibmArray.slice(i * 16, i * 16 + 16)));
const parentOf = new Map();
for (const n of root.listNodes()) for (const c of n.listChildren()) parentOf.set(c, n);
const mul = (a, b) => { const r = new Array(16).fill(0); for (let c = 0; c < 4; c++) for (let rr = 0; rr < 4; rr++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + rr] * b[c * 4 + k]; r[c * 4 + rr] = s; } return r; };
const translate = v => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, v[0], v[1], v[2], 1];
// rotation matrix from a unit axis and an angle (column-major 4x4)
const rotate = (axis, angle) => {
  const [x, y, z] = axis, c = Math.cos(angle), s = Math.sin(angle), t = 1 - c;
  return [t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0, t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0,
    t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0, 0, 0, 0, 1];
};
const about = (pivot, m) => mul(translate(pivot), mul(m, translate(pivot.map(v => -v))));
const origin = m => [m[12], m[13], m[14]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const norm = a => { const l = Math.hypot(...a) || 1; return a.map(v => v / l); };
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

// rest world matrices, then the arm chains swung out
const restWorld = new Map();
const world = n => { if (restWorld.has(n)) return restWorld.get(n); const p = parentOf.get(n); const m = p ? mul(world(p), n.getMatrix()) : n.getMatrix(); restWorld.set(n, m); return m; };
const posed = new Map(joints.map(j => [j, world(j)]));
const descendants = j => { const out = [j]; for (const c of j.listChildren()) out.push(...descendants(c)); return out.filter(n => posed.has(n)); };
const byName = name => joints.find(j => j.getName() === name);
for (const [side, sign] of [['Left', 1], ['Right', -1]]) {
  const arm = byName(side + 'Arm'), fore = byName(side + 'ForeArm'), hand = byName(side + 'Hand');
  const swing = about(origin(posed.get(arm)), rotate([0, 0, 1], sign * ABDUCT));
  for (const n of descendants(arm)) posed.set(n, mul(swing, posed.get(n)));
  if (STRAIGHTEN) {
    const upper = norm(sub(origin(posed.get(fore)), origin(posed.get(arm))));
    const lower = norm(sub(origin(posed.get(hand)), origin(posed.get(fore))));
    const axis = cross(lower, upper), s = Math.hypot(...axis);
    if (s > 1e-6) {
      const angle = Math.atan2(s, lower[0] * upper[0] + lower[1] * upper[1] + lower[2] * upper[2]);
      const bend = about(origin(posed.get(fore)), rotate(axis.map(v => v / s), angle));
      for (const n of descendants(fore)) posed.set(n, mul(bend, posed.get(n)));
    }
  }
}
const mats = joints.map((j, i) => mul(posed.get(j), IBM[i]));

const prim = node.getMesh().listPrimitives()[0];
const J4 = prim.getAttribute('JOINTS_0'), W4 = prim.getAttribute('WEIGHTS_0');
const count = prim.getAttribute('POSITION').getCount();
const skinAttribute = (semantic, point) => {
  const accessor = prim.getAttribute(semantic);
  if (!accessor) return;
  const size = accessor.getElementSize(), data = accessor.getArray().slice();
  const j = [0, 0, 0, 0], w = [0, 0, 0, 0];
  for (let v = 0; v < count; v++) {
    J4.getElement(v, j); W4.getElement(v, w);
    const x = data[v * size], y = data[v * size + 1], z = data[v * size + 2];
    let r = [0, 0, 0];
    for (let k = 0; k < 4; k++) {
      if (w[k] <= 0) continue;
      const m = mats[j[k]];
      const q = point ? [m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13], m[2] * x + m[6] * y + m[10] * z + m[14]]
        : [m[0] * x + m[4] * y + m[8] * z, m[1] * x + m[5] * y + m[9] * z, m[2] * x + m[6] * y + m[10] * z];
      r = r.map((s2, i) => s2 + q[i] * w[k]);
    }
    if (!point) r = norm(r);
    data[v * size] = r[0]; data[v * size + 1] = r[1]; data[v * size + 2] = r[2];
  }
  accessor.setArray(data);
};
skinAttribute('POSITION', true);
skinAttribute('NORMAL', false);
skinAttribute('TANGENT', false);
for (const semantic of ['JOINTS_0', 'WEIGHTS_0']) { const a = prim.getAttribute(semantic); prim.setAttribute(semantic, null); a.dispose(); }
// a static scene: the mesh under one plain node, no skin, no clips
const scene = root.getDefaultScene() || root.listScenes()[0];
const holder = doc.createNode('model').setMesh(node.getMesh());
node.setMesh(null).setSkin(null);
for (const child of scene.listChildren()) scene.removeChild(child);
scene.addChild(holder);
for (const a of root.listAnimations()) a.dispose();
for (const s of root.listSkins()) s.dispose();
for (const n of root.listNodes()) if (n !== holder) n.dispose();
const material = prim.getMaterial();
material.setEmissiveTexture(null).setEmissiveFactor([0, 0, 0]);
if (BASE_ONLY) {
  material.setNormalTexture(null).setMetallicRoughnessTexture(null).setOcclusionTexture(null);
  const t = prim.getAttribute('TANGENT');
  if (t) { prim.setAttribute('TANGENT', null); t.dispose(); }
}
const transforms = [dedup(), prune()];
if (BASE_SIZE) transforms.push(textureCompress({ encoder: sharp, targetFormat: 'jpeg', resize: [BASE_SIZE, BASE_SIZE], quality: 90, slots: /^baseColorTexture$/ }));
await doc.transform(...transforms);
await io.write(output, doc);
console.log(`${input} -> ${output}: arms out ${(ABDUCT * 180 / Math.PI).toFixed(0)} deg${STRAIGHTEN ? ', forearms straight' : ''}, ${(fs.statSync(output).size / 1048576).toFixed(2)} MB`);
