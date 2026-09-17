import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { getBounds } from '@gltf-transform/core';
import fs from 'node:fs';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const out = {};
for (const f of fs.readdirSync('godot/assets/models').filter(f => f.endsWith('.glb'))) {
  const doc = await io.read('godot/assets/models/' + f);
  const scene = doc.getRoot().getDefaultScene() || doc.getRoot().listScenes()[0];
  const b = getBounds(scene);
  out[f.replace('.glb', '')] = { min: b.min.map(v => +v.toFixed(3)), max: b.max.map(v => +v.toFixed(3)), anims: doc.getRoot().listAnimations().map(a => a.getName()) };
}
console.log(JSON.stringify(out, null, 1));
