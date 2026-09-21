// Fit Meshy weapon assemblies to the shared climbable tower, retaining PBR maps.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dedup,prune,textureCompress,transformMesh,getBounds} from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);
const identity=()=>[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
for(const kind of process.argv.slice(2)) {
  const state=JSON.parse(fs.readFileSync(`meshy_output/tower_${kind}_state.json`,'utf8'));
  const input=`${state.folder}/refine.glb`;
  if(!fs.existsSync(input)) throw new Error(`Textured Meshy asset still pending: ${kind}`);
  const doc=await io.read(input),root=doc.getRoot(),scene=root.listScenes()[0];
  const meshes=[];
  for(const node of root.listNodes()) if(node.getMesh()) {
    const mesh=node.getMesh(); transformMesh(mesh,node.getWorldMatrix()); meshes.push(mesh);
  }
  for(const child of scene.listChildren()) scene.removeChild(child);
  for(const mesh of meshes) scene.addChild(doc.createNode(`tower_${kind}`).setMesh(mesh));
  let bounds=getBounds(scene);
  console.log(kind,'source bounds',bounds);
  // These generated gun meshes point along -X (verified against the previews).
  // Turn that axis into Godot's -Z; the vertical coil stays upright.
  const yaw=kind==='tesla'?Math.PI:-Math.PI/2;
  const rotation=identity();rotation[0]=rotation[10]=Math.cos(yaw);
  rotation[2]=-Math.sin(yaw);rotation[8]=Math.sin(yaw);
  for(const mesh of meshes) transformMesh(mesh,rotation);
  bounds=getBounds(scene);
  const size=bounds.max.map((n,i)=>n-bounds.min[i]);
  const scale=kind==='tesla'?1.25/size[1]:(kind==='flame'?1.85:kind==='mortar'?2.0:2.25)/size[2];
  const tip=[[],[]];
  for(const mesh of meshes) for(const primitive of mesh.listPrimitives()) {
    const positions=primitive.getAttribute('POSITION');
    for(let i=0;i<positions.getCount();i++) {
      const point=positions.getElement(i,[]);
      if(point[2]<bounds.min[2]+size[2]*0.015) {
        tip[0].push(point[0]);tip[1].push(point[1]);
      }
    }
  }
  const median=values=>values.sort((a,b)=>a-b)[Math.floor(values.length/2)];
  const matrix=identity();matrix[0]=matrix[5]=matrix[10]=scale;
  matrix[12]=-(kind==='tesla'?bounds.min[0]+size[0]/2:median(tip[0]))*scale;
  matrix[13]=kind==='tesla'?-bounds.min[1]*scale:-median(tip[1])*scale;
  matrix[14]=kind==='tesla'?-(bounds.min[2]+size[2]/2)*scale:-bounds.min[2]*scale-1.7;
  for(const mesh of meshes) transformMesh(mesh,matrix);
  await doc.transform(dedup(),prune(),textureCompress({encoder:sharp,targetFormat:'webp',resize:[1024,1024]}));
  const output=`godot/assets/models/tower_${kind}.glb`;
  await io.write(output,doc);
  console.log('PREPARED',output,getBounds(scene));
}
