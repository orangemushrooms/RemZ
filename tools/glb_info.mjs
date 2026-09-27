// Prints what a GLB carries: meshes and triangles, materials and texture sizes, skins and joints,
// animations with their length, and the scene bounds (rest pose).
// Usage: node tools/glb_info.mjs <file.glb> [more.glb ...] [--joints]
import { NodeIO, getBounds } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import fs from 'node:fs';
import path from 'node:path';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const args = process.argv.slice(2);
const showJoints = args.includes('--joints');
for (const file of args.filter(a => !a.startsWith('--'))) {
  const doc = await io.read(file);
  const root = doc.getRoot();
  const mb = (fs.statSync(file).size / 1048576).toFixed(1);
  console.log(`== ${path.basename(file)} (${mb} MB)`);
  let triangles = 0;
  for (const mesh of root.listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      const count = prim.getIndices() ? prim.getIndices().getCount() / 3 : prim.getAttribute('POSITION').getCount() / 3;
      triangles += count;
      const attrs = prim.listSemantics().join(',');
      console.log(`  mesh ${mesh.getName() || '?'}: ${count} tris, verts ${prim.getAttribute('POSITION').getCount()}, attrs ${attrs}, material ${prim.getMaterial()?.getName() || '-'}`);
    }
  }
  console.log(`  triangles total ${triangles}`);
  for (const mat of root.listMaterials()) {
    const slot = (label, tex) => tex ? `${label} ${tex.getSize()?.join('x')} ${tex.getMimeType()}` : null;
    const parts = [slot('base', mat.getBaseColorTexture()), slot('normal', mat.getNormalTexture()),
      slot('mr', mat.getMetallicRoughnessTexture()), slot('emissive', mat.getEmissiveTexture()),
      slot('occl', mat.getOcclusionTexture())].filter(Boolean);
    console.log(`  material ${mat.getName() || '?'}: ${parts.join(' | ')} metal ${mat.getMetallicFactor()} rough ${mat.getRoughnessFactor()} alpha ${mat.getAlphaMode()} double ${mat.getDoubleSided()}`);
  }
  for (const skin of root.listSkins()) {
    const joints = skin.listJoints();
    console.log(`  skin ${skin.getName() || '?'}: ${joints.length} joints, skeleton root ${skin.getSkeleton()?.getName() || '-'}`);
    if (showJoints) console.log('   ', joints.map(j => j.getName()).join(', '));
  }
  for (const anim of root.listAnimations()) {
    let end = 0;
    for (const s of anim.listSamplers()) {
      const input = s.getInput().getArray();
      end = Math.max(end, input[input.length - 1]);
    }
    console.log(`  anim ${anim.getName()}: ${anim.listChannels().length} channels, ${end.toFixed(2)} s`);
  }
  const scene = root.getDefaultScene() || root.listScenes()[0];
  const b = getBounds(scene);
  console.log(`  bounds min ${b.min.map(v => v.toFixed(3)).join(' ')} max ${b.max.map(v => v.toFixed(3)).join(' ')}`);
  const nodes = root.listNodes().filter(n => !n.getMesh() && root.listSkins().every(s => !s.listJoints().includes(n)));
  console.log(`  other nodes: ${nodes.map(n => `${n.getName()}[s=${n.getScale().map(v => +v.toFixed(3))} r=${n.getRotation().map(v => +v.toFixed(3))}]`).join(', ')}`);
}
