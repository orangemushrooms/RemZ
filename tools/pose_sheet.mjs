// Before / after sheet of skinned poses: renders chosen clip moments of one or more GLBs with glb_preview's
// software rasteriser (front + side) and tiles them, one row per GLB, one column per pose.
// Usage: node tools/pose_sheet.mjs <out.png> --poses walk@0.4,run@0.2,death2@1.5 <a.glb> [b.glb ...] [--size 260]
import { execFileSync } from 'node:child_process';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const size = Number(opt('--size', 260));
const views = opt('--views', 'front,side');
const poses = opt('--poses', 'walk@0.4').split(',').map(p => { const [clip, t] = p.split('@'); return { clip, t: Number(t) }; });
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const [out, ...files] = plain;
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'poses-'));
const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const panelW = size * views.split(',').length, panelH = size + 26;
const tiles = [];
files.forEach((file, row) => {
  poses.forEach(({ clip, t }, col) => {
    const target = path.join(tmp, `${row}_${col}.png`);
    execFileSync(process.execPath, ['--max-old-space-size=6000', path.join(here, 'glb_preview.mjs'), file, target, '--size', String(size), '--anim', clip, '--time', String(t), '--views', views], { stdio: 'ignore' });
    tiles.push({ input: target, left: col * panelW, top: row * panelH });
  });
});
await sharp({ create: { width: panelW * poses.length, height: panelH * files.length, channels: 3, background: '#11161c' } })
  .composite(tiles).png().toFile(out);
console.log(out);
