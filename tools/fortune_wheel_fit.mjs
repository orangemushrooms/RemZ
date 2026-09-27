// Measures the painted disc of the Meshy wheel of fortune (godot/assets/models/fortune_wheel.glb) so that
// fortune_wheel.gd can mount its procedural disc exactly over it: which horizontal axis the disc faces,
// the disc plane, its centre and radius (all in the GLB's own units, y up, before the height fit), and the
// front: the side where the A-frame stands (the single rear leg is behind the disc).
// Usage: node tools/fortune_wheel_fit.mjs [file.glb]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

const file = process.argv[2] || 'godot/assets/models/fortune_wheel.glb';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(file);
const pts = [];
for (const node of doc.getRoot().listNodes()) {
  const mesh = node.getMesh();
  if (!mesh) continue;
  const m = node.getWorldMatrix();
  for (const prim of mesh.listPrimitives()) {
    const pos = prim.getAttribute('POSITION');
    const v = [0, 0, 0];
    for (let i = 0; i < pos.getCount(); i++) {
      pos.getElement(i, v);
      pts.push([
        m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12],
        m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13],
        m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14]]);
    }
  }
}
const lo = [0, 1, 2].map(a => Math.min(...pts.map(p => p[a])));
const hi = [0, 1, 2].map(a => Math.max(...pts.map(p => p[a])));
console.log('points', pts.length, 'min', lo.map(n => n.toFixed(3)).join(' '), 'max', hi.map(n => n.toFixed(3)).join(' '));
const height = hi[1] - lo[1];
// the disc lives in the upper part of the stand; its plane is the densest thin slab along x or z
const upper = pts.filter(p => p[1] > lo[1] + height * 0.35);
let best = null;
for (const axis of [0, 2]) {
  const bins = 200;
  const counts = new Array(bins).fill(0);
  const span = hi[axis] - lo[axis];
  for (const p of upper) counts[Math.min(bins - 1, Math.floor((p[axis] - lo[axis]) / span * bins))]++;
  let peak = 0;
  for (let i = 1; i < bins; i++) if (counts[i] > counts[peak]) peak = i;
  // widen the slab to the neighbouring bins that still hold a good share
  let a = peak, b = peak;
  while (a > 0 && counts[a - 1] > counts[peak] * 0.08) a--;
  while (b < bins - 1 && counts[b + 1] > counts[peak] * 0.08) b++;
  const slab = [lo[axis] + a / bins * span, lo[axis] + (b + 1) / bins * span];
  const inSlab = upper.filter(p => p[axis] >= slab[0] && p[axis] <= slab[1]);
  const other = axis === 0 ? 2 : 0;
  const ext = [Math.min(...inSlab.map(p => p[other])), Math.max(...inSlab.map(p => p[other]))];
  const ey = [Math.min(...inSlab.map(p => p[1])), Math.max(...inSlab.map(p => p[1]))];
  const score = inSlab.length / Math.max(1e-6, slab[1] - slab[0]);
  console.log(`axis ${'xyz'[axis]}: slab ${slab.map(n => n.toFixed(3)).join('..')} points ${inSlab.length} across ${ext.map(n => n.toFixed(3)).join('..')} up ${ey.map(n => n.toFixed(3)).join('..')}`);
  if (!best || score > best.score) best = { axis, other, slab, ext, ey, score, inSlab };
}
// centre: middle of the horizontal extent; radius: half of it (the vertical extent includes the flapper hook)
const cx = (best.ext[0] + best.ext[1]) / 2;
const r = (best.ext[1] - best.ext[0]) / 2;
const cy = best.ey[0] + r;
// front = the side of the plane with the A-frame: the legs below the disc on that side reach out furthest
const low = pts.filter(p => p[1] < lo[1] + height * 0.15);
const mid = (best.slab[0] + best.slab[1]) / 2;
const plus = low.filter(p => p[best.axis] > mid).length;
const minus = low.filter(p => p[best.axis] < mid).length;
// the single rear leg with its T foot carries fewer floor points than the two front legs? report both sides
const reach = s => Math.max(...low.filter(p => (p[best.axis] - mid) * s > 0).map(p => Math.abs(p[best.axis] - mid)), 0);
console.log(`disc faces axis ${'xyz'[best.axis]}, plane ${best.slab.map(n => n.toFixed(3)).join('..')}, centre ${'xyz'[best.other]}=${cx.toFixed(3)} y=${cy.toFixed(3)}, radius ${r.toFixed(3)}`);
console.log(`floor points +side ${plus} (reach ${reach(1).toFixed(3)}), -side ${minus} (reach ${reach(-1).toFixed(3)}), height ${height.toFixed(3)}`);
// what sits in front of the plane in the disc's circle (the hub, the flapper): depth per side
for (const s of [1, -1]) {
  const cover = pts.filter(p => (p[best.axis] - (s > 0 ? best.slab[1] : best.slab[0])) * s > 0 &&
    Math.hypot(p[best.other] - cx, p[1] - cy) < r * 0.98);
  const depth = cover.length ? Math.max(...cover.map(p => Math.abs(p[best.axis] - (s > 0 ? best.slab[1] : best.slab[0])))) : 0;
  const outer = cover.filter(p => Math.hypot(p[best.other] - cx, p[1] - cy) > r * 0.3);
  const outerDepth = outer.length ? Math.max(...outer.map(p => Math.abs(p[best.axis] - (s > 0 ? best.slab[1] : best.slab[0])))) : 0;
  console.log(`side ${s > 0 ? '+' : '-'}: ${cover.length} points in front of the disc, deepest ${depth.toFixed(3)}, beyond 30% radius ${outer.length} points deepest ${outerDepth.toFixed(3)}`);
}

// --cut: remove Meshy's leather flapper (the tongue hanging in front of the upper disc; the iron hook above
// the rim stays) so that fortune_wheel.gd's animated flapper is the only one. Idempotent.
if (process.argv.includes('--cut')) {
  const face = best.slab[0];            // front of the disc (the side of the A-frame)
  let dropped = 0;
  for (const node of doc.getRoot().listNodes()) {
    const mesh = node.getMesh();
    if (!mesh) continue;
    const m = node.getWorldMatrix();
    for (const prim of mesh.listPrimitives()) {
      const pos = prim.getAttribute('POSITION');
      const indices = prim.getIndices();
      const v = [0, 0, 0];
      const world = i => {
        pos.getElement(i, v);
        return [m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12], m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13], m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14]];
      };
      const keep = [];
      const src = indices.getArray();
      for (let t = 0; t < src.length; t += 3) {
        const c = [0, 0, 0];
        for (let k = 0; k < 3; k++) { const w = world(src[t + k]); c[0] += w[0] / 3; c[1] += w[1] / 3; c[2] += w[2] / 3; }
        const along = c[best.axis], across = c[best.other];
        const inFront = (along - face) * (best.slab[0] < best.slab[1] ? -1 : 1) > 0.002;
        const tongue = inFront && Math.abs(across - cx) < 0.075 && c[1] > cy + 0.15 && Math.hypot(across - cx, c[1] - cy) < r * 1.0;
        if (tongue) { dropped++; continue; }
        keep.push(src[t], src[t + 1], src[t + 2]);
      }
      indices.setArray(new (src.constructor)(keep));
    }
  }
  await io.write(file, doc);
  console.log(`cut the flapper: ${dropped} triangles removed from ${file}`);
}
