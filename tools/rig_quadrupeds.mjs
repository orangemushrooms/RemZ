// Local skeletal authoring from the shipped static Meshy animals. No service calls.
// Source meshes stay unchanged; limb positions measured from side/front projections.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {transformMesh, prune} from '@gltf-transform/functions';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const clamp = (v,a=0,b=1)=>Math.max(a,Math.min(b,v));
const smooth = (a,b,v)=>{const t=clamp((v-a)/(b-a));return t*t*(3-2*t);};
const sub=(a,b)=>a.map((v,i)=>v-b[i]);
const median=a=>a.sort((a,b)=>a-b)[Math.floor(a.length/2)];
const qx=a=>[Math.sin(a/2),0,0,Math.cos(a/2)];
for (const name of ['deer','stag','zombie_stag']) {
  const doc=await io.read(`godot/assets/models/${name}.glb`),root=doc.getRoot(),scene=root.listScenes()[0];
  const meshes=[];
  for(const node of root.listNodes()) if(node.getMesh()) {
    const mesh=node.getMesh();transformMesh(mesh,node.getWorldMatrix());meshes.push(mesh);
  }
  for(const n of scene.listChildren())scene.removeChild(n);
  const points=meshes.flatMap(m=>m.listPrimitives().flatMap(p=>{
    const a=p.getAttribute('POSITION');return Array.from({length:a.getCount()},(_,i)=>a.getElement(i,[]));
  }));
  const bottom=Math.min(...points.map(p=>p[1])),hipY=name==='deer'?-.08:-.18;
  const bones=[['Body',-1,[0,hipY,0]],['Neck',0,[0,.0,.30]],['Head',1,[0,.24,.47]]];
  const legs=[];
  for(const front of [true,false])for(const side of [-1,1]) {
    const pts=points.filter(p=>p[1]<hipY-.2&&p[0]*side>0&&(front?p[2]>-.08:p[2]<-.08));
    const feet=pts.filter(p=>p[1]<bottom+.13);
    const x=median(pts.map(p=>p[0])),z=median(feet.map(p=>p[2]));
    const hip=[x,hipY,z+(front?-.035:.075)],knee=[x,(bottom+hipY)/2,z+(front?.025:-.12)],foot=[x,bottom+.045,z];
    const id=bones.length;
    bones.push([`Leg${id}`,0,hip],[`Knee${id}`,id,knee],[`Hoof${id}`,id+1,foot]);
    legs.push({front,side,id,hip,knee,foot});
  }
  const buffer=root.listBuffers()[0]||doc.createBuffer(),rig=doc.createNode('QuadrupedRig');scene.addChild(rig);
  const skin=doc.createSkin('QuadrupedSkin').setSkeleton(rig),joints=[],inverse=new Float32Array(bones.length*16);
  for(let i=0;i<bones.length;i++) {
    const [n,parent,p]=bones[i],node=doc.createNode(n).setTranslation(parent<0?p:sub(p,bones[parent][2]));
    (parent<0?rig:joints[parent]).addChild(node);joints.push(node);skin.addJoint(node);
    inverse.set([1,0,0,0,0,1,0,0,0,0,1,0,-p[0],-p[1],-p[2],1],i*16);
  }
  skin.setInverseBindMatrices(doc.createAccessor().setType('MAT4').setArray(inverse).setBuffer(buffer));
  for(const mesh of meshes) {
    scene.addChild(doc.createNode('Animal').setMesh(mesh).setSkin(skin));
    for(const prim of mesh.listPrimitives()) {
      const pos=prim.getAttribute('POSITION'),ids=new Uint16Array(pos.getCount()*4),weights=new Float32Array(pos.getCount()*4);
      for(let v=0;v<pos.getCount();v++) {
        const p=pos.getElement(v,[]),leg=legs.find(l=>l.side*p[0]>=0&&(l.front?p[2]>=-.08:p[2]<-.08));
        // Keep the belly/rib cage on the body. A simple lower-half mask also
        // assigned the belly between the legs to a hip and pulled it into spikes
        // when the knees folded. Below the belly only the four legs remain.
        const attachment=(1-smooth(.12,.30,Math.abs(p[2]-leg.hip[2])))*smooth(.015,.09,Math.abs(p[0]));
        const lower=1-smooth(bottom+.32,bottom+.57,p[1]);
        const limb=(1-smooth(hipY-.08,hipY+.12,p[1]))*(lower+(1-lower)*attachment);
        const knee=1-smooth(leg.knee[1]-.09,leg.knee[1]+.09,p[1]);
        const hoof=1-smooth(bottom+.08,bottom+.19,p[1]);
        const head=smooth(.04,.35,p[1])*smooth(.12,.4,p[2]);
        const neck=smooth(hipY+.05,.22,p[1])*smooth(.10,.35,p[2]);
        const chosen=[[0,(1-limb)*(1-neck)],[1,(1-limb)*neck*(1-head)],[2,(1-limb)*neck*head],
          [leg.id,limb*(1-knee)],[leg.id+1,limb*knee*(1-hoof)],[leg.id+2,limb*knee*hoof]].filter(v=>v[1]>1e-6).sort((a,b)=>b[1]-a[1]).slice(0,4);
        const sum=chosen.reduce((s,v)=>s+v[1],0);
        chosen.forEach(([id,w],i)=>{ids[v*4+i]=id;weights[v*4+i]=w/sum;});
      }
      prim.setAttribute('JOINTS_0',doc.createAccessor().setType('VEC4').setArray(ids).setBuffer(buffer));
      prim.setAttribute('WEIGHTS_0',doc.createAccessor().setType('VEC4').setArray(weights).setBuffer(buffer));
    }
  }
  // Wider strides and a folded return stroke make all four legs readable at
  // flight speed. Keep these rates in sync with deer.gd / zombie.gd:
  // walk .42/(.63*1.25), run 1.08/(.27*.72), in source-model units/second.
  for(const [clip,duration] of Object.entries({idle:4,walk:1.25,run:.72,graze:5,attack:.8})) {
    const anim=doc.createAnimation(clip),times=Float32Array.from({length:61},(_,i)=>duration*i/60);
    const input=doc.createAccessor().setType('SCALAR').setArray(times).setBuffer(buffer);
    const tracks=bones.map(()=>[]),body=[];
    for(let f=0;f<times.length;f++) {
      const t=f/60,phase=t*Math.PI*2,moving=clip==='walk'||clip==='run',run=clip==='run';
      const bob=moving?(run?.035:.012)*Math.cos(phase*2):.004*Math.sin(phase);
      body.push(0,hipY+bob,0);
      const angles=bones.map(()=>0);
      const dip=clip==='graze'?Math.pow(Math.sin(Math.PI*t),2):clip==='attack'?Math.pow(Math.sin(Math.PI*t),2):0;
      angles[1]=.035*Math.sin(phase)-dip*.48;angles[2]=-.025*Math.sin(phase)-dip*.30;
      if(moving)for(let k=0;k<legs.length;k++) {
        const l=legs[k],offset=run?[0,.10,.52,.62][k]:[0,.5,.75,.25][k];
        const u=(t+offset)%1,stance=run?.27:.63,span=run?1.08:.42;
        let travel,lift;
        if(u<stance){travel=span*(.5-u/stance);lift=0;}else{const swing=(u-stance)/(1-stance);travel=span*(-.5+smooth(0,1,swing));lift=(run?(l.hip[1]-l.foot[1])*.55:.15)*Math.sin(swing*Math.PI)**2;}
        let dy=l.foot[1]+lift-bob-l.hip[1],dz=l.foot[2]+travel-l.hip[2];
        const a=Math.hypot(...sub(l.knee,l.hip)),b=Math.hypot(...sub(l.foot,l.knee)),dist=clamp(Math.hypot(dy,dz),Math.abs(a-b)+.001,a+b-.001);
        // Clamp the target itself as well as the cosine-law distance. Otherwise
        // the lower joint aims beyond its reach and never fully folds on return.
        const reach=dist/Math.max(Math.hypot(dy,dz),.001);dy*=reach;dz*=reach;
        const direction=Math.atan2(dz,-dy),bend=Math.acos(clamp((a*a+dist*dist-b*b)/(2*a*dist),-1,1));
        const upper=direction+(l.front?1:-1)*bend;
        const kneeY=-Math.cos(upper)*a,kneeZ=Math.sin(upper)*a,lower=Math.atan2(dz-kneeZ, -(dy-kneeY));
        const restU=Math.atan2(l.knee[2]-l.hip[2],l.hip[1]-l.knee[1]);
        const restL=Math.atan2(l.foot[2]-l.knee[2],l.knee[1]-l.foot[1]);
        angles[l.id]=restU-upper;angles[l.id+1]=restL-lower-angles[l.id];angles[l.id+2]=-angles[l.id]-angles[l.id+1];
      }
      angles.forEach((a,i)=>tracks[i].push(...qx(a)));
    }
    function track(i,path,values,type){const output=doc.createAccessor().setType(type).setArray(new Float32Array(values)).setBuffer(buffer);const s=doc.createAnimationSampler().setInput(input).setOutput(output).setInterpolation('LINEAR');anim.addSampler(s);anim.addChannel(doc.createAnimationChannel().setTargetNode(joints[i]).setTargetPath(path).setSampler(s));}
    tracks.forEach((values,i)=>track(i,'rotation',values,'VEC4'));track(0,'translation',body,'VEC3');
  }
  await doc.transform(prune());
  await io.write(`godot/assets/models/${name}_animated.glb`,doc);
  console.log('QUADRUPED',name,'bones',bones.length,'vertices',points.length);
}
