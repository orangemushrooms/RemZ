// Normalize the audited props to metres; retain 2K PBR maps and add an owl wing rig.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dedup,prune,textureCompress,transformMesh,getBounds} from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);
const specs=JSON.parse(fs.readFileSync('tools/missing_assets.json','utf8'));
const identity=()=>[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
const smooth=(a,b,x)=>{const t=Math.max(0,Math.min(1,(x-a)/(b-a)));return t*t*(3-2*t);};

function smoothOrganicNormals(doc,meshes) {
  // Meshy remeshing can leave flat facets on stems and cloth. Average across
  // coincident UV-seam vertices without changing UVs, silhouettes or materials.
  for(const mesh of meshes)for(const prim of mesh.listPrimitives()){
    if(prim.getMode()!==4)continue;
    const pos=prim.getAttribute('POSITION'),indices=prim.getIndices();
    const keys=[],sums=new Map();
    for(let i=0;i<pos.getCount();i++)keys.push(pos.getElement(i,[]).map(v=>Math.round(v*1e6)).join(','));
    const count=indices?indices.getCount():pos.getCount();
    for(let i=0;i<count;i+=3){
      const ids=[0,1,2].map(j=>indices?indices.getScalar(i+j):i+j);
      const [a,b,c]=ids.map(j=>pos.getElement(j,[]));
      const u=b.map((v,j)=>v-a[j]),v=c.map((n,j)=>n-a[j]);
      const normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
      for(const id of ids){const sum=sums.get(keys[id])||[0,0,0];normal.forEach((n,j)=>sum[j]+=n);sums.set(keys[id],sum);}
    }
    const normals=new Float32Array(pos.getCount()*3);
    for(let i=0;i<pos.getCount();i++){
      const n=sums.get(keys[i])||[0,1,0],length=Math.hypot(...n)||1;
      normals.set(n.map(v=>v/length),i*3);
    }
    prim.setAttribute('NORMAL',doc.createAccessor().setType('VEC3').setArray(normals).setBuffer(doc.getRoot().listBuffers()[0]));
    prim.setAttribute('TANGENT',null); // Godot regenerates the tangent basis from the new normals.
  }
}

function rigOwl(doc,nodes,bounds) {
  const root=doc.getRoot(),scene=root.listScenes()[0],buffer=root.listBuffers()[0];
  const wingY=(bounds.min[1]+bounds.max[1])*0.55;
  const pivots=[[0,0,0],[-0.085,wingY,0],[0.085,wingY,0],[-0.30,wingY,0],[0.30,wingY,0]];
  const bones=['Body','Wing_L','Wing_R','Tip_L','Tip_R'].map((n,i)=>doc.createNode(n).setTranslation(pivots[i]));
  scene.addChild(bones[0]);bones[0].addChild(bones[1]);bones[0].addChild(bones[2]);
  bones[1].addChild(bones[3]);bones[2].addChild(bones[4]);
  bones[3].setTranslation([-0.215,0,0]);bones[4].setTranslation([0.215,0,0]);
  const inverse=new Float32Array(80);
  pivots.forEach((p,i)=>{const m=identity();m[12]=-p[0];m[13]=-p[1];m[14]=-p[2];inverse.set(m,i*16);});
  const skin=doc.createSkin('OwlWingRig').setSkeleton(bones[0]);bones.forEach(b=>skin.addJoint(b));
  skin.setInverseBindMatrices(doc.createAccessor().setType('MAT4').setArray(inverse).setBuffer(buffer));
  for(const node of nodes){
    node.setSkin(skin);
    for(const prim of node.getMesh().listPrimitives()){
      const pos=prim.getAttribute('POSITION'),count=pos.getCount();
      const joints=new Uint16Array(count*4),weights=new Float32Array(count*4);
      for(let i=0;i<count;i++){
        const p=pos.getElement(i,[]),x=Math.abs(p[0]),side=p[0]<0?1:2;
        const wing=smooth(0.075,0.15,x),tip=smooth(0.26,0.38,x);
        joints.set([0,side,side+2,0],i*4);weights.set([1-wing,wing*(1-tip),wing*tip,0],i*4);
      }
      prim.setAttribute('JOINTS_0',doc.createAccessor().setType('VEC4').setArray(joints).setBuffer(buffer));
      prim.setAttribute('WEIGHTS_0',doc.createAccessor().setType('VEC4').setArray(weights).setBuffer(buffer));
    }
  }
}

for(const name of process.argv.slice(2).length?process.argv.slice(2):Object.keys(specs)) {
  const spec=specs[name];
  const state=JSON.parse(fs.readFileSync(`meshy_output/missing_${name}_state.json`,'utf8'));
  const doc=await io.read(`${state.folder}/refine.glb`),root=doc.getRoot(),scene=root.listScenes()[0];
  const meshes=[];
  for(const node of root.listNodes()) if(node.getMesh()) {
    const mesh=node.getMesh();transformMesh(mesh,node.getWorldMatrix());meshes.push(mesh);
  }
  for(const child of scene.listChildren())scene.removeChild(child);
  const nodes=meshes.map((mesh,i)=>doc.createNode(`${name}_${i}`).setMesh(mesh));nodes.forEach(n=>scene.addChild(n));
  const yaw=spec.yaw*Math.PI/180,rotate=identity();
  rotate[0]=rotate[10]=Math.cos(yaw);rotate[2]=-Math.sin(yaw);rotate[8]=Math.sin(yaw);
  for(const mesh of meshes)transformMesh(mesh,rotate);
  let bounds=getBounds(scene),size=bounds.max.map((n,i)=>n-bounds.min[i]);
  console.log('SOURCE',name,bounds);
  const axis='xyz'.indexOf(spec.axis),factor=spec.size/size[axis];
  const matrix=identity();matrix[0]=matrix[5]=matrix[10]=factor;
  matrix[12]=-(bounds.min[0]+size[0]/2)*factor;
  matrix[13]=-bounds.min[1]*factor;
  matrix[14]=-(bounds.min[2]+size[2]/2)*factor;
  if(spec.muzzle){
    const tip=[[],[]];
    for(const mesh of meshes)for(const prim of mesh.listPrimitives()){
      const pos=prim.getAttribute('POSITION');
      for(let i=0;i<pos.getCount();i++){
        const p=pos.getElement(i,[]);
        if(p[2]<bounds.min[2]+size[2]*0.015){tip[0].push(p[0]);tip[1].push(p[1]);}
      }
    }
    const mid=a=>(Math.min(...a)+Math.max(...a))/2;
    matrix[12]=-mid(tip[0])*factor;matrix[13]=-mid(tip[1])*factor;matrix[14]=-bounds.min[2]*factor-1.7;
  }
  for(const mesh of meshes)transformMesh(mesh,matrix);
  if(spec.dimensions){
    const b=getBounds(scene),fit=identity();
    fit[0]=spec.dimensions[0]/(b.max[0]-b.min[0]);
    fit[5]=spec.dimensions[1]/(b.max[1]-b.min[1]);
    fit[10]=spec.dimensions[2]/(b.max[2]-b.min[2]);
    for(const mesh of meshes)transformMesh(mesh,fit);
  }
  if(name==='owl_real')rigOwl(doc,nodes,getBounds(scene));
  if(name.startsWith('mushroom_')||name==='sandbag')smoothOrganicNormals(doc,meshes);
  for(const mat of root.listMaterials())if(name==='owl_real')mat.setDoubleSided(true);
  await doc.transform(dedup(),prune(),textureCompress({encoder:sharp,targetFormat:'webp',resize:[2048,2048],quality:95}));
  const output=`godot/assets/models/${name}.glb`;
  await io.write(output,doc);
  console.log('PREPARED',output,getBounds(scene),fs.statSync(output).size);
}
