// The Birkenhof map, rebuilt from the Street View photos. +X = east, +Z = south (downhill).
//
//  z = -95 ... -60  north forest, the gravel track "Birkenhof" runs NW along its edge
//  z = -58 ... -38  asphalt parking bay with concrete curb; grass strip with 3 green benches + bin
//                   on its east side in front of the dense forest
//  z = -38 ... +40  single-lane asphalt road climbing, hazel hedge + forest edge on the east,
//                   mown meadow with valley view on the west
//  z = +40 ... +120 lower road: open field on both sides near the road, forest further east,
//                   scrub on the west, farmhouse at the bottom
import * as THREE from 'three';
import { instance } from './assets.js';
import { loadTexture } from './textures.js';

export const MAP = {
  roadWidth: 3.6,
  bay: { x0: -7.5, x1: 7.5, z0: -58, z1: -38 },     // asphalt parking bay
  strip: { x0: 7.5, x1: 13.5, z0: -60, z1: -40 },   // grass strip with the benches
  roadStart: -38, roadEnd: 120,
  bounds: { minX: -70, maxX: 55, minZ: -95, maxZ: 128 },
  // Barricade slots: center, yaw, number of 3.2 m segments
  barricades: [
    { id: 'south', name: 'Weg (Süd)', pos: [0.2, -30], yaw: 0, segments: 2 },
    { id: 'east',  name: 'Waldrand (Ost)', pos: [13.8, -50], yaw: Math.PI / 2, segments: 2 },
    { id: 'north', name: 'Kiesweg (Nord)', pos: [-9.5, -63], yaw: 0.35, segments: 2 },
  ],
  spawns: {
    south: [[0, 30], [1, 45], [-1, 60], [1, 75]],
    east:  [[30, -52], [34, -44], [28, -36], [36, -50]],
    north: [[-14, -88], [-11, -92], [-17, -85], [-9, -90]],
  },
};

// road centre line: gentle S-curve, bending slightly west near the top like in the photos
export function roadX(z) { return 1.6 * Math.sin(z / 40) + 0.5 * Math.sin(z / 13) - (z < -20 ? (-20 - z) * 0.03 : 0); }
// gravel track centre line, leaving the bay's NW corner and following the forest edge north
export function trackX(z) { return -9 + (-58 - z) * 0.18; }

export function groundHeight(x, z) {
  const zz = Math.max(z, MAP.roadStart);
  let h = -(zz - MAP.roadStart) * 0.085;
  if (z > 95) h -= (z - 95) * 0.03;
  if (z < -60) h += (-60 - z) * 0.02;           // the track climbs a little into the forest
  const dx = x - roadX(z);
  // keep the bay and its surroundings flat, fade the side terrain in smoothly
  const inBay = z < -34 && x > -12 && x < 16;
  const flat = inBay ? 0 : Math.min(1, Math.max(0, (Math.min(z + 34, 30)) / 10));
  if (dx < -2) { const k = -dx - 2, f = Math.min(1, k / 8); h -= flat * (k * 0.06 + f * (Math.sin(x * 0.11) * 0.4 + Math.sin(z * 0.07 + x * 0.05) * 0.5)); }
  if (dx > 2) { const k = dx - 2, f = Math.min(1, k / 8); h += flat * (k * 0.03 + f * Math.sin(x * 0.19 + z * 0.13) * 0.25); }
  return h;
}

export class World {
  constructor(scene) {
    this.scene = scene;
    this.colliders = []; // {x,z,r}
    this.torches = [];
    this.barricades = []; // filled by Barricades system
  }

  async build() {
    const s = this.scene;
    const [grass, asphalt, gravel] = await Promise.all([loadTexture('grass', 70), loadTexture('asphalt', 1), loadTexture('gravel', 1)]);

    // ---- terrain ----
    const W = 320, seg = 220;
    const geo = new THREE.PlaneGeometry(W, W, seg, seg);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) pos.setY(i, groundHeight(pos.getX(i), pos.getZ(i)));
    geo.computeVertexNormals();
    const terrain = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: grass, roughness: 1, color: 0xb9c4a8 }));
    terrain.receiveShadow = true; s.add(terrain);

    const flat = (x, z) => groundHeight(x, z) + 0.04;
    const asphaltMat = new THREE.MeshStandardMaterial({ map: asphalt, roughness: 0.95 });
    const gravelMat = new THREE.MeshStandardMaterial({ map: gravel, roughness: 1 });
    const rw = MAP.roadWidth / 2;

    // ---- the road ----
    const roadPts = []; for (let z = MAP.roadStart - 1; z <= MAP.roadEnd; z += 2) roadPts.push(z);
    const road = new THREE.Mesh(ribbon(roadPts, z => [roadX(z) - rw, roadX(z) + rw], flat, 0.45), asphaltMat);
    road.receiveShadow = true; s.add(road);
    // gravel shoulder on the west side just below the bay (photo 4)
    const shPts = []; for (let z = -38; z <= -24; z += 2) shPts.push(z);
    const shoulder = new THREE.Mesh(ribbon(shPts, z => [roadX(z) - rw - 3.5, roadX(z) - rw + 0.2], (x, z) => groundHeight(x, z) + 0.03, 0.3), gravelMat);
    shoulder.receiveShadow = true; s.add(shoulder);

    // ---- asphalt parking bay with a concrete curb ----
    const B = MAP.bay;
    const bayGeo = new THREE.PlaneGeometry(B.x1 - B.x0, B.z1 - B.z0, 12, 16); bayGeo.rotateX(-Math.PI / 2);
    const bp = bayGeo.attributes.position; const bcx = (B.x0 + B.x1) / 2, bcz = (B.z0 + B.z1) / 2;
    for (let i = 0; i < bp.count; i++) bp.setY(i, flat(bp.getX(i) + bcx, bp.getZ(i) + bcz) + 0.01);
    const bay = new THREE.Mesh(bayGeo, asphaltMat); bay.position.set(bcx, 0, bcz); bay.receiveShadow = true; s.add(bay);
    const curbMat = new THREE.MeshStandardMaterial({ color: 0x9a9a92, roughness: 0.9 });
    const curb = (x, z, len, yaw) => { const c = new THREE.Mesh(new THREE.BoxGeometry(len, 0.14, 0.25), curbMat); c.position.set(x, groundHeight(x, z) + 0.07, z); c.rotation.y = yaw; c.castShadow = c.receiveShadow = true; s.add(c); };
    curb(B.x1, bcz, B.z1 - B.z0, Math.PI / 2);                 // east curb along the grass strip
    curb(bcx, B.z0, B.x1 - B.x0, 0);                           // north curb
    curb(B.x0, (B.z0 + B.z1 + 6) / 2, B.z1 - B.z0 - 6, Math.PI / 2); // west curb (gap at the NW corner for the gravel track)

    // ---- gravel track NW along the forest edge ----
    const trPts = []; for (let z = -50; z >= -95; z -= 2) trPts.push(z);
    const track = new THREE.Mesh(ribbon(trPts, z => [trackX(z) - 1.5, trackX(z) + 1.5], flat, 0.4), gravelMat);
    track.receiveShadow = true; s.add(track);

    // ---- vegetation ----
    const rnd = mulberry32(4242);
    const place = (name, x, z, { scale = 1, yaw = rnd() * Math.PI * 2, collide = 0 } = {}) => {
      const { obj } = instance(name);
      obj.position.set(x, groundHeight(x, z) - 0.05, z);
      obj.rotation.y = yaw; obj.scale.setScalar(scale);
      s.add(obj);
      if (collide) this.colliders.push({ x, z, r: collide * scale });
      return obj;
    };
    const clearZone = (x, z) =>
      (z > MAP.roadStart - 3 && Math.abs(x - roadX(z)) < rw + 2.2) ||               // road corridor
      (x > B.x0 - 2 && x < MAP.strip.x1 + 1 && z > B.z0 - 3 && z < B.z1 + 3) ||     // bay + bench strip
      (z < -46 && Math.abs(x - trackX(z)) < 3.2) ||                                  // gravel track
      (x > 13 && x < 40 && Math.abs(z - (-50 + (x - 13) * 0.2)) < 2.6);              // east approach through the forest
    const tree = (x, z, big = false) => {
      if (clearZone(x, z)) return;
      const r = rnd();
      const kind = r < 0.6 ? 'tree_leaf' : r < 0.9 ? 'tree_pine' : 'tree_dead';
      place(kind, x, z, { scale: (big ? 1.0 : 0.75) + rnd() * 0.6, collide: 0.5 });
    };

    // east forest. Its edge hugs the road in the upper half and pulls away in the lower half.
    const forestEdge = z => roadX(z) + rw + (z < 40 ? 3.5 : 3.5 + (z - 40) * 0.5);
    for (let i = 0; i < 300; i++) {
      const z = -60 + rnd() * 175;
      const x = forestEdge(z) + rnd() * rnd() * 50;
      tree(x, z, z < -30);
    }
    // dense forest wrapping the bay: north wall and the block east of the bench strip
    for (let i = 0; i < 160; i++) { const x = -30 + rnd() * 80; const z = -62 - rnd() * 35; tree(x, z, true); }
    for (let i = 0; i < 60; i++) { const x = MAP.strip.x1 + 1.5 + rnd() * 25; const z = -62 + rnd() * 26; tree(x, z, true); }
    // forest east of the gravel track (the track runs along its edge)
    for (let i = 0; i < 80; i++) { const z = -60 - rnd() * 35; const x = trackX(z) + 4 + rnd() * 30; tree(x, z, true); }
    // hazel hedge along the east edge of the road in the upper part (photos 3, 4, 7, 8)
    for (let z = -37; z < 42; z += 1.8 + rnd() * 1.0) { const x = roadX(z) + rw + 1.9 + rnd() * 0.6; if (!clearZone(x, z) || z > -34) place('bush', x, z, { scale: 0.7 + rnd() * 0.5, collide: 0.9 }); }
    // undergrowth in front of the forest around the bay
    for (let i = 0; i < 26; i++) { const x = MAP.strip.x1 + 0.5 + rnd() * 3; const z = -62 + rnd() * 26; if (!clearZone(x, z)) place('bush', x, z, { scale: 0.8 + rnd() * 0.8, collide: 0.8 }); }
    for (let i = 0; i < 22; i++) { const x = -12 + rnd() * 28; const z = -61 - rnd() * 3; if (!clearZone(x, z)) place('bush', x, z, { scale: 0.8 + rnd() * 0.8, collide: 0.8 }); }
    // scrub and a few trees on the west side of the lower road (return photo 4)
    for (let i = 0; i < 45; i++) { const z = 55 + rnd() * 65; const x = roadX(z) - rw - 1.5 - rnd() * 7; place('bush', x, z, { scale: 0.6 + rnd() * 0.9, collide: 0.7 }); }
    for (let i = 0; i < 14; i++) { const z = 60 + rnd() * 60; const x = roadX(z) - rw - 4 - rnd() * 8; tree(x, z); }
    // distant tree lines: far side of the meadow (west) and the bottom of the hill
    for (let i = 0; i < 90; i++) tree(-100 + rnd() * 25, -80 + rnd() * 200, true);
    for (let i = 0; i < 40; i++) tree(-30 + rnd() * 60, 118 + rnd() * 20, true);

    // ---- props ----
    // the three green benches on the grass strip, facing the bay, and the bin beside the last one (photos 5, 6)
    for (const [x, z] of [[10.5, -57], [10.5, -50], [10.5, -43]]) place('bench', x, z, { yaw: -Math.PI / 2, collide: 0.8 });
    const bin = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.2, 0.75, 10), new THREE.MeshStandardMaterial({ color: 0x2e6b35, roughness: 0.8 }));
    bin.position.set(10.5, groundHeight(10.5, -41) + 0.38, -41); bin.castShadow = true; s.add(bin);
    place('woodpile', -5, -61, { yaw: 0.2, collide: 1.2 });
    place('stump', 15.5, -46, { collide: 0.5 }); place('stump', -14, -70, { collide: 0.5 });
    for (let i = 0; i < 10; i++) { const x = -25 + rnd() * 50, z = -75 + rnd() * 20; if (!clearZone(x, z)) place('rock', x, z, { scale: 0.5 + rnd(), collide: 0.6 }); }
    // farmhouse at the bottom of the road (return photo 4), slightly west of the road
    const house = new THREE.Group();
    const wall = new THREE.Mesh(new THREE.BoxGeometry(11, 5, 8), new THREE.MeshStandardMaterial({ color: 0xd9d2c3, roughness: 1 })); wall.position.y = 2.5; wall.castShadow = wall.receiveShadow = true; house.add(wall);
    const roof = new THREE.Mesh(new THREE.ConeGeometry(8, 3.4, 4), new THREE.MeshStandardMaterial({ color: 0x5a3328, roughness: 1 })); roof.rotation.y = Math.PI / 4; roof.position.y = 6.7; roof.castShadow = true; house.add(roof);
    const win = new THREE.Mesh(new THREE.PlaneGeometry(1, 1.2), new THREE.MeshBasicMaterial({ color: 0xffd28a })); win.position.set(0, 2.6, 4.01); house.add(win);
    const hx = roadX(116) - 10, hz = 116;
    house.position.set(hx, groundHeight(hx, hz), hz); house.rotation.y = 0.2; s.add(house);
    this.colliders.push({ x: hx, z: hz, r: 7 });
    // the small blue signpost on the meadow side near the top (return photo 2)
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 1.6, 6), new THREE.MeshStandardMaterial({ color: 0x9a9a9a }));
    const px = roadX(-18) - rw - 1.6; post.position.set(px, groundHeight(px, -18) + 0.8, -18); s.add(post);
    const sign = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.28, 0.02), new THREE.MeshStandardMaterial({ color: 0x1d4fa8 })); sign.position.set(0, 0.7, 0); post.add(sign);
    // a white road marker at the bottom junction (return photo 4)
    const marker = new THREE.Mesh(new THREE.BoxGeometry(0.12, 1.1, 0.12), new THREE.MeshStandardMaterial({ color: 0xeeeeee }));
    const mx = roadX(100) - rw - 0.6; marker.position.set(mx, groundHeight(mx, 100) + 0.55, 100); s.add(marker);

    // ---- sky, fog, light ----
    s.background = new THREE.Color(0x04060a);
    s.fog = new THREE.FogExp2(0x070a10, 0.024);
    s.add(new THREE.HemisphereLight(0x2a3a55, 0x0c0a08, 0.7));
    const moon = new THREE.DirectionalLight(0x8fa3c9, 0.8);
    moon.position.set(-60, 80, -30); moon.castShadow = true;
    moon.shadow.mapSize.set(2048, 2048);
    Object.assign(moon.shadow.camera, { left: -45, right: 45, top: 45, bottom: -45, near: 10, far: 220 });
    moon.shadow.bias = -0.0015;
    moon.target.position.set(0, 0, -40); s.add(moon); s.add(moon.target);
    this.moon = moon;

    // torches at the bay
    for (const [x, z] of [[-6, -36], [6, -36], [-6, -56]]) this.addTorch(x, z);

    // ---- night sky: stars, moon, village lights in the valley to the west ----
    const starGeo = new THREE.BufferGeometry(); const sp = [];
    for (let i = 0; i < 900; i++) { const a = rnd() * Math.PI * 2, e = Math.asin(rnd() * 0.95 + 0.05); const r = 230; sp.push(Math.cos(a) * Math.cos(e) * r, Math.sin(e) * r, Math.sin(a) * Math.cos(e) * r); }
    starGeo.setAttribute('position', new THREE.Float32BufferAttribute(sp, 3));
    const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({ color: 0xcfd8ff, size: 1.6, sizeAttenuation: false, fog: false, transparent: true, opacity: 0.8 }));
    stars.frustumCulled = false; this.stars = stars; s.add(stars);
    const moonMesh = new THREE.Mesh(new THREE.SphereGeometry(6, 16, 16), new THREE.MeshBasicMaterial({ color: 0xe8ecff, fog: false }));
    moonMesh.position.copy(moon.position).normalize().multiplyScalar(225); s.add(moonMesh);
    const glow = new THREE.Mesh(new THREE.SphereGeometry(16, 16, 16), new THREE.MeshBasicMaterial({ color: 0x8fa3c9, fog: false, transparent: true, opacity: 0.12 }));
    glow.position.copy(moonMesh.position); s.add(glow);
    for (let i = 0; i < 40; i++) { const l = new THREE.Mesh(new THREE.SphereGeometry(0.35, 4, 4), new THREE.MeshBasicMaterial({ color: rnd() < 0.7 ? 0xffd28a : 0xfff4dc, fog: false })); l.position.set(-150 - rnd() * 60, -18 + rnd() * 3, -80 + rnd() * 200); s.add(l); }
  }

  addTorch(x, z) {
    const y = groundHeight(x, z);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.05, 1.6, 6), new THREE.MeshStandardMaterial({ color: 0x3a2a1a }));
    pole.position.set(x, y + 0.8, z); this.scene.add(pole);
    const flame = new THREE.Mesh(new THREE.SphereGeometry(0.12, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffa040 }));
    flame.position.set(x, y + 1.7, z); this.scene.add(flame);
    const light = new THREE.PointLight(0xff8c3a, 12, 18, 1.6); light.position.copy(flame.position); this.scene.add(light);
    this.torches.push({ light, flame, base: 12, seed: Math.random() * 10 });
    this.colliders.push({ x, z, r: 0.3 });
  }

  update(t, playerPos) {
    if (playerPos && this.stars) this.stars.position.set(playerPos.x, 0, playerPos.z);
    for (const tc of this.torches) {
      const f = 0.75 + 0.25 * Math.sin(t * 11 + tc.seed) * Math.sin(t * 7.3 + tc.seed * 2) + 0.1 * Math.sin(t * 23 + tc.seed);
      tc.light.intensity = tc.base * f; tc.flame.scale.setScalar(0.8 + f * 0.3);
    }
  }

  // push a position out of tree/prop colliders and clamp to bounds. radius = agent radius.
  resolve(p, radius = 0.45) {
    for (const c of this.colliders) {
      const dx = p.x - c.x, dz = p.z - c.z, d = Math.hypot(dx, dz), min = c.r + radius;
      if (d < min && d > 1e-4) { p.x = c.x + dx / d * min; p.z = c.z + dz / d * min; }
    }
    for (const b of this.barricades) if (b.hp > 0) b.pushOut(p, radius);
    const B = MAP.bounds;
    p.x = Math.min(B.maxX, Math.max(B.minX, p.x)); p.z = Math.min(B.maxZ, Math.max(B.minZ, p.z));
  }
}

function ribbon(zs, edges, height, vScale) {
  const verts = [], uvs = [], idx = [];
  zs.forEach((z, i) => {
    const [x0, x1] = edges(z);
    verts.push(x0, height(x0, z), z, x1, height(x1, z), z);
    uvs.push(0, i * vScale, 1, i * vScale);
    if (i > 0) { const a = (i - 1) * 2; idx.push(a, a + 2, a + 1, a + 1, a + 2, a + 3); }
  });
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  g.setIndex(idx); g.computeVertexNormals();
  return g;
}

function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
