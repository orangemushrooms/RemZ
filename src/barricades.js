import * as THREE from 'three';
import { instance } from './assets.js';
import { groundHeight, MAP } from './world.js';
import { hud } from './hud.js';
import { audio } from './audio.js';

const COST_BUILD = 50, COST_REPAIR = 25, MAX_LEVEL = 3;

class Barricade {
  constructor(slot, scene) {
    this.slot = slot; this.scene = scene; this.level = 0; this.hp = 0;
    this.center = new THREE.Vector3(slot.pos[0], groundHeight(slot.pos[0], slot.pos[1]), slot.pos[1]);
    this.yaw = slot.yaw; this.halfLen = slot.segments * 1.6; this.group = new THREE.Group();
    this.group.position.copy(this.center); this.group.rotation.y = this.yaw; scene.add(this.group);
    this.dir = new THREE.Vector3(Math.cos(this.yaw), 0, -Math.sin(this.yaw)); // along the wall
    this.normal = new THREE.Vector3(Math.sin(this.yaw), 0, Math.cos(this.yaw)); // across the wall
    this.rebuild();
  }
  get maxHp() { return this.level * 150; }
  rebuild() {
    this.group.clear();
    for (let i = 0; i < this.slot.segments; i++) {
      for (let l = 0; l < this.level; l++) {
        const { obj } = instance('barricade');
        obj.position.set((i - (this.slot.segments - 1) / 2) * 3.2, 0, l * 0.35 - 0.35);
        obj.scale.y = 0.85 + l * 0.15; obj.rotation.y = (l % 2 ? 0.06 : -0.06);
        this.group.add(obj);
      }
    }
    // damaged: tilt planks
    const f = this.maxHp ? this.hp / this.maxHp : 0;
    this.group.rotation.z = (1 - f) * 0.12;
  }
  build() { if (this.level >= MAX_LEVEL) return false; this.level++; this.hp = this.maxHp; this.rebuild(); return true; }
  repair() { if (this.level === 0 || this.hp >= this.maxHp) return false; this.hp = this.maxHp; this.rebuild(); return true; }
  damage(n) { if (this.hp <= 0) return; this.hp -= n; audio.breakWood(); if (this.hp <= 0) { this.hp = 0; this.level = 0; hud.message(`Barrikade ${this.slot.name} durchbrochen!`, 2000); } this.rebuild(); }
  // local coords of a point: u along, v across
  local(p) { const dx = p.x - this.center.x, dz = p.z - this.center.z; return { u: dx * this.dir.x + dz * this.dir.z, v: dx * this.normal.x + dz * this.normal.z }; }
  // does the segment a->b cross this wall?
  crosses(a, b) {
    const la = this.local(a), lb = this.local(b);
    if (Math.sign(la.v) === Math.sign(lb.v)) return false;
    const t = la.v / (la.v - lb.v); const u = la.u + (lb.u - la.u) * t;
    return Math.abs(u) < this.halfLen + 0.6;
  }
  pushOut(p, r) {
    const l = this.local(p);
    if (Math.abs(l.u) > this.halfLen + r || Math.abs(l.v) > 0.5 + r) return;
    const s = Math.sign(l.v) || 1; const want = s * (0.5 + r); const dv = want - l.v;
    p.x += this.normal.x * dv; p.z += this.normal.z * dv;
  }
}

export class Barricades {
  constructor(scene, player, world) {
    this.scene = scene; this.player = player; this.list = MAP.barricades.map(s => new Barricade(s, scene));
    world.barricades = this.list; this.near = null;
    document.addEventListener('keydown', e => { if (e.code === 'KeyE') this.interact(); });
  }
  // barricade between zombie and player, if any (closest by distance)
  blocking(from, to) {
    let best = null, bd = 1e9;
    for (const b of this.list) { if (b.hp <= 0) continue; if (b.crosses(from, to)) { const d = b.center.distanceTo(from); if (d < bd) { bd = d; best = b; } } }
    return best;
  }
  interact() {
    const b = this.near; if (!b || !this.player.controls.isLocked) return;
    if (b.level === 0 || b.level < MAX_LEVEL && b.hp >= b.maxHp) {
      if (this.player.score < COST_BUILD) { hud.message(`Zu wenig Punkte (${COST_BUILD})`, 1200); return; }
      if (b.build()) { this.player.addScore(-COST_BUILD); audio.build(); }
    } else if (b.hp < b.maxHp) {
      if (this.player.score < COST_REPAIR) { hud.message(`Zu wenig Punkte (${COST_REPAIR})`, 1200); return; }
      if (b.repair()) { this.player.addScore(-COST_REPAIR); audio.build(); }
    }
    this.updatePrompt();
  }
  updatePrompt() {
    const b = this.near;
    if (!b) return hud.prompt('');
    if (b.level === 0) hud.prompt(`[E] Barrikade bauen (${COST_BUILD} Punkte)`);
    else if (b.hp < b.maxHp) hud.prompt(`[E] Reparieren (${COST_REPAIR}) · ${Math.round(b.hp)}/${b.maxHp}`);
    else if (b.level < MAX_LEVEL) hud.prompt(`[E] Verstärken auf Stufe ${b.level + 1} (${COST_BUILD})`);
    else hud.prompt(`Barrikade Stufe ${b.level} · ${Math.round(b.hp)}/${b.maxHp}`);
  }
  update() {
    let near = null, nd = 3.2;
    for (const b of this.list) { const d = Math.hypot(b.center.x - this.player.position.x, b.center.z - this.player.position.z); if (d < nd) { nd = d; near = b; } }
    if (near !== this.near) { this.near = near; this.updatePrompt(); }
  }
}
