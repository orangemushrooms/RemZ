// Contact sheet of Meshy animation-library preview GIFs (free, no credits): one row per clip, evenly spaced
// frames, so clips can be chosen by eye before buying them for a rig.
// Usage: node tools/anim_contact_sheet.mjs <out.png> <catalog.json> <id> [id ...] [--frames 6] [--size 150]
import sharp from 'sharp';
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? Number(args[i + 1]) : fallback; };
const frames = opt('--frames', 6), size = opt('--size', 150);
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const [out, catalogPath, ...ids] = plain;
const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8')).result.list;
const tiles = [];
let row = 0;
for (const id of ids.map(Number)) {
  const entry = catalog.find(a => a.id === id);
  if (!entry) { console.log('unknown id', id); continue; }
  const response = await fetch(entry.previewUrl);
  const gif = Buffer.from(await response.arrayBuffer());
  const meta = await sharp(gif, { animated: true }).metadata();
  const pages = meta.pages || 1;
  for (let f = 0; f < frames; f++) {
    const page = Math.min(pages - 1, Math.round(f * (pages - 1) / Math.max(frames - 1, 1)));
    tiles.push({ input: await sharp(gif, { page }).resize(size, size).flatten({ background: '#ffffff' }).png().toBuffer(), left: 170 + f * size, top: row * size });
  }
  const label = Buffer.from(`<svg width="170" height="${size}"><rect width="170" height="${size}" fill="#1b2430"/>` +
    `<text x="8" y="${size / 2 - 6}" fill="#f5d27a" font-family="Arial" font-size="18">${id}</text>` +
    `<text x="8" y="${size / 2 + 16}" fill="#e2e8f0" font-family="Arial" font-size="12">${entry.name.replace(/&/g, '&amp;')}</text></svg>`);
  tiles.push({ input: label, left: 0, top: row * size });
  console.log(id, entry.name, 'frames', pages);
  row++;
}
await sharp({ create: { width: 170 + frames * size, height: row * size, channels: 3, background: '#ffffff' } }).composite(tiles).png().toFile(out);
console.log(out);
