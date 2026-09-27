// Moves repaired skin weights onto a re-rigged mesh (27 Sep 2026). The wretched bride's first rig (arms hanging)
// got clean weights from skin_fix.mjs but Meshy retargeted every clip onto it with the arms 60-70 deg too high;
// her second rig (from the A-pose that repose_glb.mjs made of that repaired mesh) plays the clips right but
// comes with fresh rigger weights (thigh pieces on the opposite arm, dress sheets, hair on the arms). Both
// skeletons carry the same bones, so the repaired weights mean the same on the new rig:
//   source   the repaired skinned GLB of the first rig (vertex order = the posed static mesh),
//   posed    the static A-pose made from it (repose_glb.mjs, same vertex order, the rig's upload),
//   target   the packed GLB of the new rig (its rest pose is that A-pose);
// every target vertex finds its posed twin by position and UV and takes the source weights, joints by name.
// Usage: node tools/transfer_weights.mjs <source.glb> <posed.glb> <target.glb> <out.glb>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import fs from 'node:fs';

const [sourcePath, posedPath, targetPath, outPath] = process.argv.slice(2);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const [source, posed, target] = await Promise.all([sourcePath, posedPath, targetPath].map(p => io.read(p)));
const primOf = doc => doc.getRoot().listMeshes()[0].listPrimitives()[0];
const sp = primOf(source), pp = primOf(posed), tp = primOf(target);
const sourceJoints = source.getRoot().listNodes().find(n => n.getSkin()).getSkin().listJoints().map(j => j.getName());
const targetNode = target.getRoot().listNodes().find(n => n.getSkin() && n.getMesh());
const targetSkin = targetNode.getSkin();
const targetJoints = targetSkin.listJoints().map(j => j.getName());
const remap = sourceJoints.map(name => targetJoints.indexOf(name));
if (remap.some(i => i < 0)) throw new Error('joints missing on the new rig: ' + sourceJoints.filter((_, i) => remap[i] < 0));
const count = pp.getAttribute('POSITION').getCount();
if (sp.getAttribute('POSITION').getCount() !== count) throw new Error('source and posed mesh differ in vertex count');

// target rest positions in metres (skinned at rest), the same frame as the posed static mesh
const parentOf = new Map();
for (const n of target.getRoot().listNodes()) for (const c of n.listChildren()) parentOf.set(c, n);
const mul = (a, b) => { const r = new Array(16).fill(0); for (let c = 0; c < 4; c++) for (let rr = 0; rr < 4; rr++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + rr] * b[c * 4 + k]; r[c * 4 + rr] = s; } return r; };
const world = n => { const p = parentOf.get(n); return p ? mul(world(p), n.getMatrix()) : n.getMatrix(); };
const ibm = targetSkin.getInverseBindMatrices().getArray();
const mats = targetSkin.listJoints().map((j, i) => mul(world(j), Array.from(ibm.slice(i * 16, i * 16 + 16))));
const TP = tp.getAttribute('POSITION'), TJ = tp.getAttribute('JOINTS_0'), TW = tp.getAttribute('WEIGHTS_0'), TUV = tp.getAttribute('TEXCOORD_0').getArray();
const targetCount = TP.getCount();
const rest = new Float32Array(targetCount * 3);
{
  const p = [0, 0, 0], j = [0, 0, 0, 0], w = [0, 0, 0, 0];
  for (let v = 0; v < targetCount; v++) {
    TP.getElement(v, p); TJ.getElement(v, j); TW.getElement(v, w);
    const r = [0, 0, 0];
    for (let k = 0; k < 4; k++) {
      if (w[k] <= 0) continue;
      const m = mats[j[k]];
      r[0] += (m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12]) * w[k];
      r[1] += (m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13]) * w[k];
      r[2] += (m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]) * w[k];
    }
    rest.set(r, v * 3);
  }
}
// Meshy's rigger re-centres the upload on the floor (the bride's A-pose moved 2.0 cm in x and 3.6 cm in z):
// line the posed mesh up with the target by their bounds (centre in x / z, floor in y), no scale
const PP = pp.getAttribute('POSITION').getArray().slice(), PUV = pp.getAttribute('TEXCOORD_0').getArray();
{
  const bounds = (arr, n) => { const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity]; for (let v = 0; v < n; v++) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], arr[v * 3 + k]); hi[k] = Math.max(hi[k], arr[v * 3 + k]); } return [lo, hi]; };
  const [plo, phi] = bounds(PP, count), [tlo, thi] = bounds(rest, targetCount);
  const shift = [(tlo[0] + thi[0] - plo[0] - phi[0]) / 2, tlo[1] - plo[1], (tlo[2] + thi[2] - plo[2] - phi[2]) / 2];
  for (let v = 0; v < count; v++) for (let k = 0; k < 3; k++) PP[v * 3 + k] += shift[k];
  console.log(`aligned the posed mesh by ${shift.map(x => (x * 100).toFixed(2)).join(', ')} cm`);
}
// spatial hash of the posed vertices, 2 cm cells
const CELL = 0.02, key = (x, y, z) => `${Math.floor(x / CELL)},${Math.floor(y / CELL)},${Math.floor(z / CELL)}`;
const grid = new Map();
for (let v = 0; v < count; v++) {
  const k = key(PP[v * 3], PP[v * 3 + 1], PP[v * 3 + 2]);
  if (!grid.has(k)) grid.set(k, []);
  grid.get(k).push(v);
}
const SJ = sp.getAttribute('JOINTS_0'), SW = sp.getAttribute('WEIGHTS_0');
let exact = 0, near = 0, far = 0, worst = 0;
const j4 = [0, 0, 0, 0], w4 = [0, 0, 0, 0];
for (let v = 0; v < targetCount; v++) {
  const x = rest[v * 3], y = rest[v * 3 + 1], z = rest[v * 3 + 2];
  let best = -1, bestScore = Infinity, bestDistance = Infinity;
  for (let r = 1; r <= 3 && best < 0; r++) {
    const cx = Math.floor(x / CELL), cy = Math.floor(y / CELL), cz = Math.floor(z / CELL);
    for (let dx = -r; dx <= r; dx++) for (let dy = -r; dy <= r; dy++) for (let dz = -r; dz <= r; dz++) {
      for (const c of grid.get(`${cx + dx},${cy + dy},${cz + dz}`) || []) {
        const d = Math.hypot(PP[c * 3] - x, PP[c * 3 + 1] - y, PP[c * 3 + 2] - z);
        const duv = Math.hypot(PUV[c * 2] - TUV[v * 2], PUV[c * 2 + 1] - TUV[v * 2 + 1]);
        const score = d + duv * 0.5;        // a UV-seam twin at the same spot must not win over the right island
        if (score < bestScore) { bestScore = score; best = c; bestDistance = d; }
      }
    }
  }
  if (best < 0) throw new Error('no posed vertex near target vertex ' + v);
  worst = Math.max(worst, bestDistance);
  if (bestDistance < 1e-4) exact++; else if (bestDistance < 5e-3) near++; else far++;
  SJ.getElement(best, j4); SW.getElement(best, w4);
  TJ.setElement(v, j4.map((j, k) => (w4[k] > 0 ? remap[j] : 0)));
  TW.setElement(v, w4);
}
await io.write(outPath, target);
console.log(`transfer: ${targetCount} vertices - ${exact} exact, ${near} within 5 mm, ${far} farther (worst ${(worst * 100).toFixed(2)} cm) -> ${outPath} (${(fs.statSync(outPath).size / 1048576).toFixed(2)} MB)`);
