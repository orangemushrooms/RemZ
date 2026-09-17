import * as THREE from 'three';
import { instance, loaded } from './assets.js';
import { hud } from './hud.js';
import { audio } from './audio.js';

const DEFS = {
  pistol:  { name: 'Pistole', model: 'pistol', mag: 12, reserve: 72, damage: 34, rate: 0.22, reload: 1.1, pellets: 1, spread: 0.012, range: 60, auto: false, kick: 0.05, snd: 'pistol', pos: [0.24, -0.22, -0.5], rot: [0, 0, 0], glbRot: [0, -Math.PI / 2, 0] },
  shotgun: { name: 'Schrotflinte', model: 'rifle', mag: 6, reserve: 24, damage: 22, rate: 0.85, reload: 2.0, pellets: 8, spread: 0.07, range: 28, auto: false, kick: 0.16, snd: 'shotgun', pos: [0.22, -0.24, -0.55], rot: [0, 0, 0], glbRot: [0, -Math.PI / 2, 0] },
};

export class Weapons {
  constructor(camera, scene, player, zombies, world) {
    this.camera = camera; this.scene = scene; this.player = player; this.zombies = zombies; this.world = world;
    this.state = {};
    for (const [id, d] of Object.entries(DEFS)) {
      const { obj } = instance(d.model);
      obj.traverse(o => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; o.frustumCulled = false; } });
      // Meshy models come in side view; turn the barrel to face forward (-Z)
      if (loaded[d.model] && d.glbRot) { const inner = new THREE.Group(); inner.add(obj.children[0]); inner.rotation.set(...d.glbRot); obj.add(inner); }
      obj.visible = false; camera.add(obj);
      this.state[id] = { def: d, ammo: d.mag, reserve: d.reserve, obj, cooldown: 0, reloading: 0 };
    }
    this.current = 'pistol'; this.unlocked = { pistol: true, shotgun: false };
    this.recoil = 0; this.swayT = 0; this.mouseDown = false;
    this.raycaster = new THREE.Raycaster();
    // muzzle flash
    this.flash = new THREE.PointLight(0xffc070, 0, 12, 2); this.flash.position.set(0.2, -0.15, -0.8); camera.add(this.flash);
    this.flashMesh = new THREE.Mesh(new THREE.SphereGeometry(0.02, 6, 6), new THREE.MeshBasicMaterial({ color: 0xfff0b0 })); this.flashMesh.visible = false; this.flashMesh.position.set(0.22, -0.16, -0.75); camera.add(this.flashMesh);
    this.tracers = [];
    this.setWeapon('pistol');
    const doc = document;
    doc.addEventListener('mousedown', e => { if (e.button === 0) { this.mouseDown = true; this.tryFire(); } });
    doc.addEventListener('mouseup', e => { if (e.button === 0) this.mouseDown = false; });
    doc.addEventListener('keydown', e => {
      if (e.code === 'KeyR') this.reload();
      if (e.code === 'Digit1') this.setWeapon('pistol');
      if (e.code === 'Digit2') this.setWeapon('shotgun');
      if (e.code === 'KeyQ') this.setWeapon(this.current === 'pistol' ? 'shotgun' : 'pistol');
    });
  }

  get cur() { return this.state[this.current]; }

  setWeapon(id) {
    if (!this.unlocked[id]) { hud.message('Schrotflinte ab Welle 3', 1200); return; }
    for (const s of Object.values(this.state)) s.obj.visible = false;
    this.current = id; this.cur.obj.visible = true; this.cur.reloading = 0;
    this.updateHud();
  }

  unlock(id) { this.unlocked[id] = true; }

  updateHud() { hud.ammo(this.cur.ammo, this.cur.reserve, this.cur.def.name); }

  addAmmo(id, n) { this.state[id].reserve += n; this.updateHud(); }

  reload() {
    const s = this.cur; if (s.reloading > 0 || s.ammo === s.def.mag || s.reserve <= 0) return;
    s.reloading = s.def.reload; audio.reload();
  }

  tryFire() {
    if (!this.player.controls.isLocked || !this.player.alive) return;
    const s = this.cur; if (s.cooldown > 0 || s.reloading > 0) return;
    if (s.ammo <= 0) { audio.empty(); this.reload(); return; }
    s.ammo--; s.cooldown = s.def.rate; this.recoil = 1; audio[s.def.snd]();
    this.flash.intensity = 30; this.flashMesh.visible = true;
    const origin = this.camera.getWorldPosition(new THREE.Vector3());
    const base = this.camera.getWorldDirection(new THREE.Vector3());
    for (let i = 0; i < s.def.pellets; i++) {
      const dir = base.clone();
      dir.x += (Math.random() - 0.5) * s.def.spread * 2; dir.y += (Math.random() - 0.5) * s.def.spread * 2; dir.z += (Math.random() - 0.5) * s.def.spread * 2; dir.normalize();
      this.raycaster.set(origin, dir); this.raycaster.far = s.def.range;
      const hit = this.zombies.raycast(this.raycaster);
      if (hit) {
        const head = hit.point.y > hit.zombie.obj.position.y + hit.zombie.height * 0.78;
        hit.zombie.damage(s.def.damage * (head ? 2.2 : 1), dir, head);
        this.zombies.blood(hit.point, dir);
      }
      this.tracer(origin, hit ? hit.point : origin.clone().addScaledVector(dir, s.def.range));
    }
    this.updateHud();
  }

  tracer(a, b) {
    const g = new THREE.BufferGeometry().setFromPoints([a.clone().add(new THREE.Vector3(0.15, -0.12, 0)), b]);
    const l = new THREE.Line(g, new THREE.LineBasicMaterial({ color: 0xffd9a0, transparent: true, opacity: 0.6 }));
    this.scene.add(l); this.tracers.push({ l, t: 0.06 });
  }

  update(dt) {
    const s = this.cur;
    s.cooldown = Math.max(0, s.cooldown - dt);
    if (s.reloading > 0) { s.reloading -= dt; if (s.reloading <= 0) { const need = s.def.mag - s.ammo, take = Math.min(need, s.reserve); s.ammo += take; s.reserve -= take; s.reloading = 0; this.updateHud(); } }
    if (this.mouseDown && s.def.auto) this.tryFire();
    this.recoil = Math.max(0, this.recoil - dt * 7);
    this.swayT += dt;
    const o = s.obj, d = s.def;
    const moving = Math.hypot(this.player.vel.x, this.player.vel.z) > 0.5;
    o.position.set(d.pos[0] + Math.sin(this.swayT * 5) * (moving ? 0.008 : 0.002), d.pos[1] + Math.abs(Math.sin(this.swayT * 5)) * (moving ? 0.01 : 0.003) + (s.reloading > 0 ? -0.12 : 0), d.pos[2] + this.recoil * d.kick);
    o.rotation.set(d.rot[0] - this.recoil * 0.35 + (s.reloading > 0 ? -0.4 : 0), d.rot[1], d.rot[2]);
    this.flash.intensity *= 0.6; if (this.flash.intensity < 0.5) { this.flash.intensity = 0; this.flashMesh.visible = false; }
    for (const t of this.tracers) { t.t -= dt; if (t.t <= 0) { this.scene.remove(t.l); t.l.geometry.dispose(); } }
    this.tracers = this.tracers.filter(t => t.t > 0);
  }
}
