// Local rig and animation authoring for the user's static Forest Spirit GLB.
// The source model stays untouched; this writes an optimized, skinned GLB.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {weld, simplify} from '@gltf-transform/functions';
import {MeshoptSimplifier} from 'meshoptimizer';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SOURCE = path.join(ROOT, 'assets/raw/forest_spirit_source/Meshy_AI_Sinew_of_the_Abyss_0925164434_texture.glb');
const OUTPUT = path.join(ROOT, 'assets/raw/forest_spirit/rigged_local.glb');
const GAME_OUTPUT = path.join(ROOT, 'godot/assets/models/zombie_forest_spirit.glb');
const clamp = (v, a=0, b=1) => Math.max(a, Math.min(b, v));
const smooth = (a, b, x) => { const t=clamp((x-a)/(b-a)); return t*t*(3-2*t); };
const mix = (a,b,t) => a+(b-a)*t;
const qmul = (a,b) => [a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],a[3]*b[3]-a[0]*b[0]-a[1]*b[1]-a[2]*b[2]];
const axisQ = (axis, angle) => { const s=Math.sin(angle/2); return [axis[0]*s,axis[1]*s,axis[2]*s,Math.cos(angle/2)]; };
const rotation = (x=0,y=0,z=0) => qmul(qmul(axisQ([0,1,0],y),axisQ([0,0,1],z)),axisQ([1,0,0],x));

// Joint positions were measured from front and side projections of the supplied mesh.
// 0 hips, 1 spine, 2 chest, 3 head; 4..9 arms; 10..15 legs.
const bones = [
  ['Hips',-1,[0,-.22,0]], ['Spine',0,[0,.13,0]], ['Chest',1,[0,.53,0]], ['Head',2,[0,.79,.09]],
  ['LeftShoulder',2,[-.27,.59,0]], ['LeftForeArm',4,[-.38,.15,0]], ['LeftHand',5,[-.51,-.36,.01]],
  ['RightShoulder',2,[.27,.59,0]], ['RightForeArm',7,[.38,.15,0]], ['RightHand',8,[.51,-.36,.01]],
  ['LeftUpLeg',0,[-.14,-.36,0]], ['LeftLeg',10,[-.15,-.66,0]], ['LeftFoot',11,[-.15,-.87,.04]],
  ['RightUpLeg',0,[.14,-.36,0]], ['RightLeg',13,[.15,-.66,0]], ['RightFoot',14,[.15,-.87,.04]],
];

function influences(x,y) {
  const ax=Math.abs(x), side=x<0, arm=smooth(.19+Math.max(0,-y)*.09,.32+Math.max(0,-y)*.09,ax);
  const leg=(1-arm)*smooth(-.13,-.43,y)*(1-smooth(.19,.30,ax));
  const body=Math.max(0,1-arm-leg), result=[];
  const add=(id,w)=>{ if(w>1e-5) result.push([id,w]); };
  // The sinewy torso blends into the hood rather than hinging as a hard cap.
  const head=smooth(.59,.79,y), chest=smooth(.27,.57,y)*(1-head), hips=1-smooth(-.31,-.06,y);
  const spine=Math.max(0,1-head-chest-hips);
  add(0,body*hips); add(1,body*spine); add(2,body*chest); add(3,body*head);
  const upper=smooth(-.02,.34,y), hand=1-smooth(-.60,-.25,y), fore=Math.max(0,1-upper-hand);
  add(side?4:7,arm*upper); add(side?5:8,arm*fore); add(side?6:9,arm*hand);
  const thigh=smooth(-.65,-.40,y), foot=1-smooth(-.88,-.73,y), shin=Math.max(0,1-thigh-foot);
  add(side?10:13,leg*thigh); add(side?11:14,leg*shin); add(side?12:15,leg*foot);
  result.sort((a,b)=>b[1]-a[1]);
  const chosen=result.slice(0,4), total=chosen.reduce((n,item)=>n+item[1],0);
  if(total<.001) return [[0,1]];
  return chosen.map(([id,w])=>[id,w/total]);
}

const clips={idle:3.6,walk:1.65,attack:1.15,attack2:1.15,pulse:1.5,hit:.55,death:2.0,scream:1.7};
function pose(clip,t,d) {
  const u=clamp(t/d), p=2*Math.PI*u, a=Array.from({length:bones.length},()=>[0,0,0]);
  const set=(i,x=0,y=0,z=0)=>{a[i]=[x,y,z];};
  const breathe=Math.sin(p), sway=Math.sin(p*.5), step=Math.sin(p);
  if(clip==='idle') {
    set(1,.025*breathe,0,.025*sway); set(2,-.035*breathe,0,-.035*sway); set(3,.045*breathe,0,.035*sway);
    set(4,.06*breathe,0,-.04*sway); set(7,-.06*breathe,0,.04*sway);
    set(5,.035*breathe); set(8,-.035*breathe);
  } else if(clip==='walk') {
    set(0,.045*Math.sin(2*p),.045*step,.025*step); set(1,.045*step,0,-.045*step); set(2,-.06*step,0,-.04*step);
    set(3,-.045*step,0,.035*step);
    set(4,-.34*step,0,-.08); set(5,-.17*step); set(6,-.08*step,0,-.06);
    set(7,.34*step,0,.08); set(8,.17*step); set(9,.08*step,0,.06);
    set(10,.29*step); set(11,.17*Math.max(0,-step)); set(12,-.07*Math.max(0,-step));
    set(13,-.29*step); set(14,.17*Math.max(0,step)); set(15,-.07*Math.max(0,step));
  } else if(clip==='attack'||clip==='attack2') {
    const side=clip==='attack'?1:-1, wind=smooth(0,.3,u), strike=smooth(.30,.52,u), recover=smooth(.58,1,u);
    const drive=wind*(1-strike)+strike*(1-recover), lean=-.12*wind+.43*strike*(1-recover);
    set(0,.10*drive,side*.10*drive); set(1,lean,side*.14*drive); set(2,.13*drive,side*.16*drive); set(3,-.10*drive);
    const front=side===1?4:7, fore=side===1?5:8, hand=side===1?6:9;
    set(front,mix(-.35,1.05,strike)*wind*(1-recover),0,side*.12*drive);
    set(fore,mix(-.18,.5,strike)*wind*(1-recover),0,side*.24*drive);
    set(hand,-.12*drive,0,side*.20*drive);
    set(side===1?7:4,-.12*drive); set(side===1?8:5,.10*drive);
  } else if(clip==='pulse') {
    const raise=smooth(0,.58,u), slam=smooth(.68,.96,u);
    set(0,-.06*raise+.18*slam); set(1,-.20*raise+.37*slam); set(2,-.10*raise+.16*slam); set(3,-.12*raise+.16*slam);
    set(4,-.55*raise+1.05*slam,0,-.56*raise+.24*slam); set(5,-.24*raise+.55*slam,0,-.22*raise);
    set(7,-.55*raise+1.05*slam,0,.56*raise-.24*slam); set(8,-.24*raise+.55*slam,0,.22*raise);
  } else if(clip==='hit') {
    const flinch=Math.sin(Math.PI*u);
    set(0,-.10*flinch); set(1,-.23*flinch,0,-.06*flinch); set(2,-.13*flinch); set(3,.16*flinch);
    set(4,-.20*flinch,0,-.14*flinch); set(7,-.20*flinch,0,.14*flinch);
  } else if(clip==='death') {
    const fall=smooth(.04,.9,u), recoil=Math.sin(Math.PI*clamp(u/.6));
    set(0,.30*fall,0,.23*fall); set(1,.88*fall,0,-.08*fall); set(2,.52*fall); set(3,.38*fall);
    set(4,-.20*recoil+.40*fall,0,-.44*fall); set(5,.36*fall);
    set(7,-.15*recoil+.55*fall,0,.44*fall); set(8,.42*fall);
    set(10,-.15*fall); set(11,.60*fall); set(13,-.24*fall); set(14,.45*fall);
  } else if(clip==='scream') {
    const rise=Math.sin(Math.PI*u);
    set(0,-.08*rise); set(1,-.23*rise); set(2,-.12*rise); set(3,-.32*rise);
    set(4,-.45*rise,0,-.5*rise); set(7,-.45*rise,0,.5*rise);
    set(5,-.22*rise); set(8,-.22*rise);
  }
  return a;
}

const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc=await io.read(SOURCE), root=doc.getRoot();
const before=root.listMeshes().flatMap(m=>m.listPrimitives()).reduce((n,p)=>n+(p.getIndices()?.getCount()||0)/3,0);
await MeshoptSimplifier.ready;
await doc.transform(weld(),simplify({simplifier:MeshoptSimplifier,ratio:.18,error:.015}));
const meshNodes=root.listNodes().filter(node=>node.getMesh()), buffer=root.listBuffers()[0]||doc.createBuffer();
const rig=doc.createNode('ForestRig'); root.listScenes()[0].addChild(rig);
const skin=doc.createSkin('ForestSkin').setSkeleton(rig), joints=[];
const inverse=new Float32Array(bones.length*16);
for(let i=0;i<bones.length;i++) {
  const [name,parent,at]=bones[i], origin=parent<0?[0,0,0]:bones[parent][2];
  const joint=doc.createNode(name).setTranslation(at.map((v,k)=>v-origin[k]));
  (parent<0?rig:joints[parent]).addChild(joint); skin.addJoint(joint); joints.push(joint);
  inverse.set([1,0,0,0,0,1,0,0,0,0,1,0,-at[0],-at[1],-at[2],1],i*16);
}
skin.setInverseBindMatrices(doc.createAccessor().setType('MAT4').setArray(inverse).setBuffer(buffer));
let vertices=0, triangles=0, minimumWeight=1;
for(const node of meshNodes) {
  node.setSkin(skin);
  for(const primitive of node.getMesh().listPrimitives()) {
    const position=primitive.getAttribute('POSITION'), array=position.getArray(), count=position.getCount();
    const ids=new Uint16Array(count*4), weights=new Float32Array(count*4);
    for(let v=0;v<count;v++) {
      const w=influences(array[v*3],array[v*3+1]);
      for(let k=0;k<w.length;k++) { ids[v*4+k]=w[k][0]; weights[v*4+k]=w[k][1]; }
      minimumWeight=Math.min(minimumWeight,w.reduce((sum,item)=>sum+item[1],0));
    }
    primitive.setAttribute('JOINTS_0',doc.createAccessor().setType('VEC4').setArray(ids).setBuffer(buffer));
    primitive.setAttribute('WEIGHTS_0',doc.createAccessor().setType('VEC4').setArray(weights).setBuffer(buffer));
    vertices+=count; triangles+=(primitive.getIndices()?.getCount()||0)/3;
  }
}
for(const [clip,duration] of Object.entries(clips)) {
  const anim=doc.createAnimation(clip), frames=Math.round(duration*30)+1;
  const times=Float32Array.from({length:frames},(_,i)=>duration*i/(frames-1));
  const input=doc.createAccessor().setType('SCALAR').setArray(times).setBuffer(buffer);
  const tracks=Array.from({length:bones.length},()=>new Float32Array(frames*4));
  for(let frame=0;frame<frames;frame++) {
    const angles=pose(clip,times[frame],duration);
    for(let j=0;j<bones.length;j++) tracks[j].set(rotation(...angles[j]),frame*4);
  }
  for(let j=0;j<bones.length;j++) {
    const output=doc.createAccessor().setType('VEC4').setArray(tracks[j]).setBuffer(buffer);
    const sampler=doc.createAnimationSampler().setInput(input).setOutput(output).setInterpolation('LINEAR');
    anim.addSampler(sampler);
    anim.addChannel(doc.createAnimationChannel().setTargetNode(joints[j]).setTargetPath('rotation').setSampler(sampler));
  }
}
fs.mkdirSync(path.dirname(OUTPUT),{recursive:true});
await io.write(OUTPUT,doc);
fs.copyFileSync(OUTPUT,GAME_OUTPUT);
console.log(JSON.stringify({source:SOURCE,output:GAME_OUTPUT,triangles_before:before,triangles_after:triangles,vertices,joints:bones.length,animations:Object.keys(clips),minimumWeight,bytes:fs.statSync(OUTPUT).size}));
