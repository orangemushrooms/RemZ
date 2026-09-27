// Skin-weight check and repair for Meshy auto-rigs (27 Sep 2026). Meshy's rigger fuses what touches in the
// source pose: the wretched bride's long hair on her back took both upper arms (the arm swing tore it by
// 45x), the hands of the arms-down models (bride, wraith, wanderer) hang against the thighs and took leg
// weights (or the knees took hand weights), and long dresses took one leg per half, so the hem tore into a
// flat sheet between the knees. The tool works on welded points (UV-seam duplicates share one position and
// must share their weights) in the bind pose, in metres:
//   report  samples every clip, skins the mesh on the CPU and prints how far edges stretch against the bind
//           pose (STRETCH lines: totals, per clip, the worst edges with their weights);
//   --fix   a. arm reach: an arm bone keeps its influence only near its own arm (normalised distance to the
//              shoulder / upper arm / forearm / hand segments, --hand-length beyond the wrist, soft edge);
//           b. conflicts: influences that may never share a vertex (a hand with a leg or the pelvis, the
//              left arm with the right, a leg with the chest) are resolved per point - the body part whose
//              bone lies closer (distance / typical bone radius, minus its current weight) keeps the point;
//           c. --hair <luma>: points darker than luma (sRGB 0..1, base colour at their UV) above the waist and
//              away from the forearms and hands (dark claws) are hair: head, neck and spine by height, nothing else;
//           d. --skirt hem=<m>[,skin=<m>,shin=<share>,leg=<max>]: the dress between the hip joints and the hem follows
//              a smooth blend of the pelvis and both thighs (left / right by the lateral position, more leg
//              towards the hem, part of the shins below the knee); bare shins and feet keep their weights;
//           e. the changed points and their neighbourhood are smoothed within compatible body parts, then the
//              true bridges are cut (a hand fused to a thigh, a leg to the chest; see severs()).
// Usage: node tools/skin_fix.mjs <in.glb> [out.glb] [--fix] [--hair 0.12] [--skirt hem=0.3] [--hand-length 0.2] [--arm-reach 2.6]
//        [--frames 16] [--clips a,b] [--report 8] [--ground]  (lowest vertex per clip, then exit)
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const SWITCHES = ['--fix'];
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && !SWITCHES.includes(args[i - 1])));
const [input, output] = plain;
const FRAMES = Number(opt('--frames', 16));
const REPORT = Number(opt('--report', 8));
const HAND_LENGTH = Number(opt('--hand-length', 0.2));
const ARM_REACH = Number(opt('--arm-reach', 2.6));        // arm influence fades out between reach - 0.7 and reach bone radii
const HAIR = opt('--hair', null) != null ? Number(opt('--hair', 0)) : null;
const onlyClips = opt('--clips', null)?.split(',');
const skirtSpec = opt('--skirt', null);
const FIX = args.includes('--fix');

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const skinNode = root.listNodes().find(n => n.getSkin() && n.getMesh());
if (!skinNode) throw new Error('no skinned mesh in ' + input);
const skin = skinNode.getSkin();
const joints = skin.listJoints();
const names = joints.map(j => j.getName());
const ibmArray = skin.getInverseBindMatrices().getArray();
const IBM = joints.map((_, i) => Array.from(ibmArray.slice(i * 16, i * 16 + 16)));
const prim = skinNode.getMesh().listPrimitives()[0];
const POS = prim.getAttribute('POSITION'), JOI = prim.getAttribute('JOINTS_0'), WEI = prim.getAttribute('WEIGHTS_0');
const vertexCount = POS.getCount();
const J = name => names.indexOf(name);

// ---------- matrices (column-major) and poses ----------
const mul = (a, b) => {
  const r = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let rr = 0; rr < 4; rr++) {
    let s = 0;
    for (let k = 0; k < 4; k++) s += a[k * 4 + rr] * b[c * 4 + k];
    r[c * 4 + rr] = s;
  }
  return r;
};
const compose = (t, q, s) => {
  const [x, y, z, w] = q;
  const xx = x * x, yy = y * y, zz = z * z, xy = x * y, xz = x * z, yz = y * z, wx = w * x, wy = w * y, wz = w * z;
  return [
    (1 - 2 * (yy + zz)) * s[0], 2 * (xy + wz) * s[0], 2 * (xz - wy) * s[0], 0,
    2 * (xy - wz) * s[1], (1 - 2 * (xx + zz)) * s[1], 2 * (yz + wx) * s[1], 0,
    2 * (xz + wy) * s[2], 2 * (yz - wx) * s[2], (1 - 2 * (xx + yy)) * s[2], 0,
    t[0], t[1], t[2], 1];
};
const parentOf = new Map();
for (const node of root.listNodes()) for (const child of node.listChildren()) parentOf.set(child, node);
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
    let dot = 0; for (let i = 0; i < 4; i++) dot += a[i] * b[i];
    const sgn = dot < 0 ? -1 : 1;
    const q = [0, 1, 2, 3].map(i => a[i] * (1 - f) + b[i] * f * sgn);
    const n = Math.hypot(...q);
    return q.map(v => v / n);
  }
  return Array.from(a).map((v, i) => v * (1 - f) + b[i] * f);
}
function worldOf(overrides) {
  const cache = new Map();
  const world = node => {
    if (cache.has(node)) return cache.get(node);
    const o = overrides?.get(node) || {};
    const local = compose(o.t || node.getTranslation(), o.r || node.getRotation(), o.s || node.getScale());
    const parent = parentOf.get(node);
    const m = parent ? mul(world(parent), local) : local;
    cache.set(node, m);
    return m;
  };
  return world;
}
const jointMatrices = overrides => { const world = worldOf(overrides); return joints.map((j, i) => mul(world(j), IBM[i])); };
const restWorld = worldOf(null);
const jointAt = name => { const m = restWorld(joints[J(name)]); return [m[12], m[13], m[14]]; };
function poseOf(animation, t) {
  const overrides = new Map();
  for (const ch of animation.listChannels()) {
    const node = ch.getTargetNode();
    const key = { translation: 't', rotation: 'r', scale: 's' }[ch.getTargetPath()];
    if (!node || !key) continue;
    const entry = overrides.get(node) || {};
    entry[key] = sample(ch.getSampler(), t);
    overrides.set(node, entry);
  }
  return overrides;
}
const clipLength = a => a.listSamplers().reduce((end, s) => { const i = s.getInput().getArray(); return Math.max(end, i[i.length - 1]); }, 0);

// ---------- mesh, welded points ----------
const bind = POS.getArray();
let influences = [];
{
  const j = [0, 0, 0, 0], w = [0, 0, 0, 0];
  for (let v = 0; v < vertexCount; v++) {
    JOI.getElement(v, j); WEI.getElement(v, w);
    const list = [];
    for (let k = 0; k < 4; k++) if (w[k] > 1e-4) list.push([j[k], w[k]]);
    influences.push(list);
  }
}
let indices = Array.from(prim.getIndices().getArray());
function skinned(mats, out) {
  for (let v = 0; v < vertexCount; v++) {
    const x = bind[v * 3], y = bind[v * 3 + 1], z = bind[v * 3 + 2];
    let px = 0, py = 0, pz = 0;
    for (const [jt, w] of influences[v]) {
      const m = mats[jt];
      px += (m[0] * x + m[4] * y + m[8] * z + m[12]) * w;
      py += (m[1] * x + m[5] * y + m[9] * z + m[13]) * w;
      pz += (m[2] * x + m[6] * y + m[10] * z + m[14]) * w;
    }
    out[v * 3] = px; out[v * 3 + 1] = py; out[v * 3 + 2] = pz;
  }
  return out;
}
const rest = skinned(jointMatrices(null), new Float32Array(vertexCount * 3));   // metres, feet at 0
const pointOf = new Int32Array(vertexCount);
const points = [];
{
  const map = new Map();
  for (let v = 0; v < vertexCount; v++) {
    const key = `${Math.round(rest[v * 3] * 1e5)},${Math.round(rest[v * 3 + 1] * 1e5)},${Math.round(rest[v * 3 + 2] * 1e5)}`;
    let id = map.get(key);
    if (id === undefined) { id = points.length; map.set(key, id); points.push({ verts: [], pos: [rest[v * 3], rest[v * 3 + 1], rest[v * 3 + 2]] }); }
    points[id].verts.push(v);
    pointOf[v] = id;
  }
}
const normalize = list => { const t = list.reduce((s, e) => s + e[1], 0) || 1; return list.map(([j, w]) => [j, w / t]); };
let pw = points.map(p => {
  const acc = new Map();
  for (const v of p.verts) for (const [j, w] of influences[v]) acc.set(j, (acc.get(j) || 0) + w / p.verts.length);
  return normalize([...acc.entries()].filter(([, w]) => w > 1e-4));
});
const adjacency = points.map(() => new Set());
for (let i = 0; i < indices.length; i += 3) {
  const a = pointOf[indices[i]], b = pointOf[indices[i + 1]], c = pointOf[indices[i + 2]];
  for (const [x, y] of [[a, b], [b, c], [a, c]]) if (x !== y) { adjacency[x].add(y); adjacency[y].add(x); }
}

// ---------- body parts, bone capsules ----------
const side = name => name.startsWith('Left') ? 'L' : (name.startsWith('Right') ? 'R' : 'C');
const part = name => {
  if (/(ForeArm|Hand)$/.test(name)) return 'armF';
  if (/Arm$/.test(name)) return 'armU';
  if (/Shoulder$/.test(name)) return 'shoulder';
  if (/(UpLeg|Leg|Foot|ToeBase)$/.test(name)) return 'leg';
  if (name === 'Hips' || name === 'Spine02') return 'lower';
  return 'upper';
};
const PART = names.map(part), SIDE = names.map(side);
const isArm = j => PART[j] === 'armF' || PART[j] === 'armU';
const group = j => (isArm(j) ? 'arm' : PART[j] === 'leg' ? 'leg' : 'torso') + SIDE[j];
function compatible(a, b) {
  if (a === b || a < 0 || b < 0) return true;
  const pa = PART[a], pb = PART[b], sa = SIDE[a], sb = SIDE[b];
  if (isArm(a) && isArm(b)) return sa === sb;
  if (pa === 'armF' || pb === 'armF') return false;
  if (pa === 'armU' || pb === 'armU') {
    const other = pa === 'armU' ? pb : pa, os = pa === 'armU' ? sb : sa, ms = pa === 'armU' ? sa : sb;
    if (other === 'leg' || other === 'lower') return false;
    return other !== 'shoulder' || os === ms;
  }
  if (pa === 'leg' && pb === 'leg') return sa === sb || skirtSpec != null;
  if (pa === 'leg' || pb === 'leg') return (pa === 'leg' ? pb : pa) === 'lower';
  return true;
}
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const segDist = (q, a, b) => {
  const ab = sub(b, a), aq = sub(q, a);
  const t = Math.max(0, Math.min(1, (aq[0] * ab[0] + aq[1] * ab[1] + aq[2] * ab[2]) / Math.max(ab[0] ** 2 + ab[1] ** 2 + ab[2] ** 2, 1e-12)));
  return Math.hypot(aq[0] - ab[0] * t, aq[1] - ab[1] * t, aq[2] - ab[2] * t);
};
const extend = (from, to, length) => { const d = sub(to, from), l = Math.hypot(...d) || 1; return [to[0] + d[0] / l * length, to[1] + d[1] / l * length, to[2] + d[2] / l * length]; };
const RADIUS = { Hips: 0.14, Spine02: 0.14, Spine01: 0.14, Spine: 0.13, neck: 0.07, Head: 0.1, head_end: 0.09, headfront: 0.08,
  Shoulder: 0.07, Arm: 0.06, ForeArm: 0.05, Hand: 0.045, UpLeg: 0.09, Leg: 0.065, Foot: 0.05, ToeBase: 0.04 };
const CHILD = { Hips: 'Spine02', Spine02: 'Spine01', Spine01: 'Spine', Spine: 'neck', neck: 'Head', Head: 'head_end',
  Shoulder: 'Arm', Arm: 'ForeArm', ForeArm: 'Hand', UpLeg: 'Leg', Leg: 'Foot', Foot: 'ToeBase' };
const capsule = names.map(name => {
  const s = side(name) === 'C' ? '' : (side(name) === 'L' ? 'Left' : 'Right');
  const base = name.replace(/^(Left|Right)/, '');
  const a = jointAt(name);
  let b = a;
  if (CHILD[base] && J(s + CHILD[base]) >= 0) b = jointAt(s + CHILD[base]);
  else if (base === 'Hand') b = extend(jointAt(s + 'ForeArm'), a, HAND_LENGTH);
  else if (base === 'ToeBase') b = extend(jointAt(s + 'Foot'), a, 0.07);
  return { a, b, r: RADIUS[base] ?? 0.1 };
});
const nd = (q, j) => segDist(q, capsule[j].a, capsule[j].b) / capsule[j].r;
const chainND = (q, s) => Math.min(...['Arm', 'ForeArm', 'Hand'].map(n => J(s + n)).filter(j => j >= 0).map(j => nd(q, j)));
const anchor = list => { let best = -1, bw = -1; for (const [j, w] of list) if (w > bw) { bw = w; best = j; } return best; };
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

// ---------- stretch report ----------
function report(label) {
  const seen = new Map();
  for (let i = 0; i < indices.length; i += 3) for (let k = 0; k < 3; k++) {
    const a = indices[i + k], b = indices[i + (k + 1) % 3];
    const key = a < b ? a * vertexCount + b : b * vertexCount + a;
    if (!seen.has(key)) seen.set(key, [Math.min(a, b), Math.max(a, b)]);
  }
  const edges = [...seen.values()];
  const len = (p, a, b) => Math.hypot(p[a * 3] - p[b * 3], p[a * 3 + 1] - p[b * 3 + 1], p[a * 3 + 2] - p[b * 3 + 2]);
  const restLen = edges.map(([a, b]) => len(rest, a, b));
  const worst = new Float32Array(edges.length), worstClip = new Array(edges.length).fill('');
  const posed = new Float32Array(vertexCount * 3);
  const perClip = [];
  for (const animation of root.listAnimations()) {
    if (onlyClips && !onlyClips.includes(animation.getName())) continue;
    const length = clipLength(animation);
    let bad = 0, peak = 0;
    const counted = new Uint8Array(edges.length);
    for (let f = 0; f <= FRAMES; f++) {
      skinned(jointMatrices(poseOf(animation, length * f / FRAMES)), posed);
      for (let e = 0; e < edges.length; e++) {
        if (restLen[e] < 2e-4) continue;             // sub-millimetre edges: ratios mean nothing
        const r = len(posed, edges[e][0], edges[e][1]) / restLen[e];
        if (r > worst[e]) { worst[e] = r; worstClip[e] = animation.getName(); }
        if (r > 2.5 && !counted[e]) { counted[e] = 1; bad++; }
        if (r > peak) peak = r;
      }
    }
    perClip.push(`${animation.getName()} ${bad}/${peak.toFixed(1)}`);
  }
  const over = k => worst.reduce((n, r) => n + (r > k ? 1 : 0), 0);
  console.log(`STRETCH ${label}: edges ${edges.length}, >1.6x ${over(1.6)}, >2.5x ${over(2.5)}, >4x ${over(4)}, >8x ${over(8)}`);
  console.log('  per clip (edges >2.5x / peak): ' + perClip.join(' | '));
  const order = [...worst.keys()].sort((a, b) => worst[b] - worst[a]).slice(0, REPORT);
  const desc = v => influences[v].map(([j, w]) => `${names[j]}:${w.toFixed(2)}`).join(' ');
  const pos = v => [0, 1, 2].map(k => rest[v * 3 + k].toFixed(2)).join(',');
  for (const e of order) {
    const [a, b] = edges[e];
    console.log(`  x${worst[e].toFixed(1)} ${worstClip[e]}  (${pos(a)}) [${desc(a)}]  (${pos(b)}) [${desc(b)}]`);
  }
}
if (args.includes('--ground')) {
  // lowest vertex per frame (metres over the rest pose's floor): standing clips should touch 0, not float
  const posed = new Float32Array(vertexCount * 3);
  const rows = [];
  for (const animation of root.listAnimations()) {
    if (onlyClips && !onlyClips.includes(animation.getName())) continue;
    const length = clipLength(animation);
    let lo = Infinity, hi = -Infinity, sum = 0;
    for (let f = 0; f <= FRAMES; f++) {
      skinned(jointMatrices(poseOf(animation, length * f / FRAMES)), posed);
      let m = Infinity;
      for (let v = 0; v < vertexCount; v++) if (posed[v * 3 + 1] < m) m = posed[v * 3 + 1];
      lo = Math.min(lo, m); hi = Math.max(hi, m); sum += m;
    }
    rows.push(`${animation.getName()} ${lo.toFixed(3)}/${(sum / (FRAMES + 1)).toFixed(3)}/${hi.toFixed(3)}`);
  }
  let restMin = Infinity;
  for (let v = 0; v < vertexCount; v++) restMin = Math.min(restMin, rest[v * 3 + 1]);
  console.log(`GROUND rest ${restMin.toFixed(3)} | lowest vertex min/mean/max per clip: ` + rows.join(' | '));
  if (!FIX) process.exit(0);
}
report('before');

if (FIX) {
  const changed = new Uint8Array(points.length);
  const setWeights = (p, list) => { pw[p] = normalize(list.filter(([, w]) => w > 1e-4)); changed[p] = 1; };
  const nearestBone = (q, allowed) => {
    let best = -1, bd = Infinity;
    for (let j = 0; j < names.length; j++) if (!allowed || allowed(j)) { const d = nd(q, j); if (d < bd) { bd = d; best = j; } }
    return best;
  };
  // a. arm reach
  let armCut = 0;
  for (let p = 0; p < points.length; p++) {
    const list = pw[p];
    if (!list.some(([j]) => isArm(j))) continue;
    const q = points[p].pos;
    const factor = { L: smooth(ARM_REACH, ARM_REACH - 0.7, chainND(q, 'Left')), R: smooth(ARM_REACH, ARM_REACH - 0.7, chainND(q, 'Right')) };
    const next = list.map(([j, w]) => [j, isArm(j) ? w * factor[SIDE[j]] : w]);
    if (next.some(([j, w], i) => w < list[i][1] - 1e-6)) {
      armCut++;
      const kept = next.filter(([, w]) => w > 1e-3);
      setWeights(p, kept.length ? kept : [[nearestBone(q, j => !isArm(j)), 1]]);
    }
  }
  // b. conflicts: the closer body part keeps the point
  let resolved = 0;
  for (let p = 0; p < points.length; p++) {
    let list = pw[p];
    let conflict = false;
    for (;;) {
      let pair = null, pairWeight = -1;
      for (let a = 0; a < list.length; a++) for (let b = a + 1; b < list.length; b++)
        if (!compatible(list[a][0], list[b][0]) && list[a][1] + list[b][1] > pairWeight) { pair = [list[a][0], list[b][0]]; pairWeight = list[a][1] + list[b][1]; }
      if (!pair) break;
      conflict = true;
      const q = points[p].pos;
      const groupWeight = j => list.reduce((s, [k, w]) => s + (group(k) === group(j) ? w : 0), 0);
      const score = j => nd(q, j) - groupWeight(j);
      const winner = score(pair[0]) <= score(pair[1]) ? pair[0] : pair[1];
      list = list.filter(([j]) => compatible(j, winner));
    }
    if (conflict) { resolved++; setWeights(p, list); }
  }
  console.log(`FIX arm reach on ${armCut} points, conflicts resolved on ${resolved} points`);
  // c. hair by colour
  if (HAIR != null) {
    const texture = root.listMaterials()[0]?.getBaseColorTexture();
    const { data, info } = await sharp(Buffer.from(texture.getImage())).removeAlpha().raw().toBuffer({ resolveWithObject: true });
    const uv = prim.getAttribute('TEXCOORD_0').getArray();
    const luma = v => {
      const x = Math.min(info.width - 1, Math.max(0, Math.floor((uv[v * 2] % 1) * info.width)));
      const y = Math.min(info.height - 1, Math.max(0, Math.floor((uv[v * 2 + 1] % 1) * info.height)));
      const o = (y * info.width + x) * 3;
      return (0.2126 * data[o] + 0.7152 * data[o + 1] + 0.0722 * data[o + 2]) / 255;
    };
    const ys = ['Hips', 'Spine02', 'Spine01', 'Spine', 'neck', 'Head'].map(n => [J(n), jointAt(n)[1]]);
    const waist = ys[1][1] + 0.05;
    let hair = 0;
    for (let p = 0; p < points.length; p++) {
      const q = points[p].pos;
      if (q[1] < waist) continue;
      const dark = points[p].verts.reduce((s, v) => s + luma(v), 0) / points[p].verts.length;
      if (dark > HAIR) continue;
      // dark claws and gloves near the forearms and hands are not hair; hair on the shoulders and upper arms is
      const handND = Math.min(...['LeftForeArm', 'LeftHand', 'RightForeArm', 'RightHand'].map(J).filter(j => j >= 0).map(j => nd(q, j)));
      if (handND < 1.6) continue;
      // head, neck and spine by height: a smooth blend between the two joints around the point
      let list = [[ys[ys.length - 1][0], 1]];
      for (let k = 0; k < ys.length - 1; k++) {
        const [ja, ya] = ys[k], [jb, yb] = ys[k + 1];
        if (q[1] >= ya && q[1] < yb) { const t = smooth(ya, yb, q[1]); list = [[ja, 1 - t], [jb, t]]; break; }
      }
      if (q[1] < ys[0][1]) list = [[ys[0][0], 1]];
      setWeights(p, list);
      hair++;
    }
    console.log(`HAIR ${hair} points follow head, neck and spine`);
  }
  // d. skirt blend
  if (skirtSpec) {
    const o = Object.fromEntries(skirtSpec.split(',').map(kv => kv.split('=')).map(([k, v]) => [k, Number(v)]));
    const HL = jointAt('LeftUpLeg'), HR = jointAt('RightUpLeg'), KL = jointAt('LeftLeg'), KR = jointAt('RightLeg');
    const FL = jointAt('LeftFoot'), FR = jointAt('RightFoot');
    const hipY = (HL[1] + HR[1]) / 2, kneeY = (KL[1] + KR[1]) / 2;
    const centre = [(HL[0] + HR[0]) / 2, hipY, (HL[2] + HR[2]) / 2];
    const lateral = sub(HL, HR), halfWidth = Math.hypot(lateral[0], lateral[2]) / 2;
    const lat = [lateral[0] / (2 * halfWidth), 0, lateral[2] / (2 * halfWidth)];
    const [iUL, iUR, iLL, iLR, iHips] = ['LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg', 'Hips'].map(J);
    const hem = o.hem ?? 0.3, skinR = o.skin ?? 0.075, shinShare = o.shin ?? 0.35, legMax = o.leg ?? 0.9;
    let blended = 0;
    for (let p = 0; p < points.length; p++) {
      const q = points[p].pos;
      if (q[1] > hipY) continue;
      const list = pw[p];
      if (!list.some(([j]) => PART[j] === 'leg' || PART[j] === 'lower')) continue;
      if (list.some(([j]) => isArm(j))) continue;
      if (q[1] < hem && Math.min(segDist(q, KL, FL), segDist(q, KR, FR)) < skinR) continue;   // bare shins
      if (list.some(([j]) => /Foot|ToeBase/.test(names[j]) && q[1] < hem)) continue;          // feet
      const s = (q[0] - centre[0]) * lat[0] + (q[2] - centre[2]) * lat[2];
      const wl = smooth(-halfWidth * 1.1, halfWidth * 1.1, s);
      const k = smooth(0, 1, (hipY - q[1]) / Math.max(hipY - kneeY, 1e-6));
      const below = smooth(0, 1, (kneeY - q[1]) / Math.max(kneeY - 0.05, 1e-6));
      const leg = legMax * k, shin = leg * shinShare * below, thigh = leg - shin;
      setWeights(p, [[iHips, 1 - leg], [iUL, thigh * wl], [iUR, thigh * (1 - wl)], [iLL, shin * wl], [iLR, shin * (1 - wl)]]);
      blended++;
    }
    console.log(`SKIRT ${blended} points blended (hip joints ${hipY.toFixed(2)} m, knees ${kneeY.toFixed(2)} m, hem ${hem} m)`);
  }
  // e. smoothing around the changes, within compatible parts
  const ring = new Uint8Array(points.length);
  for (let p = 0; p < points.length; p++) if (changed[p]) { ring[p] = 1; for (const n of adjacency[p]) { ring[n] = 1; for (const m of adjacency[n]) ring[m] = 1; } }
  for (let iteration = 0; iteration < 4; iteration++) {
    const next = pw.slice();
    for (let p = 0; p < points.length; p++) {
      if (!ring[p]) continue;
      const own = anchor(pw[p]);
      const acc = new Map();
      for (const [j, w] of pw[p]) acc.set(j, (acc.get(j) || 0) + w);
      let count = 1;
      for (const n of adjacency[p]) {
        if (!compatible(anchor(pw[n]), own)) continue;
        for (const [j, w] of pw[n]) acc.set(j, (acc.get(j) || 0) + w);
        count++;
      }
      next[p] = normalize([...acc.entries()].map(([j, w]) => [j, w / count]).filter(([j, w]) => w > 2e-3 && compatible(j, own)));
    }
    pw = next;
  }
  // cut only the true bridges, where the source fused parts that never touch in motion: a hand or forearm
  // with anything but its own arm (claws on a thigh), the two arms, a leg with the chest or the head. Between
  // an upper arm and the waist the cloth stretches instead - cutting there opened holes under the arms.
  const severs = (a, b) => {
    if (a === b || a < 0 || b < 0 || compatible(a, b)) return false;
    if (PART[a] === 'armF' || PART[b] === 'armF') return true;
    if (isArm(a) && isArm(b)) return true;
    if (PART[a] === 'leg' || PART[b] === 'leg') return !isArm(a) && !isArm(b);
    return false;
  };
  const kept = [];
  let cut = 0;
  for (let i = 0; i < indices.length; i += 3) {
    const a = anchor(pw[pointOf[indices[i]]]), b = anchor(pw[pointOf[indices[i + 1]]]), c = anchor(pw[pointOf[indices[i + 2]]]);
    if (!severs(a, b) && !severs(b, c) && !severs(a, c)) kept.push(indices[i], indices[i + 1], indices[i + 2]);
    else cut++;
  }
  indices = kept;
  console.log(`SMOOTH ${ring.reduce((s, x) => s + x, 0)} points, cut ${cut} bridging triangles`);
  // write back: every vertex of a point gets the point's four strongest influences
  const j4 = [0, 0, 0, 0], w4 = [0, 0, 0, 0];
  for (let v = 0; v < vertexCount; v++) {
    const top = normalize([...pw[pointOf[v]]].sort((a, b) => b[1] - a[1]).slice(0, 4));
    influences[v] = top;
    for (let k = 0; k < 4; k++) { j4[k] = top[k]?.[0] ?? 0; w4[k] = top[k]?.[1] ?? 0; }
    JOI.setElement(v, j4); WEI.setElement(v, w4);
  }
  prim.getIndices().setArray(vertexCount > 65535 ? new Uint32Array(indices) : new Uint16Array(indices));
  report('after');
  if (output) {
    await doc.transform(prune());
    await io.write(output, doc);
    console.log(`written ${output} (${(fs.statSync(output).size / 1048576).toFixed(2)} MB)`);
  }
}
