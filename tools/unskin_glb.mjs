// Turns a rigged Meshy web export back into a static textured mesh in its bind pose (metres, feet at y 0,
// facing +Z), so it can be rigged again through the API, which delivers the Meshy bone names the game uses
// and accepts library clips. Skin, joints and animations go, the emissive map too (web exports carry a
// copy of the base colour there, which would light the model up).
// Usage: node tools/unskin_glb.mjs <rigged.glb> <out.glb>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, dedup } from '@gltf-transform/functions';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const [input, output] = process.argv.slice(2);
const doc = await io.read(input);
const root = doc.getRoot();

const mul = (a, b) => {
  const r = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let rr = 0; rr < 4; rr++) for (let k = 0; k < 4; k++) r[c * 4 + rr] += a[k * 4 + rr] * b[c * 4 + k];
  return r;
};
const point = (m, x, y, z) => [m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13], m[2] * x + m[6] * y + m[10] * z + m[14]];
const vector = (m, x, y, z) => [m[0] * x + m[4] * y + m[8] * z, m[1] * x + m[5] * y + m[9] * z, m[2] * x + m[6] * y + m[10] * z];

const scene = root.getDefaultScene() || root.listScenes()[0];
const holder = doc.createNode('model');
for (const node of root.listNodes()) {
  const mesh = node.getMesh();
  const skin = node.getSkin();
  if (!mesh) continue;
  const ibm = skin?.getInverseBindMatrices()?.getArray();
  const joints = skin ? skin.listJoints().map((j, i) => mul(j.getWorldMatrix(), Array.from(ibm.slice(i * 16, i * 16 + 16)))) : null;
  const world = node.getWorldMatrix();
  for (const prim of mesh.listPrimitives()) {
    const pos = prim.getAttribute('POSITION'), nrm = prim.getAttribute('NORMAL');
    const J = prim.getAttribute('JOINTS_0')?.getArray(), W = prim.getAttribute('WEIGHTS_0')?.getArray();
    const P = pos.getArray().slice(), N = nrm ? nrm.getArray().slice() : null;
    for (let v = 0; v < P.length / 3; v++) {
      let p = [0, 0, 0], n = [0, 0, 0];
      if (joints && J) {
        for (let k = 0; k < 4; k++) {
          const w = W[v * 4 + k];
          if (w <= 0) continue;
          const m = joints[J[v * 4 + k]];
          const q = point(m, P[v * 3], P[v * 3 + 1], P[v * 3 + 2]);
          p = p.map((s, i) => s + q[i] * w);
          if (N) { const d = vector(m, N[v * 3], N[v * 3 + 1], N[v * 3 + 2]); n = n.map((s, i) => s + d[i] * w); }
        }
      } else {
        p = point(world, P[v * 3], P[v * 3 + 1], P[v * 3 + 2]);
        if (N) n = vector(world, N[v * 3], N[v * 3 + 1], N[v * 3 + 2]);
      }
      P.set(p, v * 3);
      if (N) { const l = Math.hypot(...n) || 1; N.set(n.map(s => s / l), v * 3); }
    }
    pos.setArray(P);
    if (nrm) nrm.setArray(N);
    for (const semantic of ['JOINTS_0', 'WEIGHTS_0', 'TANGENT']) {
      const accessor = prim.getAttribute(semantic);
      if (accessor) { prim.setAttribute(semantic, null); accessor.dispose(); }
    }
  }
  const copy = doc.createNode(node.getName() || 'mesh').setMesh(mesh);
  holder.addChild(copy);
  node.setMesh(null).setSkin(null);
}
for (const anim of root.listAnimations()) anim.dispose();
for (const skin of root.listSkins()) skin.dispose();
for (const child of scene.listChildren()) scene.removeChild(child);
for (const node of root.listNodes()) if (node !== holder && !node.getMesh() && !holder.listChildren().includes(node)) node.dispose();
scene.addChild(holder);
for (const material of root.listMaterials()) material.setEmissiveTexture(null).setEmissiveFactor([0, 0, 0]);
await doc.transform(dedup(), prune());
await io.write(output, doc);
console.log(`${input} -> ${output}: ${root.listMeshes().length} mesh, ${root.listNodes().length} nodes, ${root.listTextures().length} textures`);
