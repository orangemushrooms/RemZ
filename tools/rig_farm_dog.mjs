// Articulate the shipped Meshy farm dog without changing its source mesh or textures.
// Run from the repository root: node tools/rig_farm_dog.mjs
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {transformMesh, prune} from '@gltf-transform/functions';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read('godot/assets/models/zombie_dog.glb');
const root = doc.getRoot(), scene = root.listScenes()[0];
const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };
const sub = (a, b) => a.map((v, i) => v - b[i]);
const qx = a => [Math.sin(a / 2), 0, 0, Math.cos(a / 2)];
const meshes = [];
for (const node of root.listNodes()) if (node.getMesh()) {
  const mesh = node.getMesh();
  transformMesh(mesh, node.getWorldMatrix());
  meshes.push(mesh);
}
for (const node of scene.listChildren()) scene.removeChild(node);

// Joint positions measured in the source mesh's space (+Z is the muzzle).
// The hind knee is the backwards hock; its weight transition follows the thigh.
const bones = [
  ['Body', -1, [0, .10, 0]],
  ['DogNeck', 0, [0, .16, .35]],
  ['DogHead', 1, [0, .22, .62]],
  ['DogTail', 0, [0, .13, -.53]],
];
const legs = [];
for (const front of [true, false]) for (const side of [-1, 1]) {
  const x = side * (front ? .115 : .125);
  const hip = [x, front ? .09 : .12, front ? .30 : -.43];
  const knee = [x, front ? -.22 : -.28, front ? .28 : -.65];
  const foot = [x, -.445, front ? .34 : -.59];
  const id = bones.length, label = `${front ? 'Front' : 'Hind'}${side < 0 ? 'Left' : 'Right'}`;
  bones.push([label + 'Upper', 0, hip], [label + 'Lower', id, knee], [label + 'Paw', id + 1, foot]);
  legs.push({front, side, id, hip, knee, foot});
}
const buffer = root.listBuffers()[0] || doc.createBuffer();
const rig = doc.createNode('FarmDogRig');
scene.addChild(rig);
const skin = doc.createSkin('FarmDogSkin').setSkeleton(rig);
const joints = [], inverse = new Float32Array(bones.length * 16);
for (let i = 0; i < bones.length; i++) {
  const [name, parent, p] = bones[i];
  const joint = doc.createNode(name).setTranslation(parent < 0 ? p : sub(p, bones[parent][2]));
  (parent < 0 ? rig : joints[parent]).addChild(joint);
  joints.push(joint);
  skin.addJoint(joint);
  inverse.set([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0], -p[1], -p[2], 1], i * 16);
}
const accessor = (type, values) => doc.createAccessor().setType(type).setArray(values).setBuffer(buffer);
skin.setInverseBindMatrices(accessor('MAT4', inverse));
for (const mesh of meshes) {
  scene.addChild(doc.createNode('FarmDog').setMesh(mesh).setSkin(skin));
  for (const prim of mesh.listPrimitives()) {
    const pos = prim.getAttribute('POSITION');
    const ids = new Uint16Array(pos.getCount() * 4), weights = new Float32Array(pos.getCount() * 4);
    for (let v = 0; v < pos.getCount(); v++) {
      const p = pos.getElement(v, []);
      const leg = legs.find(l => l.side * p[0] >= 0 && (l.front ? p[2] >= -.12 : p[2] < -.12));
      const tail = (1 - smooth(-.76, -.55, p[2])) * (1 - smooth(.05, .10, Math.abs(p[0])));
      const limb = (1 - smooth(-.11, .14, p[1])) * (1 - tail)
        * smooth(.03, .09, Math.abs(p[0])) * (1 - smooth(.44, .56, p[2]));
      const knee = 1 - smooth(leg.knee[1] - .08, leg.knee[1] + .10, p[1]);
      const paw = 1 - smooth(-.43, -.35, p[1]);
      const neck = smooth(.33, .60, p[2]) * (1 - limb) * (1 - tail);
      const head = smooth(.53, .73, p[2]);
      const chosen = [
        [0, Math.max(0, 1 - limb - neck - tail)], [1, neck * (1 - head)], [2, neck * head], [3, tail],
        [leg.id, limb * (1 - knee)], [leg.id + 1, limb * knee * (1 - paw)], [leg.id + 2, limb * knee * paw],
      ].filter(v => v[1] > 1e-6).sort((a, b) => b[1] - a[1]).slice(0, 4);
      const sum = chosen.reduce((s, v) => s + v[1], 0);
      chosen.forEach(([id, weight], i) => { ids[v * 4 + i] = id; weights[v * 4 + i] = weight / sum; });
    }
    prim.setAttribute('JOINTS_0', accessor('VEC4', ids));
    prim.setAttribute('WEIGHTS_0', accessor('VEC4', weights));
  }
}

// A planted paw travels back linearly; the return stroke lifts and folds the leg.
// Natural speeds (model units/second): walk .38/(.62*.8), run .80/(.28*.62).
for (const [clip, duration] of Object.entries({idle: 3.2, walk: .8, run: .62, attack: .36})) {
  const anim = doc.createAnimation(clip);
  const times = Float32Array.from({length: 61}, (_, i) => duration * i / 60);
  const input = accessor('SCALAR', times), rotations = bones.map(() => []), body = [];
  for (let frame = 0; frame < times.length; frame++) {
    const t = frame / 60, phase = t * Math.PI * 2, moving = clip === 'walk' || clip === 'run', run = clip === 'run';
    const bob = moving ? (run ? .026 : .009) * Math.cos(phase * 2) : .003 * Math.sin(phase);
    body.push(0, .10 + bob, 0);
    const angles = bones.map(() => 0);
    const bite = clip === 'attack' ? Math.sin(Math.PI * t) ** 2 : 0;
    angles[1] = .025 * Math.sin(phase) - .16 * bite;
    angles[2] = -.018 * Math.sin(phase) - .10 * bite;
    angles[3] = .06 * Math.sin(phase + .5);
    if (moving) for (let k = 0; k < legs.length; k++) {
      const leg = legs[k];
      const offset = run ? [0, .12, .52, .64][k] : [0, .5, .5, 0][k];
      const u = (t + offset) % 1, stance = run ? .28 : .62, span = run ? .80 : .38;
      let travel, lift;
      if (u < stance) { travel = span * (.5 - u / stance); lift = 0; }
      else {
        const swing = (u - stance) / (1 - stance);
        travel = span * (-.5 + smooth(0, 1, swing));
        lift = (run ? .23 : .11) * Math.sin(swing * Math.PI) ** 2;
      }
      const dy = leg.foot[1] + lift - bob - leg.hip[1], dz = leg.foot[2] + travel - leg.hip[2];
      const a = Math.hypot(...sub(leg.knee, leg.hip)), b = Math.hypot(...sub(leg.foot, leg.knee));
      const dist = clamp(Math.hypot(dy, dz), Math.abs(a - b) + .001, a + b - .001);
      const direction = Math.atan2(dz, -dy), bend = Math.acos(clamp((a*a + dist*dist - b*b) / (2*a*dist), -1, 1));
      const upper = direction + (leg.front ? 1 : -1) * bend;
      const lower = Math.atan2(dz - Math.sin(upper)*a, -(dy + Math.cos(upper)*a));
      const restUpper = Math.atan2(leg.knee[2] - leg.hip[2], leg.hip[1] - leg.knee[1]);
      const restLower = Math.atan2(leg.foot[2] - leg.knee[2], leg.knee[1] - leg.foot[1]);
      angles[leg.id] = restUpper - upper;
      angles[leg.id + 1] = restLower - lower - angles[leg.id];
      angles[leg.id + 2] = -angles[leg.id] - angles[leg.id + 1];
    }
    angles.forEach((a, i) => rotations[i].push(...qx(a)));
  }
  function track(index, path, values, type) {
    const sampler = doc.createAnimationSampler().setInput(input).setOutput(accessor(type, new Float32Array(values))).setInterpolation('LINEAR');
    anim.addSampler(sampler);
    anim.addChannel(doc.createAnimationChannel().setTargetNode(joints[index]).setTargetPath(path).setSampler(sampler));
  }
  rotations.forEach((values, i) => track(i, 'rotation', values, 'VEC4'));
  track(0, 'translation', body, 'VEC3');
}
await doc.transform(prune());
await io.write('godot/assets/models/zombie_dog_animated.glb', doc);
console.log('FARM_DOG_RIG bones=%d clips=idle,walk,run,attack', bones.length);
