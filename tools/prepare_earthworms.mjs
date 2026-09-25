// Reference-first Meshy geometry/PBR, with a connected, length-preserving rig.
// Inspect the design and model from meshy_earthworm_quality.py before running.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {dedup, prune, weld, textureCompress, transformMesh, getBounds} from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const names = process.argv.slice(2).length ? process.argv.slice(2) : ['zombie_earthworm', 'zombie_earthworm_ancient'];
const count = 22, length = 1.7, neck = length * .76;
const clips = {walk:4.8, burrow:2.0, emerge:1.8, attack:2.6, recovery:2.8, dive:1.8, death:3.2};
const clamp = (v,a=0,b=1) => Math.max(a,Math.min(b,v));
const smooth = v => {v=clamp(v); return v*v*(3-2*v);};
const dot = (a,b) => a.reduce((s,v,i)=>s+v*b[i],0);
const sub = (a,b) => a.map((v,i)=>v-b[i]);
const add = (a,b) => a.map((v,i)=>v+b[i]);
const norm = a => a.map(v=>v/Math.hypot(...a));
const mulQ = (a,b) => [
  a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],
  a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],
  a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],
  a[3]*b[3]-dot(a.slice(0,3),b.slice(0,3))];
const invQ = q => [-q[0],-q[1],-q[2],q[3]];
const rotate = (v,q) => mulQ(mulQ(q,[...v,0]),invQ(q)).slice(0,3);
const cross = (a,b) => [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];

// 26 Sep 2026: every clip carries a travelling serpentine wave (sway phase-shifted along the body) and a
// twist about the body axis, so the worm writhes instead of standing like a post: the risen body weaves
// its head hunting, the emerge overshoots and whips back, the strike coils sideways before the slam and
// shudders after it, the recovery drags the head up in jerks, the dive corkscrews into the ground and
// the death is a spasm that collapses.
function orientation(clip, u, p) {
  const wave = p*Math.PI*2, upper = smooth((u-.12)/.88), tip = upper*upper;
  let bend = .18*upper + .10*Math.sin(wave)*tip;
  let sway = .09*Math.sin(wave*2-u*7)*u + .06*Math.sin(wave-u*2.5)*tip;
  let twist = .12*Math.sin(wave-u*4)*u;
  if (clip === 'burrow') {bend=.15*upper; sway=.2*Math.sin(wave*3-u*6)*u; twist=.1*Math.sin(wave*2-u*3)*u;}
  if (clip === 'emerge') {
    const rise = Math.sin(p*Math.PI), shake = (1-p)*(1-p);
    bend = .18*upper + .55*rise*upper - .25*Math.sin(p*Math.PI*2)*tip;
    sway = .16*Math.sin(p*40)*shake*u + .12*rise*Math.sin(wave*2-u*6)*u;
    twist = .2*Math.sin(p*Math.PI*3)*(1-p)*u;
  }
  if (clip === 'attack') {
    // Slow recoil with a sideways coil, short readable pause, accelerating downward strike, a shudder.
    const pull = smooth(p/.6), strike = smooth((p-.73)/.27), after = smooth((p-.88)/.12);
    bend = (.18-.6*pull+2.82*strike)*upper;
    sway = .38*pull*(1-strike)*u + .06*Math.sin(p*60)*after*u;
    twist = .3*pull*(1-strike)*tip;
  }
  if (clip === 'recovery') {
    const lift = smooth((p-.15)/.85), jerk = Math.max(0, Math.sin(p*Math.PI*5))*(1-lift);
    bend = (2.4-2.22*lift-.18*Math.sin(lift*Math.PI))*upper - .12*jerk*tip;
    sway = .08*Math.sin(p*30)*(1-lift)*u + .05*Math.sin(wave*2-u*5)*u;
    twist = .15*Math.sin(p*Math.PI*2)*(1-lift)*u;
  }
  if (clip === 'dive') {bend=(.18+1.25*smooth(p))*upper; sway=.08*Math.sin(p*24)*(1-p)*u; twist=1.3*smooth(p)*u;}
  if (clip === 'death') {
    const fall = smooth(p/.82), spasm = (1-p)*(1-p);
    bend = (.18+1.6*fall)*smooth(u/.4) + .15*Math.sin(p*22)*spasm*tip;
    sway = .35*Math.sin(p*22)*spasm*u + .2*Math.sin(p*Math.PI)*u;
    twist = .5*Math.sin(p*9)*spasm*u;
  }
  const bendQ = [Math.sin(bend/2),0,0,Math.cos(bend/2)], swayQ = [0,0,Math.sin(sway/2),Math.cos(sway/2)], twistQ = [0,Math.sin(twist/2),0,Math.cos(twist/2)];
  return mulQ(mulQ(bendQ,swayQ),twistQ);
}

const reports = [];
for (const name of names) {
  const sourceDir = `meshy_output/earthworm_quality/${name}`;
  const doc = await io.read(`${sourceDir}/model.glb`);
  const root = doc.getRoot(), scene = root.listScenes()[0], meshes = [];
  for (const node of root.listNodes()) if (node.getMesh()) {
    const mesh = node.getMesh();
    transformMesh(mesh,node.getWorldMatrix());
    meshes.push(mesh);
  }
  for (const node of scene.listChildren()) scene.removeChild(node);
  meshes.forEach((mesh,i)=>scene.addChild(doc.createNode(`worm_mesh_${i}`).setMesh(mesh)));
  const positions = () => meshes.flatMap(mesh=>mesh.listPrimitives().flatMap(prim=>{
    const a=prim.getAttribute('POSITION');
    return Array.from({length:a.getCount()},(_,i)=>a.getElement(i,[]));
  }));
  let points=positions();
  const mean=[0,1,2].map(k=>points.reduce((s,p)=>s+p[k],0)/points.length);
  const centered=points.map(p=>sub(p,mean));
  const covariance=[0,1,2].map(i=>[0,1,2].map(j=>centered.reduce((s,p)=>s+p[i]*p[j],0)));
  let axis=norm([.1,1,.7]);
  for(let i=0;i<32;i++) axis=norm(covariance.map(row=>dot(row,axis)));
  const projections=centered.map(p=>dot(p,axis));
  const lo=Math.min(...projections), hi=Math.max(...projections), girth=[0,0], samples=[0,0];
  centered.forEach((p,i)=>{
    const u=(projections[i]-lo)/(hi-lo), side=u<.18?0:(u>.82?1:-1);
    if(side>=0) {girth[side]+=dot(p,p)-projections[i]**2; samples[side]++;}
  });
  if(girth[0]/samples[0]>girth[1]/samples[1]) axis=axis.map(v=>-v);
  // Both inspected image-to-3D exports have their maw at source +Y.
  // The ancient's curled tail fools a width-only head/tail heuristic.
  if(axis[1]<0) axis=axis.map(v=>-v);
  const right=norm([1,0,0].map((v,k)=>v-axis[0]*axis[k])), forward=cross(right,axis);
  meshes.forEach(mesh=>transformMesh(mesh,[right[0],axis[0],forward[0],0,right[1],axis[1],forward[1],0,right[2],axis[2],forward[2],0,0,0,0,1]));
  const box=getBounds(scene), scale=length/(box.max[1]-box.min[1]);
  const matrix=[scale,0,0,0,0,scale,0,0,0,0,scale,0,-(box.min[0]+box.max[0])*.5*scale,-box.min[1]*scale,-(box.min[2]+box.max[2])*.5*scale,1];
  meshes.forEach(mesh=>transformMesh(mesh,matrix));
  points=positions();
  // Slice centres follow the actual body. The maw shares a rigid head bone.
  const centres=Array.from({length:count},(_,i)=>{
    const y=neck*i/(count-1), band=points.filter(p=>Math.abs(p[1]-Math.max(y,.025))<.035);
    const median=k=>band.map(p=>p[k]).sort((a,b)=>a-b)[Math.floor(band.length/2)];
    if(!band.length) throw new Error(`${name}: missing body cross section at ${y}`);
    return [median(0),y,median(2)];
  });
  for(let pass=0;pass<3;pass++) {
    const previous=centres.map(p=>[...p]);
    for(let i=1;i<count-1;i++) for(const k of [0,2]) centres[i][k]=(previous[i-1][k]+previous[i][k]*2+previous[i+1][k])/4;
  }
  const buffer=root.listBuffers()[0]||doc.createBuffer(), skeleton=doc.createNode('WormRig');
  scene.addChild(skeleton);
  const skin=doc.createSkin('AnnelidSkin').setSkeleton(skeleton), joints=[], inverse=new Float32Array(count*16);
  for(let i=0;i<count;i++) {
    const [x,y,z]=centres[i], local=i?sub(centres[i],centres[i-1]):centres[i];
    const bone=doc.createNode(i>=count-3?`head_maw_${i}`:`spine_${i}`).setTranslation(local);
    (i?joints[i-1]:skeleton).addChild(bone); skin.addJoint(bone); joints.push(bone);
    inverse.set([1,0,0,0,0,1,0,0,0,0,1,0,-x,-y,-z,1],i*16);
  }
  skin.setInverseBindMatrices(doc.createAccessor().setType('MAT4').setArray(inverse).setBuffer(buffer));
  let triangleCount=0, removedDegenerates=0, vertexCount=0;
  for(const node of scene.listChildren()) if(node.getMesh()) {
    node.setSkin(skin);
    for(const primitive of node.getMesh().listPrimitives()) {
      const a=primitive.getAttribute('POSITION'), normals=primitive.getAttribute('NORMAL'), uv=primitive.getAttribute('TEXCOORD_0');
      if(!normals||!uv) throw new Error(`${name}: missing normals/UVs`);
      const ids=new Uint16Array(a.getCount()*4), weights=new Float32Array(a.getCount()*4);
      for(let v=0;v<a.getCount();v++) {
        const p=a.getElement(v,[]), n=normals.getElement(v,[]);
        if(![...p,...n,...uv.getElement(v,[])].every(Number.isFinite)||Math.hypot(...n)<.5) throw new Error(`${name}: invalid vertex ${v}`);
        const f=clamp(p[1]/neck*(count-1),0,count-1), low=Math.min(count-2,Math.floor(f)), mix=f-low;
        ids.set([low,low+1,0,0],v*4); weights.set([1-mix,mix,0,0],v*4);
      }
      vertexCount+=a.getCount();
      primitive.setAttribute('JOINTS_0',doc.createAccessor().setType('VEC4').setArray(ids).setBuffer(buffer));
      primitive.setAttribute('WEIGHTS_0',doc.createAccessor().setType('VEC4').setArray(weights).setBuffer(buffer));
      const old=primitive.getIndices()?.getArray()||Uint32Array.from({length:a.getCount()},(_,i)=>i), indices=[];
      for(let t=0;t<old.length;t+=3) {
        const [i,j,k]=old.slice(t,t+3), p=a.getElement(i,[]), q=a.getElement(j,[]), r=a.getElement(k,[]);
        if(i===j||i===k||j===k||Math.hypot(...cross(sub(q,p),sub(r,p)))<1e-13) {removedDegenerates++; continue;}
        indices.push(i,j,k);
      }
      triangleCount+=indices.length/3;
      primitive.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(indices)).setBuffer(buffer));
    }
  }
  let maxLengthError=0;
  for(const [clip,duration] of Object.entries(clips)) {
    const animation=doc.createAnimation(clip), frames=Math.round(duration*30)+1;
    const times=Float32Array.from({length:frames},(_,i)=>duration*i/(frames-1));
    const input=doc.createAccessor().setType('SCALAR').setArray(times).setBuffer(buffer);
    const tracks=Array.from({length:count},()=>[]);
    for(const t of times) {
      const q=Array.from({length:count},(_,i)=>orientation(clip,i/(count-1),t/duration));
      let point=centres[0];
      for(let i=0;i<count;i++) {
        tracks[i].push(...(i?mulQ(invQ(q[i-1]),q[i]):q[i]));
        if(i) {
          const delta=sub(centres[i],centres[i-1]), next=add(point,rotate(delta,q[i-1]));
          maxLengthError=Math.max(maxLengthError,Math.abs(Math.hypot(...sub(next,point))-Math.hypot(...delta)));
          point=next;
        }
      }
    }
    for(let i=0;i<count;i++) {
      const output=doc.createAccessor().setType('VEC4').setArray(new Float32Array(tracks[i])).setBuffer(buffer);
      const sampler=doc.createAnimationSampler().setInput(input).setOutput(output).setInterpolation('LINEAR');
      animation.addSampler(sampler);
      animation.addChannel(doc.createAnimationChannel().setTargetNode(joints[i]).setTargetPath('rotation').setSampler(sampler));
    }
  }
  for(const material of root.listMaterials()) {
    material.setMetallicFactor(0); material.setDoubleSided(false);
  }
  // Keep source microdetail: no 2K downscale or lossy normal-map compression.
  await doc.transform(weld(),dedup(),prune(),textureCompress({encoder:sharp,targetFormat:'webp',resize:[4096,4096],lossless:true}));
  const textureSizes=await Promise.all(root.listTextures().map(async texture=>{
    const {width,height}=await sharp(texture.getImage()).metadata(); return {name:texture.getName(),width,height};
  }));
  const output=`godot/assets/models/${name}.glb`;
  await io.write(output,doc);
  // Existing Godot texture imports otherwise retain the older BC1 setting.
  // BPTC/BC7 preserves subtle colour/roughness transitions on supported PCs.
  for(const filename of fs.readdirSync('godot/assets/models')) {
    if(!filename.startsWith(`${name}_`)||!filename.endsWith('.webp.import')) continue;
    if(name==='zombie_earthworm'&&filename.startsWith('zombie_earthworm_ancient')) continue;
    const path=`godot/assets/models/${filename}`;
    fs.writeFileSync(path,fs.readFileSync(path,'utf8').replace('compress/high_quality=false','compress/high_quality=true'));
  }
  const designStage=fs.existsSync(`${sourceDir}/design_straight_task.json`)?'design_straight':'design';
  const receipts=[designStage,'model'].map(stage=>JSON.parse(fs.readFileSync(`${sourceDir}/${stage}_task.json`)));
  fs.writeFileSync(`godot/assets/models/${name}.SOURCES.md`,
    `# ${name}\n\nGeometry and PBR textures generated with Meshy from an inspected design reference. Original files and requests: \`${sourceDir}/\`.\n\n`+
    receipts.map((r,i)=>`${['Design','Image to 3D'][i]}: \`${r.id}\`; ${r.consumed_credits} credits.`).join('\n\n')+
    `\n\n${triangleCount.toLocaleString('en-US')} triangles. Source-resolution PBR maps retained with lossless WebP compression (4K colour/normal; source roughness resolution recorded in artifacts/earthworm-mesh-quality.json).\n`+
    '\n22-joint connected annelid skeleton; fixed bone lengths and rigid maw. Seven locally authored animation clips, including recovery. These animations are not Meshy API output.\n'+
    '\nPrepared by `tools/prepare_earthworms.mjs`. Neutral height 1.7 m; scaled to 14 m / 19 m in game.\n');
  const report={name,triangleCount,vertexCount,removedDegenerates,joints:count,maxLengthError,textureSizes,clips:Object.keys(clips),axis,bytes:fs.statSync(output).size};
  reports.push(report); console.log('PREPARED',JSON.stringify(report));
}
fs.mkdirSync('artifacts',{recursive:true});
const reportPath='artifacts/earthworm-mesh-quality.json';
const previous=fs.existsSync(reportPath)?JSON.parse(fs.readFileSync(reportPath)):[];
fs.writeFileSync(reportPath,JSON.stringify([...previous.filter(r=>!names.includes(r.name)),...reports],null,2));
