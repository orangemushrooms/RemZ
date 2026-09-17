// Procedural fallback textures (canvas). Photo textures in /textures/<name>.jpg override these when present.
import * as THREE from 'three';

function noiseCanvas(size, fn) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(size, size);
  const d = img.data;
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const i = (y * size + x) * 4;
    const [r, g, b] = fn(x, y, size);
    d[i] = r; d[i + 1] = g; d[i + 2] = b; d[i + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return c;
}

// cheap tileable value noise
const P = new Uint8Array(512);
{ const p = []; for (let i = 0; i < 256; i++) p[i] = i; for (let i = 255; i > 0; i--) { const j = (Math.random() * (i + 1)) | 0; [p[i], p[j]] = [p[j], p[i]]; } for (let i = 0; i < 512; i++) P[i] = p[i & 255]; }
function vnoise(x, y) {
  const xi = Math.floor(x) & 255, yi = Math.floor(y) & 255;
  const xf = x - Math.floor(x), yf = y - Math.floor(y);
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const a = P[P[xi] + yi] / 255, b = P[P[xi + 1] + yi] / 255, c = P[P[xi] + yi + 1] / 255, d = P[P[xi + 1] + yi + 1] / 255;
  return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v;
}
function fbm(x, y, oct = 4) { let s = 0, a = 1, f = 1, n = 0; for (let i = 0; i < oct; i++) { s += a * vnoise(x * f, y * f); n += a; a *= 0.5; f *= 2; } return s / n; }

function make(size, fn, repeat) {
  const t = new THREE.CanvasTexture(noiseCanvas(size, fn));
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat, repeat);
  t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4;
  return t;
}

export const procedural = {
  grass: () => make(256, (x, y) => {
    const n = fbm(x / 18, y / 18, 4), g = fbm(x / 3, y / 3, 2);
    const k = 0.55 + n * 0.45;
    return [40 * k + g * 25, 78 * k + g * 40, 22 * k + g * 12];
  }, 1),
  asphalt: () => make(256, (x, y) => {
    const n = fbm(x / 6, y / 6, 3), g = vnoise(x * 1.7, y * 1.7);
    const v = 52 + n * 30 + g * 22;
    return [v, v, v + 3];
  }, 1),
  gravel: () => make(256, (x, y) => {
    const n = fbm(x / 4, y / 4, 3), g = vnoise(x * 2.3, y * 2.3);
    const v = 105 + n * 40 + g * 45;
    return [v + 8, v + 4, v - 6];
  }, 4),
  dirt: () => make(256, (x, y) => {
    const n = fbm(x / 12, y / 12, 4);
    return [60 + n * 40, 45 + n * 30, 28 + n * 18];
  }, 1),
  wood: () => make(128, (x, y) => {
    const n = fbm(x / 30, y / 4, 3);
    const v = 90 + n * 70;
    return [v + 20, v, v - 25];
  }, 1),
};

export async function loadTexture(name, repeat = 1) {
  const loader = new THREE.TextureLoader();
  const url = `${import.meta.env.BASE_URL}textures/${name}.jpg`;
  try {
    const t = await loader.loadAsync(url);
    t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat, repeat);
    t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
    return t;
  } catch {
    const t = procedural[name](); t.repeat.set(repeat, repeat); return t;
  }
}
