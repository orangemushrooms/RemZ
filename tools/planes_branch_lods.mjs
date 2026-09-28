// Reuse the existing bare Meshy birch skeleton. Weld UV seams before reduction;
// Planes supplies its own bark coordinates and leaves the original GLB intact.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {prune} from '@gltf-transform/functions';
import {MeshoptSimplifier} from 'meshoptimizer';
await MeshoptSimplifier.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const [lod,target,error] of [['near',3500,0.008],['far',700,0.04]]) {
 const doc=await io.read('godot/assets/models/tree_birch.glb');
 const buffer=doc.getRoot().listBuffers()[0];
 for(const mesh of doc.getRoot().listMeshes()) for(const primitive of mesh.listPrimitives()) {
  const src=primitive.getAttribute('POSITION'),lookup=new Map(),points=[],mapping=[];
  for(let i=0;i<src.getCount();i++) {
   const p=src.getElement(i,[]),key=p.map(v=>Math.round(v*1e6)).join(',');
   let j=lookup.get(key);
   if(j===undefined){j=points.length/3;lookup.set(key,j);points.push(...p);}
   mapping.push(j);
  }
  const positions=new Float32Array(points);
  const indices=Uint32Array.from(primitive.getIndices().getArray(),i=>mapping[i]);
  const [reduced]=MeshoptSimplifier.simplify(indices,positions,3,target*3,error);
  const normals=new Float32Array(points.length);
  for(let i=0;i<reduced.length;i+=3) {
   const [a,b,c]=[reduced[i]*3,reduced[i+1]*3,reduced[i+2]*3];
   const u=[0,1,2].map(k=>positions[b+k]-positions[a+k]),v=[0,1,2].map(k=>positions[c+k]-positions[a+k]);
   const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
   for(const at of [a,b,c]) for(let k=0;k<3;k++) normals[at+k]+=n[k];
  }
  for(let i=0;i<normals.length;i+=3){const len=Math.hypot(...normals.slice(i,i+3))||1;for(let k=0;k<3;k++)normals[i+k]/=len;}
  for(const name of primitive.listSemantics()) primitive.setAttribute(name,null);
  const accessor=(type,array)=>doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
  primitive.setAttribute('POSITION',accessor('VEC3',positions)).setAttribute('NORMAL',accessor('VEC3',normals)).setIndices(accessor('SCALAR',reduced));
  primitive.setMaterial(doc.createMaterial().setRoughnessFactor(1));
  console.log(lod,indices.length/3,'->',reduced.length/3);
 }
 await doc.transform(prune());
 await io.write(`godot/assets/planes/branches_${lod}.glb`,doc);
}
