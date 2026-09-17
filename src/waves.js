import { MAP } from './world.js';
import { hud } from './hud.js';
import { audio } from './audio.js';

export class Waves {
  constructor(zombies, player, weapons) {
    this.zombies = zombies; this.player = player; this.weapons = weapons;
    this.wave = 0; this.phase = 'idle'; this.timer = 4; this.queue = []; this.spawnT = 0;
    hud.wave(1, 'Bereit machen ...');
  }

  plan(n) {
    const count = 6 + n * 3;
    const q = [];
    for (let i = 0; i < count; i++) {
      const r = Math.random();
      let type = 'shambler';
      if (n >= 2 && r < 0.15 + n * 0.04) type = 'runner';
      if (n >= 4 && r > 0.92) type = 'brute';
      // lane mix: early waves mostly the road, later more from the forest
      const lr = Math.random();
      const lane = lr < (n < 3 ? 0.7 : 0.45) ? 'south' : lr < 0.8 ? 'east' : 'north';
      q.push({ type, lane });
    }
    return q;
  }

  start(n) {
    this.wave = n; this.queue = this.plan(n); this.phase = 'spawning'; this.spawnT = 0;
    this.zombies.speedMul = 1 + (n - 1) * 0.04;
    hud.wave(n, `${this.queue.length} Zombies`); hud.message(`Welle ${n}`, 2000); audio.wave();
    if (n === 3 && !this.weapons.unlocked.shotgun) { this.weapons.unlock('shotgun'); hud.message('Welle 3\nSchrotflinte freigeschaltet (Taste 2)', 3500); }
  }

  update(dt) {
    if (this.phase === 'idle') {
      this.timer -= dt; hud.wave(this.wave + 1, `Start in ${Math.ceil(this.timer)} s`);
      if (this.timer <= 0) this.start(this.wave + 1);
    } else if (this.phase === 'spawning') {
      this.spawnT -= dt;
      if (this.spawnT <= 0 && this.queue.length) {
        const { type, lane } = this.queue.shift();
        const pts = MAP.spawns[lane]; const p = pts[(Math.random() * pts.length) | 0];
        this.zombies.spawn(type, [p[0] + (Math.random() - .5) * 3, p[1] + (Math.random() - .5) * 3]);
        this.spawnT = Math.max(0.6, 2.2 - this.wave * 0.12);
      }
      hud.wave(this.wave, `${this.zombies.aliveCount + this.queue.length} übrig`);
      if (!this.queue.length && this.zombies.aliveCount === 0) {
        this.phase = 'idle'; this.timer = 18;
        const bonus = 40 + this.wave * 10; this.player.addScore(bonus);
        this.weapons.addAmmo('pistol', 36); if (this.weapons.unlocked.shotgun) this.weapons.addAmmo('shotgun', 12);
        hud.message(`Welle ${this.wave} überstanden\n+${bonus} Punkte, Munition aufgefüllt\nBaue Barrikaden mit E`, 4000); audio.pickup();
      }
    }
  }
}
