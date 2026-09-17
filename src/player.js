import * as THREE from 'three';
import { groundHeight } from './world.js';
import { hud } from './hud.js';
import { audio } from './audio.js';

// Minimal mouse-look controller. Uses the Pointer Lock API when available and falls back to
// plain mouse movement over the canvas (embedded browsers, iframes) so the game stays playable.
class Look {
  constructor(camera, dom) {
    this.camera = camera; this.dom = dom; this.object = new THREE.Object3D(); this.object.add(camera);
    this.yaw = Math.PI; this.pitch = 0; this.isLocked = false; this.usingLock = false; this.sens = 0.0022;
    camera.rotation.order = 'YXZ';
    document.addEventListener('mousemove', e => {
      if (!this.isLocked) return;
      if (this.usingLock && document.pointerLockElement !== dom) return;
      this.yaw -= e.movementX * this.sens; this.pitch -= e.movementY * this.sens;
      this.pitch = Math.max(-1.45, Math.min(1.45, this.pitch));
    });
    document.addEventListener('pointerlockchange', () => {
      if (document.pointerLockElement === dom) { this.usingLock = true; this.isLocked = true; }
      else if (this.usingLock) { this.usingLock = false; this.isLocked = false; this.onUnlock?.(); }
    });
    document.addEventListener('pointerlockerror', () => { this.usingLock = false; this.isLocked = true; });
    document.addEventListener('keydown', e => { if (e.code === 'Escape' && this.isLocked && !this.usingLock) { this.isLocked = false; this.onUnlock?.(); } });
  }
  lock() {
    this.isLocked = true;
    try { const p = this.dom.requestPointerLock({ unadjustedMovement: true }); if (p?.catch) p.catch(() => { this.usingLock = false; }); } catch { this.usingLock = false; }
  }
  unlock() { if (this.usingLock) document.exitPointerLock(); this.isLocked = false; }
  apply() { this.object.rotation.set(0, this.yaw, 0); this.camera.rotation.x = this.pitch; }
}

export class Player {
  constructor(camera, dom, world) {
    this.camera = camera; this.world = world;
    this.controls = new Look(camera, dom);
    this.obj = this.controls.object;
    this.obj.position.set(0, groundHeight(0, -48) + 1.7, -48);
    this.vel = new THREE.Vector3();
    this.keys = {};
    this.maxHp = 100; this.hp = 100; this.score = 0; this.alive = true;
    this.eye = 1.7; this.bob = 0; this.regenTimer = 0;
    this.flashOn = true;
    // flashlight attached to the camera
    this.flash = new THREE.SpotLight(0xfff2d6, 40, 45, 0.42, 0.55, 1.4);
    this.flash.castShadow = true; this.flash.shadow.mapSize.set(1024, 1024); this.flash.shadow.bias = -0.002;
    this.flash.position.set(0.15, -0.1, -0.7); // in front of the view-model so the weapon is not blown out
    this.flash.target.position.set(0, 0, -10);
    camera.add(this.flash); camera.add(this.flash.target);
    this.wobble = 0;

    document.addEventListener('keydown', e => { this.keys[e.code] = true; if (e.code === 'KeyF') this.toggleFlash(); });
    document.addEventListener('keyup', e => { this.keys[e.code] = false; });
    addEventListener('blur', () => { this.keys = {}; });
    hud.health(this.hp, this.maxHp);
  }

  toggleFlash() { this.flashOn = !this.flashOn; this.flash.intensity = this.flashOn ? 40 : 0; }

  get position() { return this.obj.position; }

  damage(n) {
    if (!this.alive) return;
    this.hp -= n; this.regenTimer = 5; hud.health(this.hp, this.maxHp); hud.damage(); audio.hurt();
    this.wobble = 1;
    if (this.hp <= 0) { this.hp = 0; this.alive = false; }
  }

  addScore(n) { this.score += n; hud.score(this.score); }

  update(dt) {
    if (!this.controls.isLocked || !this.alive) return;
    this.controls.apply();
    const k = this.keys;
    const sprint = k.ShiftLeft || k.ShiftRight;
    const speed = sprint ? 7.2 : 4.4;
    const dir = new THREE.Vector3((k.KeyD ? 1 : 0) - (k.KeyA ? 1 : 0), 0, (k.KeyS ? 1 : 0) - (k.KeyW ? 1 : 0));
    if (dir.lengthSq() > 0) dir.normalize();
    dir.applyAxisAngle(new THREE.Vector3(0, 1, 0), this.controls.yaw);
    const target = dir.multiplyScalar(speed);
    this.vel.x += (target.x - this.vel.x) * Math.min(1, dt * 12);
    this.vel.z += (target.z - this.vel.z) * Math.min(1, dt * 12);
    const p = this.obj.position;
    p.x += this.vel.x * dt; p.z += this.vel.z * dt;
    this.world.resolve(p, 0.45);
    const moving = Math.hypot(this.vel.x, this.vel.z) > 0.5;
    this.bob += dt * (moving ? (sprint ? 13 : 9) : 0);
    const bobY = moving ? Math.sin(this.bob) * 0.045 : 0;
    p.y = groundHeight(p.x, p.z) + this.eye + bobY;
    this.wobble = Math.max(0, this.wobble - dt * 3);
    this.camera.rotation.z = Math.sin(this.bob * 0.5) * 0.004 * (moving ? 1 : 0) + Math.sin(this.wobble * 30) * 0.02 * this.wobble;
    if (this.regenTimer > 0) this.regenTimer -= dt; else if (this.hp < this.maxHp) { this.hp = Math.min(this.maxHp, this.hp + dt * 4); hud.health(this.hp, this.maxHp); }
  }
}
