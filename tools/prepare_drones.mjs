// Normalize the Meshy originals, preserve PBR and retain 2K textures in game.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dedup,prune,textureCompress,transformMesh,getBounds} from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const [kind,width] of Object.entries({scout:1.25,viper:1.65,tempest:2.05})) {
  const state = JSON.parse(fs.readFileSync(`meshy_output/drone_${kind}_state.json`,'utf8'));
  const doc = await io.read(`${state.folder}/refine.glb`);
  const root = doc.getRoot(), scene = root.listScenes()[0], meshes = [];
  for (const node of root.listNodes()) if (node.getMesh()) {
    const mesh = node.getMesh();
    transformMesh(mesh,node.getWorldMatrix());
    meshes.push(mesh);
  }
  for (const child of scene.listChildren()) scene.removeChild(child);
  for (const mesh of meshes) scene.addChild(doc.createNode(`drone_${kind}`).setMesh(mesh));
  let bounds = getBounds(scene);
  const size = bounds.max.map((v,i)=>v-bounds.min[i]);
  const scale = width/Math.max(size[0],size[2]);
  const mid = bounds.min.map((v,i)=>v+size[i]/2);
  // Meshy front is +Z. Flight and weapon fire use Godot's -Z.
  for (const mesh of meshes) transformMesh(mesh,[-scale,0,0,0,0,scale,0,0,0,0,-scale,0,mid[0]*scale,-mid[1]*scale,mid[2]*scale,1]);
  await doc.transform(dedup(),prune(),textureCompress({encoder:sharp,targetFormat:'webp',resize:[2048,2048]}));
  await io.write(`godot/assets/models/drone_${kind}.glb`,doc);
  console.log(kind,JSON.stringify(getBounds(scene)));
}
