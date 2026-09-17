import * as THREE from 'three';
import { instance } from './assets.js';
import { groundHeight } from './world.js';
import { audio } from './audio.js';

const TYPES = {
  shambler: { model: 'zombie_shambler', hp: 100, speed: 1.6, damage: 12, reach: 1.6, attackTime: 1.1, score: 10, height: 1.8 },
  runner:   { model: 'zombie_runner',   hp: 60,  speed: 4.2, damage: 8,  reach: 1.4, attackTime: 0.7, score: 15, height: 1.7 },
  brute:    { model: 'zombie_shambler', hp: 320, speed: 1.2, damage: 25, reach: 2.0, attackTime: 1.6, score: 40, height: 2.4, tint: 0x8a4a3a },
};

class Zombie {
  constructor(type, pos, mgr) {
    this.type = TYPES[type]; this.mgr = mgr;
    const inst = instance(this.type.model);
    this.obj = inst.obj; this.mixer = inst.mixer; this.actions = inst.actions; this.real = inst.real;
    this.height = this.type.height;
    const scaleVar = 0.92 + Math.random() * 0.16;
    this.obj.scale.setScalar(scaleVar * this.height / 1.8);
    // colour variation so clones look different
    const tint = new THREE.Color().setHSL(Math.random() * 0.1 + 0.2, 0.25, 0.75 + Math.random() * 0.25);
    if (this.type.tint) tint.set(this.type.tint);
    this.obj.traverse(o => { if (o.isMesh && o.material) { o.material = o.material.clone(); if (o.material.color) o.material.color.multiply(tint); } });
    this.obj.position.set(pos[0], groundHeight(pos[0], pos[1]), pos[1]);
    this.hp = this.type.hp; this.maxHp = this.type.hp; this.alive = true; this.dead = false; this.deadT = 0;
    this.attackT = 0; this.state = 'walk'; this.growlT = Math.random() * 6 + 2;
    this.hitFlash = 0; this.target = null; this.hitPending = 0; this.hitTarget = null; this.hitReach = 1.6; this.stuckT = 0; this.steerT = 0; this.steerSide = 1;
    this.play('walk');
    // per-zombie animation speed variation
    if (this.actions.walk) this.actions.walk.timeScale = 0.85 + Math.random() * 0.3;
    this.box = new THREE.Box3();
  }

  play(name, loop = true) {
    if (this.state === name && name !== 'attack') return;
    const a = this.actions[name]; if (!a) return;
    if (this.real) {
      for (const [k, act] of Object.entries(this.actions)) if (k !== name) act.fadeOut(0.15);
      a.reset(); a.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, Infinity); a.clampWhenFinished = true; a.fadeIn(0.15).play();
    } else a.play();
    this.state = name;
  }

  damage(n, dir, head) {
    if (!this.alive) return;
    this.hp -= n; this.hitFlash = 0.12; audio.hit();
    if (this.hp <= 0) this.die(dir, head);
  }

  die(dir) {
    this.alive = false; this.play('death', false);
    this.mgr.player.addScore(this.type.score);
    this.mgr.onKill?.(this);
    if (dir) { this.obj.position.addScaledVector(new THREE.Vector3(dir.x, 0, dir.z).normalize(), 0.3); }
  }

  update(dt, player, barricades) {
    if (this.mixer) this.mixer.update(dt);
    if (this.hitFlash > 0) this.hitFlash -= dt;
    const p = this.obj.position;
    if (!this.alive) {
      this.deadT += dt;
      if (this.deadT > 6) { p.y -= dt * 0.4; if (this.deadT > 9) this.dead = true; }
      return;
    }
    p.y = groundHeight(p.x, p.z);
    // target: the player, or a barricade blocking the way
    const toP = new THREE.Vector3(player.position.x - p.x, 0, player.position.z - p.z);
    const dist = toP.length();
    let target = player.position, isBarricade = false;
    const b = barricades.blocking(p, player.position);
    if (b) { target = b.center; isBarricade = true; }
    const dir = new THREE.Vector3(target.x - p.x, 0, target.z - p.z);
    const d = dir.length(); dir.normalize();
    // face the target
    const yaw = Math.atan2(dir.x, dir.z);
    this.obj.rotation.y += shortest(yaw - this.obj.rotation.y) * Math.min(1, dt * 6);
    this.attackT -= dt;
    const reach = isBarricade ? 1.9 : this.type.reach;
    if (d < reach) {
      if (this.attackT <= 0) {
        this.play('attack', false); this.attackT = this.type.attackTime;
        this.hitPending = 0.35; this.hitTarget = isBarricade ? b : null; this.hitReach = reach;
      } else if (this.attackT < this.type.attackTime - 0.7 && this.state === 'attack') this.play('walk');
    } else {
      if (this.state !== 'walk' && this.attackT < this.type.attackTime - 0.7) this.play('walk');
      if (this.state === 'walk') {
        const sp = this.type.speed * (this.mgr.speedMul || 1);
        // obstacle avoidance: when progress stalls, steer sideways for a while
        if (this.steerT > 0) { this.steerT -= dt; dir.set(dir.x * 0.4 + this.steerSide * -dir.z, 0, dir.z * 0.4 + this.steerSide * dir.x).normalize(); }
        const before = p.clone();
        p.x += dir.x * sp * dt; p.z += dir.z * sp * dt;
        // separation from other zombies
        for (const o of this.mgr.list) { if (o === this || !o.alive) continue; const dx = p.x - o.obj.position.x, dz = p.z - o.obj.position.z, dd = Math.hypot(dx, dz); if (dd < 0.9 && dd > 0.001) { p.x += dx / dd * (0.9 - dd) * 0.5; p.z += dz / dd * (0.9 - dd) * 0.5; } }
        this.mgr.world.resolve(p, 0.4);
        const moved = before.distanceTo(p) / (sp * dt + 1e-6);
        this.stuckT = moved < 0.35 ? this.stuckT + dt : Math.max(0, this.stuckT - dt);
        if (this.stuckT > 0.4 && this.steerT <= 0) { this.steerT = 1.2 + Math.random(); this.steerSide = Math.random() < 0.5 ? -1 : 1; this.stuckT = 0; }
      }
    }
    // the hit lands a moment into the swing
    if (this.hitPending > 0) {
      this.hitPending -= dt;
      if (this.hitPending <= 0) {
        const tgt = this.hitTarget;
        const dd = tgt ? tgt.center.distanceTo(p) : player.position.distanceTo(p);
        if (dd < this.hitReach + 0.6) { if (tgt) tgt.damage(this.type.damage * 2); else if (player.alive) player.damage(this.type.damage); }
      }
    }
    this.growlT -= dt; if (this.growlT <= 0 && dist < 25) { this.growlT = 4 + Math.random() * 8; audio.growl(); }
  }
}

function shortest(a) { return Math.atan2(Math.sin(a), Math.cos(a)); }

export class Zombies {
  constructor(scene, world, player) {
    this.scene = scene; this.world = world; this.player = player; this.list = []; this.speedMul = 1;
    this.particles = []; this.onKill = null;
    this.bloodGeo = new THREE.SphereGeometry(0.05, 4, 4); this.bloodMat = new THREE.MeshBasicMaterial({ color: 0x5a0a0a });
  }

  spawn(type, pos) { const z = new Zombie(type, pos, this); this.scene.add(z.obj); this.list.push(z); return z; }
  get aliveCount() { return this.list.filter(z => z.alive).length; }

  raycast(ray) {
    let best = null;
    for (const z of this.list) {
      if (!z.alive) continue;
      z.box.setFromCenterAndSize(new THREE.Vector3(z.obj.position.x, z.obj.position.y + z.height / 2, z.obj.position.z), new THREE.Vector3(0.7, z.height, 0.7));
      const pt = new THREE.Vector3();
      if (ray.ray.intersectBox(z.box, pt)) { const d = pt.distanceTo(ray.ray.origin); if (d <= ray.far && (!best || d < best.d)) best = { d, point: pt, zombie: z }; }
    }
    return best;
  }

  blood(point, dir) {
    for (let i = 0; i < 6; i++) {
      const m = new THREE.Mesh(this.bloodGeo, this.bloodMat); m.position.copy(point);
      const v = new THREE.Vector3(dir.x + (Math.random() - .5), Math.random() * 1.5, dir.z + (Math.random() - .5)).multiplyScalar(2.5);
      this.scene.add(m); this.particles.push({ m, v, t: 0.7 });
    }
  }

  update(dt, barricades) {
    for (const z of this.list) z.update(dt, this.player, barricades);
    for (const z of this.list) if (z.dead) this.scene.remove(z.obj);
    this.list = this.list.filter(z => !z.dead);
    for (const p of this.particles) { p.t -= dt; p.v.y -= 9 * dt; p.m.position.addScaledVector(p.v, dt); if (p.t <= 0) this.scene.remove(p.m); }
    this.particles = this.particles.filter(p => p.t > 0);
    // hit flash tint
    for (const z of this.list) if (z.hitFlash > 0 || z._flashed) { const on = z.hitFlash > 0; if (on !== !!z._flashed) { z._flashed = on; z.obj.traverse(o => { if (o.isMesh && o.material?.emissive) o.material.emissive.setHex(on ? 0x662222 : 0x000000); }); } }
  }
}
