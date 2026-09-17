// Turns dist/index.html into an Artifact page fragment (no doctype/html/head/body, no viewport meta)
// and writes dist/artifact.html. Supporting files (JS bundle, models, textures) stay as they are.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = fs.readFileSync(path.join(ROOT, 'dist', 'index.html'), 'utf8');
const head = /<head>([\s\S]*?)<\/head>/i.exec(html)?.[1] ?? '';
const body = /<body>([\s\S]*?)<\/body>/i.exec(html)?.[1] ?? '';
const headKeep = head
  .replace(/<meta[^>]*charset[^>]*>\s*/gi, '')
  .replace(/<meta[^>]*viewport[^>]*>\s*/gi, '')
  .trim();
const out = `${headKeep}\n${body.trim()}\n`;
fs.writeFileSync(path.join(ROOT, 'dist', 'artifact.html'), out);
const list = [];
for (const dir of ['assets', 'models', 'textures']) {
  const d = path.join(ROOT, 'dist', dir);
  if (!fs.existsSync(d)) continue;
  for (const f of fs.readdirSync(d)) if (!f.endsWith('.glb')) list.push(`${dir}/${f}`);
}
fs.writeFileSync(path.join(ROOT, 'dist', 'files.json'), JSON.stringify(Object.fromEntries(list.map(p => [p, `dist/${p}`])), null, 2));
console.log('artifact.html', out.length, 'bytes; files:', list.join(', '));
