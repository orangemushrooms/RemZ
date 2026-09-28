// Derive low-cost distance meshes from the existing Meshy trees. Bake the source
// atlas into vertex colours before welding UV seams; never modify the originals.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
await MeshoptSimplifier.ready;
MeshoptSimplifier.useExperimentalFeatures = true;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const variant of ['a', 'b']) {
  for (const [lod, target, error] of [['far', 1800, 0.12]]) {
    const doc = await io.read(`godot/assets/models/tree_autumn_${variant}.glb`);
    const root = doc.getRoot(), buffer = root.listBuffers()[0];
    for (const mesh of root.listMeshes()) for (const prim of mesh.listPrimitives()) {
      const source = prim.getAttribute('POSITION'), uv = prim.getAttribute('TEXCOORD_0');
      const atlas = prim.getMaterial().getBaseColorTexture();
      const {data, info} = await sharp(atlas.getImage()).ensureAlpha().raw().toBuffer({resolveWithObject:true});
      const lookup = new Map(), vertices = [], colours = [], counts = [], mapping = [];
      for (let i=0; i<source.getCount(); i++) {
        const p=source.getElement(i,[]), tex=uv.getElement(i,[]);
        const key=p.map(v=>Math.round(v*1e6)).join(',');
        let j=lookup.get(key);
        if (j===undefined) { j=vertices.length/3; lookup.set(key,j); vertices.push(...p); colours.push(0,0,0,1); counts.push(0); }
        const x=Math.min(info.width-1,Math.max(0,Math.floor(tex[0]*info.width)));
        const y=Math.min(info.height-1,Math.max(0,Math.floor(tex[1]*info.height)));
        for (let k=0;k<3;k++) colours[j*4+k]+=data[(y*info.width+x)*4+k]/255;
        counts[j]++; mapping.push(j);
      }
      for (let i=0;i<counts.length;i++) for(let k=0;k<3;k++) colours[i*4+k]/=counts[i];
      const indices=Uint32Array.from(prim.getIndices().getArray(),i=>mapping[i]);
      const positions=new Float32Array(vertices);
      const [reduced]=MeshoptSimplifier.simplify(indices,positions,3,Math.min(indices.length,target*3),error,['Prune']);
      const normals=new Float32Array(vertices.length);
      for(let i=0;i<reduced.length;i+=3) {
        const [a,b,c]=[reduced[i]*3,reduced[i+1]*3,reduced[i+2]*3];
        const u=[0,1,2].map(k=>positions[b+k]-positions[a+k]), v=[0,1,2].map(k=>positions[c+k]-positions[a+k]);
        const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
        for(const at of [a,b,c]) for(let k=0;k<3;k++) normals[at+k]+=n[k];
      }
      for(let i=0;i<normals.length;i+=3) { const length=Math.hypot(...normals.slice(i,i+3))||1; for(let k=0;k<3;k++) normals[i+k]/=length; }
      for(const name of prim.listSemantics()) prim.setAttribute(name,null);
      const accessor=(type,array)=>doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
      prim.setAttribute('POSITION',accessor('VEC3',positions)).setAttribute('NORMAL',accessor('VEC3',normals))
        .setAttribute('COLOR_0',accessor('VEC4',new Float32Array(colours))).setIndices(accessor('SCALAR',reduced));
      prim.setMaterial(doc.createMaterial().setDoubleSided(true).setRoughnessFactor(1));
      console.log(variant,lod,indices.length/3,'->',reduced.length/3);
    }
    const {prune}=await import('@gltf-transform/functions');
    await doc.transform(prune());
    await io.write(`godot/assets/planes/tree_${variant}_${lod}.glb`,doc);
  }
}
