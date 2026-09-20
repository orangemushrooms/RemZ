// Runtime-scale, center and optimize the original Meshy props; keep their PBR materials.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dedup, prune, textureCompress, transformMesh, getBounds} from '@gltf-transform/functions';
import sharp from 'sharp';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const [name, height] of [['firework_rocket', .8], ['firework_cracker', .16]]) {
  const doc = await io.read(`meshy_output/raven_melee/${name}/refine.glb`);
  const root = doc.getRoot(), scene = root.listScenes()[0], meshes = [];
  for (const node of root.listNodes()) if (node.getMesh()) {
    const mesh = node.getMesh();
    transformMesh(mesh, node.getWorldMatrix());
    meshes.push(mesh);
  }
  for (const node of scene.listChildren()) scene.removeChild(node);
  meshes.forEach((mesh, i) => scene.addChild(doc.createNode(`${name}_${i}`).setMesh(mesh)));
  // Meshy authored the cracker fuse downward; turn it upward before normalization.
  if (name === 'firework_cracker') meshes.forEach(mesh => transformMesh(mesh, [-1,0,0,0, 0,-1,0,0, 0,0,1,0, 0,0,0,1]));
  const bounds = getBounds(scene), scale = height / (bounds.max[1] - bounds.min[1]);
  const m = [scale,0,0,0, 0,scale,0,0, 0,0,scale,0,
    -(bounds.min[0]+bounds.max[0])*.5*scale, -bounds.min[1]*scale,
    -(bounds.min[2]+bounds.max[2])*.5*scale, 1];
  meshes.forEach(mesh => transformMesh(mesh, m));
  await doc.transform(dedup(), prune(), textureCompress({encoder: sharp, targetFormat: 'webp', resize: [1024,1024], quality: 92}));
  const path = `godot/assets/models/${name}.glb`;
  await io.write(path, doc);
  console.log('PREPARED', path, getBounds(scene));
}
