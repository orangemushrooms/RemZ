// Bakes the detail of a high-poly Meshy web export (0.5-2 M triangles) into the normal map of the game mesh
// (33-43 k triangles) - 27 Sep 2026. decimate_glb.mjs only collapses edges, so both meshes share one UV atlas
// and the transfer happens texel by texel in UV space, no ray casting:
//   1. the high-poly is rasterised into the atlas: per texel its object-space normal, i.e. its interpolated
//      vertex normal bent by its own tangent-space normal map (tangents from the file or MikkTSpace);
//   2. the game mesh gets smooth area-weighted normals (welded by position, so UV seams stay invisible) and
//      MikkTSpace tangents, written into the GLB so Godot shades with exactly the basis of the bake;
//   3. the game mesh is rasterised into the same atlas and every texel's object normal is expressed in the
//      interpolated tangent frame the way Godot's scene shader rebuilds it (normalised T, B = sign * N x T
//      per vertex, N), z kept positive for the RGTC import; the islands are dilated for the mipmaps.
// Without --high only the --material factors are rewritten (the wanderer has no
// high-poly: metallic 0 instead of the export's 1, which rendered it like chrome without an ORM map).
// Usage: node tools/bake_normals.mjs <game.glb> <out.glb> [--high source.glb] [--size 2048] [--geometry-only]
//        [--material metallic=0,roughness=0.9] [--preview atlas.png] [--retangent]
// --retangent without --high: the bride was re-rigged from an A-pose (repose_glb.mjs) after her bake; her
// tangent-space map moves with the surface, only the normals and tangents of the new rest pose are rebuilt.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { tangents, prune, unweld, weld } from '@gltf-transform/functions';
import { createRequire } from 'node:module';
import sharp from 'sharp';
import fs from 'node:fs';

const require = createRequire(import.meta.url);
const { generateTangents } = require('mikktspace');
const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && args[i - 1] !== '--retangent'));
const [input, output] = plain;
const highPath = opt('--high', null);
const SIZE = Number(opt('--size', 2048));
const materialSpec = opt('--material', null);
const previewPath = opt('--preview', null);
const RETANGENT = args.includes('--retangent');
const GEOMETRY_ONLY = args.includes('--geometry-only');   // ignore the high-poly's own normal map (the Nighthawk's averages 127,127,173: bent beyond use)   // new normals + tangents for a normal map baked before a re-rig
const heatmapPath = opt('--heatmap', null);     // deviation per texel: blue 0 deg .. red 90 deg, white = clamped
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const norm = a => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };

// MikkTSpace on an indexed triangle list (it needs unindexed corners): per-corner tangents, one per vertex (a
// vertex whose corners disagree keeps the first corner's - fine on a 2 M triangle mesh; the game mesh is split
// properly by unweld / tangents / weld). The sign is flipped to glTF's UV convention, as gltf-transform does.
function mikkPerVertex(pos, nrm, uv, idx) {
  const n = idx.length;
  const P = new Float32Array(n * 3), N = new Float32Array(n * 3), U = new Float32Array(n * 2);
  for (let c = 0; c < n; c++) {
    const v = idx[c];
    P.set(pos.subarray(v * 3, v * 3 + 3), c * 3); N.set(nrm.subarray(v * 3, v * 3 + 3), c * 3); U.set(uv.subarray(v * 2, v * 2 + 2), c * 2);
  }
  const T = generateTangents(P, N, U);
  const out = new Float32Array((pos.length / 3) * 4);
  const seen = new Uint8Array(pos.length / 3);
  for (let c = 0; c < n; c++) {
    const v = idx[c];
    if (seen[v]) continue;
    seen[v] = 1;
    out.set(T.subarray(c * 4, c * 4 + 3), v * 4);
    out[v * 4 + 3] = -T[c * 4 + 3];
  }
  return out;
}

// Rasterise a triangle list in UV space; callback(texel, w0, w1, w2, triangle) for every covered texel centre.
function rasterUV(uv, idx, size, callback) {
  for (let t = 0; t < idx.length; t += 3) {
    const a = idx[t], b = idx[t + 1], c = idx[t + 2];
    const ax = uv[a * 2] * size, ay = uv[a * 2 + 1] * size, bx = uv[b * 2] * size, by = uv[b * 2 + 1] * size, cx = uv[c * 2] * size, cy = uv[c * 2 + 1] * size;
    const area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay);
    if (Math.abs(area) < 1e-12) continue;
    const x0 = Math.max(0, Math.floor(Math.min(ax, bx, cx))), x1 = Math.min(size - 1, Math.ceil(Math.max(ax, bx, cx)));
    const y0 = Math.max(0, Math.floor(Math.min(ay, by, cy))), y1 = Math.min(size - 1, Math.ceil(Math.max(ay, by, cy)));
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const px = x + 0.5, py = y + 0.5;
      const w0 = ((bx - px) * (cy - py) - (cx - px) * (by - py)) / area;
      const w1 = ((cx - px) * (ay - py) - (ax - px) * (cy - py)) / area;
      const w2 = 1 - w0 - w1;
      if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) continue;
      callback(y * size + x, w0, w1, w2, t);
    }
  }
}
// grow covered texels into their empty neighbours, rounds times (float3 data + mask)
function dilate(data, mask, size, rounds) {
  for (let r = 0; r < rounds; r++) {
    const add = [];
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const i = y * size + x;
      if (mask[i]) continue;
      let sx = 0, sy = 0, sz = 0, n = 0;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const X = x + dx, Y = y + dy;
        if (X < 0 || Y < 0 || X >= size || Y >= size) continue;
        const j = Y * size + X;
        if (!mask[j]) continue;
        sx += data[j * 3]; sy += data[j * 3 + 1]; sz += data[j * 3 + 2]; n++;
      }
      if (n) add.push([i, sx / n, sy / n, sz / n]);
    }
    for (const [i, x, y, z] of add) { data[i * 3] = x; data[i * 3 + 1] = y; data[i * 3 + 2] = z; mask[i] = 1; }
  }
}
async function decodeTexture(texture, size) {
  const { data, info } = await sharp(Buffer.from(texture.getImage())).removeAlpha().resize(size, size, { fit: 'fill' }).raw().toBuffer({ resolveWithObject: true });
  return { data, w: info.width, h: info.height };
}

// ---------- game mesh ----------
const doc = await io.read(input);
const root = doc.getRoot();
const meshNode = root.listNodes().find(n => n.getMesh());
const prim = meshNode.getMesh().listPrimitives()[0];
const material = prim.getMaterial();
if (materialSpec) {
  const m = Object.fromEntries(materialSpec.split(',').map(kv => kv.split('=')).map(([k, v]) => [k, Number(v)]));
  if (m.metallic != null) material.setMetallicFactor(m.metallic);
  if (m.roughness != null) material.setRoughnessFactor(m.roughness);
  console.log(`material factors: metallic ${material.getMetallicFactor()} roughness ${material.getRoughnessFactor()}`);
}
// the skinned mesh's bind space: Meshy rigs are centimetres under a 0.01 armature, never rotated
const skin = meshNode.getSkin();
if (skin) {
  const ibm = skin.getInverseBindMatrices().getArray().slice(0, 16);
  const joint = skin.listJoints()[0];
  const world = joint.getWorldMatrix();
  const m = [0, 1, 2].map(c => [0, 1, 2].map(r => world[0 * 4 + r] * ibm[c * 4 + 0] + world[1 * 4 + r] * ibm[c * 4 + 1] + world[2 * 4 + r] * ibm[c * 4 + 2]));
  const s = Math.hypot(...m[0]);
  const skew = Math.abs(m[0][1]) + Math.abs(m[0][2]) + Math.abs(m[1][0]) + Math.abs(m[1][2]) + Math.abs(m[2][0]) + Math.abs(m[2][1]);
  if (skew > 1e-3 * s) throw new Error('bind space is rotated against the rest pose, normals would need a transform');
}
// smooth normals, welded by position (for a bake or --retangent; otherwise the mesh keeps its own normals)
if (highPath || RETANGENT) {
  const pos = prim.getAttribute('POSITION').getArray(), idx = prim.getIndices().getArray();
  const count = pos.length / 3;
  const key = new Map(), weld = new Int32Array(count);
  for (let v = 0; v < count; v++) {
    const k = `${Math.round(pos[v * 3] * 1e4)},${Math.round(pos[v * 3 + 1] * 1e4)},${Math.round(pos[v * 3 + 2] * 1e4)}`;
    if (!key.has(k)) key.set(k, key.size);
    weld[v] = key.get(k);
  }
  const acc = new Float64Array(key.size * 3);
  for (let t = 0; t < idx.length; t += 3) {
    const a = idx[t], b = idx[t + 1], c = idx[t + 2];
    const A = [pos[a * 3], pos[a * 3 + 1], pos[a * 3 + 2]], B = [pos[b * 3], pos[b * 3 + 1], pos[b * 3 + 2]], C = [pos[c * 3], pos[c * 3 + 1], pos[c * 3 + 2]];
    const n = cross(sub(B, A), sub(C, A));       // length = twice the area: area weighting
    for (const v of [a, b, c]) { acc[weld[v] * 3] += n[0]; acc[weld[v] * 3 + 1] += n[1]; acc[weld[v] * 3 + 2] += n[2]; }
  }
  const nrm = new Float32Array(count * 3);
  for (let v = 0; v < count; v++) {
    const n = norm([acc[weld[v] * 3], acc[weld[v] * 3 + 1], acc[weld[v] * 3 + 2]]);
    nrm.set(n, v * 3);
  }
  const accessor = prim.getAttribute('NORMAL') || doc.createAccessor().setType('VEC3').setBuffer(root.listBuffers()[0]);
  accessor.setArray(nrm);
  prim.setAttribute('NORMAL', accessor);
}
if (highPath || RETANGENT) await doc.transform(unweld(), tangents({ generateTangents, overwrite: true }), weld());
const P = prim.getAttribute('POSITION').getArray(), N = prim.getAttribute('NORMAL').getArray();
const T = prim.getAttribute('TANGENT')?.getArray(), UV = prim.getAttribute('TEXCOORD_0').getArray();
const I = prim.getIndices().getArray();
console.log(`game mesh: ${I.length / 3} triangles, ${P.length / 3} vertices after the MikkTSpace split`);

if (highPath) {
  // ---------- high-poly object normals in the atlas ----------
  const high = await io.read(highPath);
  const hprim = high.getRoot().listMeshes()[0].listPrimitives()[0];
  const hpos = hprim.getAttribute('POSITION').getArray(), hnrm = hprim.getAttribute('NORMAL').getArray();
  const huv = hprim.getAttribute('TEXCOORD_0').getArray(), hidx = hprim.getIndices().getArray();
  const htan = hprim.getAttribute('TANGENT')?.getArray() || mikkPerVertex(hpos, hnrm, huv, hidx);
  const hnm = hprim.getMaterial().getNormalTexture();
  const map = hnm && !GEOMETRY_ONLY ? await decodeTexture(hnm, SIZE) : null;
  const atlas = new Float32Array(SIZE * SIZE * 3), covered = new Uint8Array(SIZE * SIZE);
  rasterUV(huv, hidx, SIZE, (i, w0, w1, w2, t) => {
    const [a, b, c] = [hidx[t], hidx[t + 1], hidx[t + 2]];
    const lerp3 = (arr, stride, k) => w0 * arr[a * stride + k] + w1 * arr[b * stride + k] + w2 * arr[c * stride + k];
    const n = norm([lerp3(hnrm, 3, 0), lerp3(hnrm, 3, 1), lerp3(hnrm, 3, 2)]);
    let result = n;
    if (map) {
      let t3 = [lerp3(htan, 4, 0), lerp3(htan, 4, 1), lerp3(htan, 4, 2)];
      t3 = norm(sub(t3, n.map(x => x * dot(t3, n))));
      const sign = htan[a * 4 + 3] < 0 ? -1 : 1;
      const bt = cross(n, t3).map(x => x * sign);
      const o = i * 3;
      const tx = map.data[o] / 127.5 - 1, ty = map.data[o + 1] / 127.5 - 1, tz = map.data[o + 2] / 127.5 - 1;
      result = norm([tx * t3[0] + ty * bt[0] + tz * n[0], tx * t3[1] + ty * bt[1] + tz * n[1], tx * t3[2] + ty * bt[2] + tz * n[2]]);
    }
    atlas[i * 3] = result[0]; atlas[i * 3 + 1] = result[1]; atlas[i * 3 + 2] = result[2];
    covered[i] = 1;
  });
  dilate(atlas, covered, SIZE, 6);
  // ---------- into the game mesh's tangent space ----------
  const out = new Float32Array(SIZE * SIZE * 3), done = new Uint8Array(SIZE * SIZE);
  const heat = heatmapPath ? Buffer.alloc(SIZE * SIZE * 3, 40) : null;
  let texels = 0, missing = 0, flipped = 0, angle = 0;
  const vertexB = new Float32Array((P.length / 3) * 3);
  for (let v = 0; v < P.length / 3; v++) {
    const b = cross([N[v * 3], N[v * 3 + 1], N[v * 3 + 2]], [T[v * 4], T[v * 4 + 1], T[v * 4 + 2]]).map(x => x * (T[v * 4 + 3] < 0 ? -1 : 1));
    vertexB.set(b, v * 3);
  }
  rasterUV(UV, I, SIZE, (i, w0, w1, w2, t) => {
    const [a, b, c] = [I[t], I[t + 1], I[t + 2]];
    const l3 = (arr, stride, k) => w0 * arr[a * stride + k] + w1 * arr[b * stride + k] + w2 * arr[c * stride + k];
    const n = norm([l3(N, 3, 0), l3(N, 3, 1), l3(N, 3, 2)]);
    const tt = norm([l3(T, 4, 0), l3(T, 4, 1), l3(T, 4, 2)]);
    const bb = norm([l3(vertexB, 3, 0), l3(vertexB, 3, 1), l3(vertexB, 3, 2)]);
    texels++;
    let target = n;
    if (covered[i]) target = [atlas[i * 3], atlas[i * 3 + 1], atlas[i * 3 + 2]];
    else missing++;
    // solve target = x T + y B + z N (the basis is not orthonormal after interpolation)
    const det = dot(tt, cross(bb, n));
    let x, y, z;
    if (Math.abs(det) > 1e-6) {
      x = dot(target, cross(bb, n)) / det;
      y = dot(tt, cross(target, n)) / det;
      z = dot(tt, cross(bb, target)) / det;
    } else { x = 0; y = 0; z = 1; }
    if (heat) {
      const deg = Math.acos(Math.max(-1, Math.min(1, dot(norm(target), n)))) * 180 / Math.PI;
      const f = Math.min(1, deg / 90);
      heat[i * 3] = z < 0.08 ? 255 : Math.round(255 * f); heat[i * 3 + 1] = z < 0.08 ? 255 : Math.round(80 * (1 - Math.abs(f - 0.5) * 2)); heat[i * 3 + 2] = z < 0.08 ? 255 : Math.round(255 * (1 - f));
    }
    if (z < 0.08) { z = 0.08; flipped++; }
    const l = Math.hypot(x, y, z);
    x /= l; y /= l; z /= l;
    angle += Math.acos(Math.min(1, z));
    out[i * 3] = x; out[i * 3 + 1] = y; out[i * 3 + 2] = z;
    done[i] = 1;
  });
  dilate(out, done, SIZE, 16);
  const pixels = Buffer.alloc(SIZE * SIZE * 3);
  for (let i = 0; i < SIZE * SIZE; i++) {
    const [x, y, z] = done[i] ? [out[i * 3], out[i * 3 + 1], out[i * 3 + 2]] : [0, 0, 1];
    pixels[i * 3] = Math.round((x * 0.5 + 0.5) * 255);
    pixels[i * 3 + 1] = Math.round((y * 0.5 + 0.5) * 255);
    pixels[i * 3 + 2] = Math.round((z * 0.5 + 0.5) * 255);
  }
  const encoded = await sharp(pixels, { raw: { width: SIZE, height: SIZE, channels: 3 } }).webp({ lossless: true }).toBuffer();
  const texture = doc.createTexture('normal').setImage(encoded).setMimeType('image/webp');
  const previous = material.getNormalTexture();
  material.setNormalTexture(texture).setNormalScale(1);
  if (previous && previous !== texture && previous.listParents().length <= 1) previous.dispose();
  if (heat) await sharp(heat, { raw: { width: SIZE, height: SIZE, channels: 3 } }).png().toFile(heatmapPath);
  if (previewPath) await sharp(pixels, { raw: { width: SIZE, height: SIZE, channels: 3 } }).resize(1024, 1024).png().toFile(previewPath);
  console.log(`bake: ${texels} texels, ${(100 * missing / Math.max(texels, 1)).toFixed(2)} % without high-poly data, ${(100 * flipped / Math.max(texels, 1)).toFixed(2)} % clamped, mean detail angle ${(angle / Math.max(texels, 1) * 180 / Math.PI).toFixed(1)} deg, ${(encoded.length / 1048576).toFixed(1)} MB`);
}
await doc.transform(prune());
await io.write(output, doc);
console.log(`written ${output} (${(fs.statSync(output).size / 1048576).toFixed(2)} MB)`);
