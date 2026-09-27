// Re-author motion only: preserve the shipped mesh, textures, bind pose and fixed bone lengths.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);
const smooth=t=>{t=Math.max(0,Math.min(1,t));return t*t*(3-2*t);};
const mul=(a,b)=>[a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],a[3]*b[3]-a[0]*b[0]-a[1]*b[1]-a[2]*b[2]];
const inverse=q=>[-q[0],-q[1],-q[2],q[3]];
function orientation(clip,u,t){
  const p=t*Math.PI*2,upper=smooth((u-.08)/.92),tip=upper*upper;
  let bend=.22*upper,sway=0,twist=0;
  if(clip==='walk'||clip==='burrow') {
    const power=clip==='burrow'?1.3:1;
    bend+=power*.10*(Math.sin(p-u*3.8)-Math.sin(-u*3.8))*tip;
    sway=power*.15*(Math.sin(p-u*5.5)-Math.sin(-u*5.5))*upper;
    twist=.09*(Math.sin(p-u*3)-Math.sin(-u*3))*upper;
  } else if(clip==='emerge') {
    bend+=.30*Math.sin(t*Math.PI)*upper-.12*Math.sin(p)*tip;
    sway=.12*Math.sin(p-u*2)*Math.sin(t*Math.PI)*upper;
  } else if(clip==='attack') {
    const recoil=smooth(t/.64)*(1-smooth((t-.66)/.34));
    const strike=smooth((t-.70)/.30);
    bend+=(-.48*recoil+1.85*strike)*upper;
    sway=.25*recoil*tip;twist=.15*recoil*upper;
  } else if(clip==='recovery') {
    bend+=1.85*(1-smooth(t))*upper;
    sway=.10*Math.sin(t*Math.PI)*Math.sin(p-u*3)*upper;
  } else if(clip==='dive') {
    bend+=1.25*smooth(t)*upper;
    sway=.15*Math.sin(p-u*3)*Math.sin(t*Math.PI)*upper;
    twist=.5*smooth(t)*upper;
  } else if(clip==='death') {
    bend+=1.65*smooth(t)*upper;
    sway=.13*Math.sin(p*2-u*2)*Math.sin(t*Math.PI)*(1-t)*upper;
  }
  return mul(mul([Math.sin(bend/2),0,0,Math.cos(bend/2)],[0,0,Math.sin(sway/2),Math.cos(sway/2)]),[0,Math.sin(twist/2),0,Math.cos(twist/2)]);
}
for(const name of ['zombie_earthworm','zombie_earthworm_ancient']) {
  const path=`godot/assets/models/${name}.glb`,doc=await io.read(path);
  for(const animation of doc.getRoot().listAnimations())for(const channel of animation.listChannels()) {
    if(channel.getTargetPath()!=='rotation')continue;
    const bone=Number(channel.getTargetNode().getName().split('_').at(-1));
    if(!Number.isInteger(bone))continue;
    const sampler=channel.getSampler(),times=sampler.getInput().getArray(),out=sampler.getOutput();
    const values=new Float32Array(times.length*4),duration=times.at(-1);
    times.forEach((t,i)=>{
      const q=orientation(animation.getName(),bone/21,t/duration);
      values.set(bone?mul(inverse(orientation(animation.getName(),(bone-1)/21,t/duration)),q):q,i*4);
    });
    out.setArray(values);
  }
  await io.write(path,doc);console.log('WORM_MOTION',name);
}
