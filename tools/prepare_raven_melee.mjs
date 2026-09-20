// Normalize Meshy geometry, preserve PBR maps, and author an avian wing rig.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dedup,prune,textureCompress,transformMesh,getBounds} from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);
const identity=()=>[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
for(const name of process.argv.slice(2)) {
 const input=`meshy_output/raven_melee/${name}/refine.glb`;
 const doc=await io.read(input),root=doc.getRoot();
 const scene=root.listScenes()[0];
 const meshes=[];
 for(const node of root.listNodes()) if(node.getMesh()) {
  const mesh=node.getMesh(); transformMesh(mesh,node.getWorldMatrix());
  meshes.push(mesh);
 }
 for(const child of scene.listChildren()) scene.removeChild(child);
 const nodes=meshes.map((mesh,i)=>doc.createNode(`${name}_${i}`).setMesh(mesh));
 nodes.forEach(n=>scene.addChild(n));
 let bounds=getBounds(scene);
 console.log(name,'original bounds',bounds);
 // All assets are generated upright. Reverse raven forward (+Z) into Godot -Z.
 const bird=name==='raven_real';
 const rotation=identity();
 if(bird||name==='hatchet_real'){rotation[0]=-1;rotation[10]=-1;}
 for(const mesh of meshes) transformMesh(mesh,rotation);
 bounds=getBounds(scene);
 const size=bounds.max.map((v,i)=>v-bounds.min[i]);
 const scale=(bird?1.3:name==='knife_real'?0.37:0.57)/(bird?size[0]:size[1]);
 const m=identity();m[0]=m[5]=m[10]=scale;
 let gripCenter=bounds.min[0]+size[0]*0.5;
 if(!bird){
  let lo=Infinity,hi=-Infinity;
  for(const mesh of meshes)for(const prim of mesh.listPrimitives()){
   const pos=prim.getAttribute('POSITION');
   for(let i=0;i<pos.getCount();i++){
    const p=pos.getElement(i,[]),t=(p[1]-bounds.min[1])/size[1];
    if(t>0.06&&t<0.25){lo=Math.min(lo,p[0]);hi=Math.max(hi,p[0]);}
   }
  }
  if(Number.isFinite(lo))gripCenter=(lo+hi)/2;
 }
 m[12]=-gripCenter*scale;
 m[13]=-bounds.min[1]*scale+(bird?0:name==='knife_real'?-0.12:-0.145);
 m[14]=-(bounds.min[2]+size[2]*0.5)*scale;
 for(const mesh of meshes) transformMesh(mesh,m);
 if(bird){
  const pivots=[[0,0,0],[-0.10,0.27,0.02],[0.10,0.27,0.02],[-0.36,0.41,0.03],[0.36,0.41,0.03]];
  const names=['Body','Wing_L','Wing_R','Tip_L','Tip_R'];
  const bones=names.map((n,i)=>doc.createNode(n).setTranslation(pivots[i]));
  // Two joints per wing preserve the shoulder-to-wrist chain during flapping.
  scene.addChild(bones[0]);bones[0].addChild(bones[1]);bones[0].addChild(bones[2]);
  bones[1].addChild(bones[3]);bones[2].addChild(bones[4]);
  bones[3].setTranslation([-0.26,0.14,0.01]);bones[4].setTranslation([0.26,0.14,0.01]);
  const inverse=new Float32Array(5*16);
  pivots.forEach((p,i)=>{const m=identity();m[12]=-p[0];m[13]=-p[1];m[14]=-p[2];inverse.set(m,i*16)});
  const skin=doc.createSkin('RavenWingRig').setSkeleton(bones[0]);
  bones.forEach(b=>skin.addJoint(b));
  skin.setInverseBindMatrices(doc.createAccessor().setType('MAT4').setArray(inverse).setBuffer(root.listBuffers()[0]));
  for(const node of nodes){
   node.setSkin(skin);
   for(const prim of node.getMesh().listPrimitives()){
    const pos=prim.getAttribute('POSITION'), count=pos.getCount();
    const joints=new Uint16Array(count*4),weights=new Float32Array(count*4);
    for(let i=0;i<count;i++){
     const p=pos.getElement(i,[]),x=Math.abs(p[0]),side=p[0]<0?1:2;
     let wing=Math.max(0,Math.min(1,(x-0.075)/0.09));wing=wing*wing*(3-2*wing);
     let feather=Math.max(0,Math.min(1,(p[1]-0.18)/0.10));
     wing*=feather*feather*(3-2*feather);
     let tip=Math.max(0,Math.min(1,(x-0.32)/0.14));tip=tip*tip*(3-2*tip);
     joints.set([0,side,side+2,0],i*4);weights.set([1-wing,wing*(1-tip),wing*tip,0],i*4);
    }
    prim.setAttribute('JOINTS_0',doc.createAccessor().setType('VEC4').setArray(joints).setBuffer(root.listBuffers()[0]));
    prim.setAttribute('WEIGHTS_0',doc.createAccessor().setType('VEC4').setArray(weights).setBuffer(root.listBuffers()[0]));
   }
  }
 }
 for(const material of root.listMaterials())material.setDoubleSided(bird);
 await doc.transform(dedup(),prune(),textureCompress({encoder:sharp,targetFormat:'webp',resize:[bird?1024:2048,bird?1024:2048],quality:92}));
 const target=`godot/assets/models/${name}.glb`;
 await io.write(target,doc);
 console.log('PREPARED',target,getBounds(scene),fs.statSync(target).size);
}
