// Procedural WebAudio sounds so the game needs no audio files.
let ctx, master;
function ac() { if (!ctx) { ctx = new (window.AudioContext || window.webkitAudioContext)(); master = ctx.createGain(); master.gain.value = 0.5; master.connect(ctx.destination); } if (ctx.state === 'suspended') ctx.resume(); return ctx; }

function noiseBuffer(sec) { const c = ac(); const b = c.createBuffer(1, c.sampleRate * sec, c.sampleRate); const d = b.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1; return b; }
let nb;

function burst({ dur = 0.15, freq = 800, q = 1, gain = 1, decay = 0.1 }) {
  const c = ac(); nb ??= noiseBuffer(1);
  const src = c.createBufferSource(); src.buffer = nb;
  const f = c.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = q;
  const g = c.createGain(); g.gain.setValueAtTime(gain, c.currentTime); g.gain.exponentialRampToValueAtTime(0.001, c.currentTime + decay);
  src.connect(f); f.connect(g); g.connect(master); src.start(); src.stop(c.currentTime + dur);
}
function tone(freq, dur, type = 'sine', gain = 0.3, slide = 0) {
  const c = ac(); const o = c.createOscillator(); o.type = type; o.frequency.setValueAtTime(freq, c.currentTime);
  if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq + slide), c.currentTime + dur);
  const g = c.createGain(); g.gain.setValueAtTime(gain, c.currentTime); g.gain.exponentialRampToValueAtTime(0.001, c.currentTime + dur);
  o.connect(g); g.connect(master); o.start(); o.stop(c.currentTime + dur);
}

export const audio = {
  init() { ac(); },
  pistol() { burst({ freq: 1200, q: 0.7, gain: 1.2, decay: 0.12 }); tone(160, 0.12, 'square', 0.25, -120); },
  shotgun() { burst({ freq: 500, q: 0.5, gain: 1.6, decay: 0.3, dur: 0.35 }); tone(80, 0.25, 'sawtooth', 0.35, -60); },
  reload() { tone(900, 0.05, 'square', 0.08); setTimeout(() => tone(600, 0.06, 'square', 0.1), 140); },
  empty() { tone(1200, 0.04, 'square', 0.08); },
  hit() { burst({ freq: 300, q: 1.5, gain: 0.5, decay: 0.08 }); },
  hurt() { tone(120, 0.35, 'sawtooth', 0.3, -70); burst({ freq: 200, q: 1, gain: 0.5, decay: 0.3 }); },
  growl() { const f = 70 + Math.random() * 60; tone(f, 0.6 + Math.random() * 0.4, 'sawtooth', 0.12, -20); },
  build() { burst({ freq: 700, q: 2, gain: 0.5, decay: 0.15 }); tone(220, 0.1, 'triangle', 0.15); },
  wave() { tone(110, 1.2, 'triangle', 0.25, 30); setTimeout(() => tone(165, 1.2, 'triangle', 0.2), 300); },
  breakWood() { burst({ freq: 400, q: 1, gain: 0.9, decay: 0.25, dur: 0.3 }); },
  pickup() { tone(660, 0.08, 'sine', 0.2); setTimeout(() => tone(990, 0.12, 'sine', 0.2), 80); },
};
