const $ = id => document.getElementById(id);
let msgTimer, promptEl = $('prompt');

export const hud = {
  health(v, max) { $('hp').style.width = `${Math.max(0, v / max * 100)}%`; },
  score(v) { $('score').textContent = v; },
  ammo(now, reserve, name) { $('ammoNow').textContent = now; $('ammoRes').textContent = reserve; $('weaponName').textContent = name; },
  wave(n, info) { $('waveNo').textContent = n; $('waveInfo').textContent = info; },
  message(text, ms = 2500) {
    const el = $('msg'); el.textContent = text; el.style.opacity = 1;
    clearTimeout(msgTimer); if (ms > 0) msgTimer = setTimeout(() => (el.style.opacity = 0), ms);
  },
  prompt(text) { promptEl.textContent = text || ''; promptEl.style.opacity = text ? 1 : 0; },
  damage() { const d = $('damage'); d.style.opacity = 1; setTimeout(() => (d.style.opacity = 0), 180); },
};
