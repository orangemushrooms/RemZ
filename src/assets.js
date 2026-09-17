// Model manifest + loader with primitive fallbacks. Replace a model by dropping a GLB into public/models/.
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { clone as skeletonClone } from 'three/examples/jsm/utils/SkeletonUtils.js';

export const MANIFEST = {
  tree_pine:  { file: 'tree_pine.glb',  height: 12, fallback: 'pine', tint: 0x7f8f7a },
  tree_leaf:  { file: 'tree_leaf.glb',  height: 11, fallback: 'leaf', tint: 0x8a9a80 },
  tree_dead:  { file: 'tree_dead.glb',  height: 8,  fallback: 'dead' },
  bush:       { file: 'bush.glb',       height: 2.2, fallback: 'bush', tint: 0x66785e },
  rock:       { file: 'rock.glb',       height: 1.1, fallback: 'rock' },
  stump:      { file: 'stump.glb',      height: 0.6, fallback: 'stump' },
  woodpile:   { file: 'woodpile.glb',   height: 1.2, fallback: 'woodpile' },
  barricade:  { file: 'barricade.glb',  height: 1.4, fallback: 'barricade' },
  bench:      { file: 'bench.glb',      height: 0.9, fallback: 'bench' },
  pistol:     { file: 'pistol.glb',     height: 0.14, fallback: 'pistol' },
  rifle:      { file: 'rifle.glb',      height: 0.2,  fallback: 'rifle' },
  zombie_shambler: { file: 'zombie_shambler.glb', height: 1.8, animated: true, fallback: 'zombie' },
  zombie_runner:   { file: 'zombie_runner.glb',   height: 1.7, animated: true, fallback: 'zombie' },
};

const loader = new GLTFLoader();

// Models ship as { b64 } JSON because the hosting only serves standard web media types.
async function loadGlbJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  const { b64 } = await res.json();
  const bin = atob(b64); const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return new Promise((resolve, reject) => loader.parse(buf.buffer, '', resolve, reject));
}
const cache = {};
export const loaded = {}; // name -> true if a real GLB was loaded

function normalize(obj, height) {
  const box = new THREE.Box3().setFromObject(obj);
  const size = new THREE.Vector3(); box.getSize(size);
  const s = height / (size.y || 1);
  obj.scale.multiplyScalar(s);
  box.setFromObject(obj);
  const c = new THREE.Vector3(); box.getCenter(c);
  obj.position.x -= c.x; obj.position.z -= c.z; obj.position.y -= box.min.y;
  const g = new THREE.Group(); g.add(obj);
  return g;
}

function prepMaterials(root, tint) {
  root.traverse(o => {
    if (o.isMesh) {
      o.castShadow = true; o.receiveShadow = true;
      o.frustumCulled = false;
      if (o.material?.map) o.material.map.anisotropy = 4;
      if (tint && o.material?.color) o.material.color.multiply(new THREE.Color(tint));
    }
  });
}

function findClip(anims, key) {
  const k = key.toLowerCase();
  return anims.find(a => a.name.toLowerCase() === k) || anims.find(a => a.name.toLowerCase().includes(k)) || null;
}

export async function loadAll(onProgress) {
  const names = Object.keys(MANIFEST);
  let done = 0;
  await Promise.all(names.map(async name => {
    const m = MANIFEST[name];
    try {
      const gltf = await loadGlbJson(`${import.meta.env.BASE_URL}models/${m.file}.json`);
      prepMaterials(gltf.scene, m.tint);
      cache[name] = { scene: normalize(gltf.scene, m.height), animations: gltf.animations || [] };
      loaded[name] = true;
    } catch {
      cache[name] = { scene: m.animated ? null : fallbacks[m.fallback](m.height), animations: [] };
      loaded[name] = false;
    }
    onProgress?.(++done, names.length);
  }));
}

// Returns a fresh instance. Animated models get a SkeletonUtils clone with a mixer and named actions.
export function instance(name) {
  const entry = cache[name];
  const m = MANIFEST[name];
  if (m.animated && loaded[name] && entry.animations.length) {
    const obj = skeletonClone(entry.scene);
    const mixer = new THREE.AnimationMixer(obj);
    const actions = {};
    for (const key of ['walk', 'attack', 'death']) {
      const clip = findClip(entry.animations, key) || entry.animations[0];
      actions[key] = mixer.clipAction(clip);
    }
    return { obj, mixer, actions, real: true };
  }
  if (m.animated) return fallbackZombie(m.height);
  return { obj: entry.scene.clone(), real: loaded[name] };
}

// ---------- primitive fallbacks ----------
const mat = (color, extra = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.9, ...extra });
function shadow(o) { o.castShadow = true; o.receiveShadow = true; return o; }

const fallbacks = {
  pine(h) {
    const g = new THREE.Group();
    const trunk = shadow(new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.35, h * 0.4, 7), mat(0x4a3323)));
    trunk.position.y = h * 0.2; g.add(trunk);
    for (let i = 0; i < 4; i++) {
      const r = (1 - i * 0.2) * h * 0.22, y = h * 0.3 + i * h * 0.17;
      const c = shadow(new THREE.Mesh(new THREE.ConeGeometry(r, h * 0.28, 8), mat(0x173a1f)));
      c.position.y = y; g.add(c);
    }
    return g;
  },
  leaf(h) {
    const g = new THREE.Group();
    const trunk = shadow(new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.4, h * 0.45, 7), mat(0x5a4a3a)));
    trunk.position.y = h * 0.225; g.add(trunk);
    for (let i = 0; i < 4; i++) {
      const s = shadow(new THREE.Mesh(new THREE.IcosahedronGeometry(h * 0.26, 1), mat(0x1f4a22, { flatShading: true })));
      s.position.set((Math.random() - .5) * h * 0.25, h * 0.6 + (Math.random() - .5) * h * 0.2, (Math.random() - .5) * h * 0.25);
      g.add(s);
    }
    return g;
  },
  dead(h) {
    const g = new THREE.Group();
    const trunk = shadow(new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.3, h, 6), mat(0x4d4a45)));
    trunk.position.y = h / 2; g.add(trunk);
    for (let i = 0; i < 4; i++) {
      const b = shadow(new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.12, h * 0.4, 5), mat(0x4d4a45)));
      b.position.y = h * 0.6 + i * h * 0.08; b.rotation.z = (i % 2 ? 1 : -1) * 0.8; b.rotation.y = i * 1.5;
      b.position.x = Math.cos(i * 1.5) * 0.3; b.position.z = Math.sin(i * 1.5) * 0.3;
      g.add(b);
    }
    return g;
  },
  bush(h) {
    const g = new THREE.Group();
    for (let i = 0; i < 3; i++) {
      const s = shadow(new THREE.Mesh(new THREE.IcosahedronGeometry(h * 0.45, 1), mat(0x1d4020, { flatShading: true })));
      s.position.set((Math.random() - .5) * h * 0.5, h * 0.4, (Math.random() - .5) * h * 0.5); g.add(s);
    }
    return g;
  },
  rock(h) { const m = shadow(new THREE.Mesh(new THREE.DodecahedronGeometry(h * 0.6, 0), mat(0x6b6b66, { flatShading: true }))); m.position.y = h * 0.4; const g = new THREE.Group(); g.add(m); return g; },
  stump(h) { const m = shadow(new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.5, h, 8), mat(0x6b4d33))); m.position.y = h / 2; const g = new THREE.Group(); g.add(m); return g; },
  woodpile(h) { const m = shadow(new THREE.Mesh(new THREE.BoxGeometry(2.2, h, 1), mat(0x7a5a3a))); m.position.y = h / 2; const g = new THREE.Group(); g.add(m); return g; },
  barricade(h) {
    const g = new THREE.Group();
    for (let i = 0; i < 4; i++) {
      const p = shadow(new THREE.Mesh(new THREE.BoxGeometry(3.2, 0.22, 0.08), mat(0x6e5236)));
      p.position.y = 0.3 + i * 0.32; p.rotation.z = (i % 2 ? 0.12 : -0.12); g.add(p);
    }
    const post = shadow(new THREE.Mesh(new THREE.BoxGeometry(0.15, h, 0.15), mat(0x5a4028)));
    post.position.set(-1.4, h / 2, 0); g.add(post); const post2 = post.clone(); post2.position.x = 1.4; g.add(post2);
    return g;
  },
  bench() {
    const g = new THREE.Group();
    const seat = shadow(new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.06, 0.45), mat(0x2f7a3a))); seat.position.y = 0.45; g.add(seat);
    const back = shadow(new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.4, 0.05), mat(0x2f7a3a))); back.position.set(0, 0.7, -0.2); back.rotation.x = -0.15; g.add(back);
    for (const x of [-0.75, 0.75]) { const l = shadow(new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.45, 0.4), mat(0x222222))); l.position.set(x, 0.22, 0); g.add(l); }
    return g;
  },
  pistol() {
    const g = new THREE.Group();
    const slide = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.05, 0.2), mat(0x1c1c1e, { roughness: 0.5, metalness: 0.6 })); slide.position.set(0, 0.03, -0.05); g.add(slide);
    const grip = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.1, 0.05), mat(0x2a2a2c)); grip.position.set(0, -0.045, 0.03); grip.rotation.x = 0.25; g.add(grip);
    return g;
  },
  rifle() {
    const g = new THREE.Group();
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.55, 8), mat(0x222222, { roughness: 0.4, metalness: 0.7 })); barrel.rotation.x = Math.PI / 2; barrel.position.set(0, 0.03, -0.25); g.add(barrel);
    const pump = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.16, 8), mat(0x5a3d25)); pump.rotation.x = Math.PI / 2; pump.position.set(0, 0.0, -0.22); g.add(pump);
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.07, 0.25), mat(0x2a2a2c)); body.position.set(0, 0.01, 0.02); g.add(body);
    const stock = new THREE.Mesh(new THREE.BoxGeometry(0.045, 0.08, 0.25), mat(0x5a3d25)); stock.position.set(0, -0.02, 0.25); g.add(stock);
    return g;
  },
};

// Blocky procedurally-animated fallback zombie (used until the Meshy GLB exists)
function fallbackZombie(h) {
  const g = new THREE.Group();
  const skin = mat(0x6f8a5a), cloth = mat(0x3a3f4a);
  const torso = shadow(new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.65, 0.28), cloth)); torso.position.y = 1.15; g.add(torso);
  const head = shadow(new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.32, 0.3), skin)); head.position.y = 1.65; g.add(head);
  const parts = { arms: [], legs: [] };
  for (const s of [-1, 1]) {
    const arm = shadow(new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.6, 0.14), skin)); arm.geometry.translate(0, -0.3, 0); arm.position.set(s * 0.33, 1.45, 0); g.add(arm); parts.arms.push(arm);
    const leg = shadow(new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.8, 0.18), cloth)); leg.geometry.translate(0, -0.4, 0); leg.position.set(s * 0.14, 0.82, 0); g.add(leg); parts.legs.push(leg);
  }
  const inner = new THREE.Group(); inner.add(g); g.scale.setScalar(h / 1.8);
  let t = 0, state = 'walk', deathT = 0;
  const mixer = {
    update(dt) {
      t += dt;
      if (state === 'walk') {
        parts.legs[0].rotation.x = Math.sin(t * 6) * 0.6; parts.legs[1].rotation.x = -Math.sin(t * 6) * 0.6;
        parts.arms[0].rotation.x = -1.4 + Math.sin(t * 3) * 0.15; parts.arms[1].rotation.x = -1.4 - Math.sin(t * 3) * 0.15;
      } else if (state === 'attack') {
        const p = Math.sin(t * 10); parts.arms[0].rotation.x = -1.2 + p * 0.6; parts.arms[1].rotation.x = -1.2 - p * 0.6;
      } else if (state === 'death') {
        deathT = Math.min(1, deathT + dt * 1.6); g.rotation.x = -deathT * Math.PI / 2; g.position.y = deathT * 0.15;
      }
    },
    stopAllAction() {},
  };
  const actions = {};
  for (const k of ['walk', 'attack', 'death']) actions[k] = { play() { state = k; return this; }, reset() { return this; }, stop() { return this; }, setLoop() { return this; }, fadeIn() { return this; }, fadeOut() { return this; }, clampWhenFinished: true, timeScale: 1, enabled: true, isRunning: () => state === k };
  return { obj: inner, mixer, actions, real: false };
}
