// Software preview of a GLB without a GPU: front (camera on +Z), side (camera on +X) and back views,
// textured with the base colour and flat-shaded, skinned meshes in their bind pose.
// Usage: node tools/glb_preview.mjs <file.glb> <out.png> [--size 520] [--anim <name> --time <s>] [--views front,side,back,top]
//        [--zoom x,y,z,extent] [--texture override.png]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import sharp from 'sharp';
import path from 'node:path';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const [file, out] = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const size = Number(opt('--size', 520));
const animName = opt('--anim', null);
const animTime = Number(opt('--time', 0));

const doc = await io.read(file);
const root = doc.getRoot();

// --- optional pose from an animation clip (linear sampling of TRS channels) ---
function sampleChannel(sampler, t) {
  const input = sampler.getInput().getArray();
  const output = sampler.getOutput().getArray();
  const width = output.length / input.length;
  if (t <= input[0]) return Array.from(output.slice(0, width));
  if (t >= input[input.length - 1]) return Array.from(output.slice((input.length - 1) * width, input.length * width));
  let k = 0;
  while (k < input.length - 2 && input[k + 1] < t) k++;
  const f = (t - input[k]) / Math.max(input[k + 1] - input[k], 1e-6);
  const a = output.slice(k * width, k * width + width), b = output.slice((k + 1) * width, (k + 1) * width + width);
  if (width === 4) { // quaternion nlerp
    let dot = 0; for (let i = 0; i < 4; i++) dot += a[i] * b[i];
    const s = dot < 0 ? -1 : 1;
    const q = [0, 1, 2, 3].map(i => a[i] * (1 - f) + b[i] * f * s);
    const n = Math.hypot(...q);
    return q.map(v => v / n);
  }
  return Array.from(a).map((v, i) => v * (1 - f) + b[i] * f);
}
if (animName) {
  const anim = root.listAnimations().find(a => a.getName() === animName);
  if (!anim) throw new Error('no animation ' + animName + ' in ' + root.listAnimations().map(a => a.getName()));
  for (const ch of anim.listChannels()) {
    const value = sampleChannel(ch.getSampler(), animTime);
    const node = ch.getTargetNode();
    if (ch.getTargetPath() === 'rotation') node.setRotation(value);
    else if (ch.getTargetPath() === 'translation') node.setTranslation(value);
    else if (ch.getTargetPath() === 'scale') node.setScale(value);
  }
}

// --- matrices ---
const mul = (a, b) => { // column-major 4x4
  const r = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let rr = 0; rr < 4; rr++) for (let k = 0; k < 4; k++) r[c * 4 + rr] += a[k * 4 + rr] * b[c * 4 + k];
  return r;
};
const apply = (m, x, y, z) => [m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13], m[2] * x + m[6] * y + m[10] * z + m[14]];

// --- collect world-space triangles ---
const tris = []; // {p: [9 floats], uv: [6], tex}
const textures = new Map();
const textureOverride = opt('--texture', null);   // an image file shown instead of every base colour map
async function decode(texture) {
  if (!texture && !textureOverride) return null;
  if (textures.has(texture)) return textures.get(texture);
  const source = textureOverride ? textureOverride : Buffer.from(texture.getImage());
  const { data, info } = await sharp(source).raw().ensureAlpha().toBuffer({ resolveWithObject: true });
  const t = { data, w: info.width, h: info.height };
  textures.set(texture, t);
  return t;
}
for (const node of root.listNodes()) {
  const mesh = node.getMesh();
  if (!mesh) continue;
  const skin = node.getSkin();
  let jointMats = null;
  if (skin) {
    const ibm = skin.getInverseBindMatrices()?.getArray();
    jointMats = skin.listJoints().map((j, i) => mul(j.getWorldMatrix(), ibm ? Array.from(ibm.slice(i * 16, i * 16 + 16)) : [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]));
  }
  const world = node.getWorldMatrix();
  for (const prim of mesh.listPrimitives()) {
    const pos = prim.getAttribute('POSITION').getArray();
    const uv = prim.getAttribute('TEXCOORD_0')?.getArray();
    const joints = prim.getAttribute('JOINTS_0')?.getArray();
    const weights = prim.getAttribute('WEIGHTS_0')?.getArray();
    const n = pos.length / 3;
    const wp = new Float32Array(n * 3);
    for (let v = 0; v < n; v++) {
      const x = pos[v * 3], y = pos[v * 3 + 1], z = pos[v * 3 + 2];
      let r;
      if (jointMats && joints) {
        r = [0, 0, 0];
        for (let k = 0; k < 4; k++) {
          const w = weights[v * 4 + k];
          if (w <= 0) continue;
          const q = apply(jointMats[joints[v * 4 + k]], x, y, z);
          r[0] += q[0] * w; r[1] += q[1] * w; r[2] += q[2] * w;
        }
      } else r = apply(world, x, y, z);
      wp[v * 3] = r[0]; wp[v * 3 + 1] = r[1]; wp[v * 3 + 2] = r[2];
    }
    const tex = await decode(prim.getMaterial()?.getBaseColorTexture());
    const factor = prim.getMaterial()?.getBaseColorFactor() || [1, 1, 1, 1];
    const idx = prim.getIndices()?.getArray();
    const count = idx ? idx.length : n;
    for (let i = 0; i < count; i += 3) {
      const a = idx ? idx[i] : i, b = idx ? idx[i + 1] : i + 1, c = idx ? idx[i + 2] : i + 2;
      tris.push({ a, b, c, wp, uv, tex, factor });
    }
  }
}
let lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
for (const t of tris) for (const v of [t.a, t.b, t.c]) for (let k = 0; k < 3; k++) {
  lo[k] = Math.min(lo[k], t.wp[v * 3 + k]); hi[k] = Math.max(hi[k], t.wp[v * 3 + k]);
}
let extent = Math.max(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]);
let center = [0, 1, 2].map(k => (lo[k] + hi[k]) / 2);
// --zoom x,y,z,extent: frame a detail (posed world coordinates) instead of the whole model
const zoom = opt('--zoom', null);
if (zoom) { const z = zoom.split(',').map(Number); center = z.slice(0, 3); extent = z[3]; }

// view: screen x, screen y (up), depth (larger = closer to the camera)
const VIEWS = {
  front: p => [p[0], p[1], p[2]],
  side: p => [-p[2], p[1], p[0]],
  back: p => [-p[0], p[1], -p[2]],
  top: p => [p[0], -p[2], p[1]],
};
const views = (opt('--views', 'front,side,back')).split(',');
const panels = [];
for (const view of views) {
  const project = VIEWS[view];
  const W = size, H = size;
  const color = Buffer.alloc(W * H * 3, 0);
  for (let i = 0; i < W * H; i++) { color[i * 3] = 38; color[i * 3 + 1] = 44; color[i * 3 + 2] = 52; }
  const depth = new Float32Array(W * H).fill(-Infinity);
  const scale = (size * 0.92) / extent;
  const toScreen = p => {
    const q = project([p[0] - center[0], p[1] - center[1], p[2] - center[2]]);
    return [W / 2 + q[0] * scale, H / 2 - q[1] * scale, q[2]];
  };
  for (const t of tris) {
    const P = [t.a, t.b, t.c].map(v => [t.wp[v * 3], t.wp[v * 3 + 1], t.wp[v * 3 + 2]]);
    const S = P.map(toScreen);
    // face normal in view space for the shading
    const e1 = [S[1][0] - S[0][0], -(S[1][1] - S[0][1]), S[1][2] * scale - S[0][2] * scale];
    const e2 = [S[2][0] - S[0][0], -(S[2][1] - S[0][1]), S[2][2] * scale - S[0][2] * scale];
    const nx = e1[1] * e2[2] - e1[2] * e2[1], ny = e1[2] * e2[0] - e1[0] * e2[2], nz = e1[0] * e2[1] - e1[1] * e2[0];
    const nl = Math.hypot(nx, ny, nz) || 1;
    const shade = 0.35 + 0.65 * Math.abs(nz / nl) * 0.8 + 0.2 * Math.max(0, ny / nl);
    const minX = Math.max(0, Math.floor(Math.min(S[0][0], S[1][0], S[2][0])));
    const maxX = Math.min(W - 1, Math.ceil(Math.max(S[0][0], S[1][0], S[2][0])));
    const minY = Math.max(0, Math.floor(Math.min(S[0][1], S[1][1], S[2][1])));
    const maxY = Math.min(H - 1, Math.ceil(Math.max(S[0][1], S[1][1], S[2][1])));
    const area = (S[1][0] - S[0][0]) * (S[2][1] - S[0][1]) - (S[2][0] - S[0][0]) * (S[1][1] - S[0][1]);
    if (Math.abs(area) < 1e-9) continue;
    for (let y = minY; y <= maxY; y++) for (let x = minX; x <= maxX; x++) {
      const px = x + 0.5, py = y + 0.5;
      let w0 = ((S[1][0] - px) * (S[2][1] - py) - (S[2][0] - px) * (S[1][1] - py)) / area;
      let w1 = ((S[2][0] - px) * (S[0][1] - py) - (S[0][0] - px) * (S[2][1] - py)) / area;
      let w2 = 1 - w0 - w1;
      if (w0 < -0.01 || w1 < -0.01 || w2 < -0.01) continue;
      const d = w0 * S[0][2] + w1 * S[1][2] + w2 * S[2][2];
      const id = y * W + x;
      if (d <= depth[id]) continue;
      depth[id] = d;
      let r = 200, g = 200, b = 200;
      if (t.tex && t.uv) {
        const u = w0 * t.uv[t.a * 2] + w1 * t.uv[t.b * 2] + w2 * t.uv[t.c * 2];
        const v = w0 * t.uv[t.a * 2 + 1] + w1 * t.uv[t.b * 2 + 1] + w2 * t.uv[t.c * 2 + 1];
        const tx = Math.min(t.tex.w - 1, Math.max(0, Math.floor((u - Math.floor(u)) * t.tex.w)));
        const ty = Math.min(t.tex.h - 1, Math.max(0, Math.floor((v - Math.floor(v)) * t.tex.h)));
        const o = (ty * t.tex.w + tx) * 4;
        r = t.tex.data[o]; g = t.tex.data[o + 1]; b = t.tex.data[o + 2];
      }
      color[id * 3] = Math.min(255, r * t.factor[0] * shade);
      color[id * 3 + 1] = Math.min(255, g * t.factor[1] * shade);
      color[id * 3 + 2] = Math.min(255, b * t.factor[2] * shade);
    }
  }
  panels.push(await sharp(color, { raw: { width: W, height: H, channels: 3 } }).png().toBuffer());
}
const label = Buffer.from(`<svg width="${size * panels.length}" height="26"><rect width="100%" height="26" fill="#11161c"/>` +
  views.map((v, i) => `<text x="${i * size + 10}" y="18" fill="#e2e8f0" font-family="Arial" font-size="14">${v}${animName ? ' ' + animName + ' @' + animTime + 's' : ''} - ${path.basename(file)}</text>`).join('') + '</svg>');
await sharp({ create: { width: size * panels.length, height: size + 26, channels: 3, background: '#11161c' } })
  .composite([...panels.map((p, i) => ({ input: p, left: i * size, top: 26 })), { input: label, left: 0, top: 0 }])
  .png().toFile(out);
console.log(`${out}: ${tris.length} triangles, extent ${extent.toFixed(3)}, bounds ${lo.map(v => v.toFixed(2))} .. ${hi.map(v => v.toFixed(2))}`);
