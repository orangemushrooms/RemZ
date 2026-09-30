// Dumps the material textures of a GLB as 512 px PNGs with their mean colour (a real normal map averages
// about 128,128,255; a flat or garbage one does not). Usage: node tools/glb_textures.mjs <file.glb> <outdir>
// dump the textures of a GLB as small PNGs + mean colour, to judge whether a "normal map" really is one
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import sharp from 'sharp';
import path from 'node:path';
const [file, outDir] = process.argv.slice(2);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(file);
const mat = doc.getRoot().listMaterials()[0];
const slots = { base: mat.getBaseColorTexture(), normal: mat.getNormalTexture(), mr: mat.getMetallicRoughnessTexture(), emissive: mat.getEmissiveTexture() };
for (const [slot, tex] of Object.entries(slots)) {
  if (!tex) continue;
  const img = sharp(Buffer.from(tex.getImage()));
  const stats = await img.stats();
  const means = stats.channels.map(c => c.mean.toFixed(0)).join(',');
  const out = path.join(outDir, path.basename(file, '.glb') + '_' + slot + '.png');
  await sharp(Buffer.from(tex.getImage())).resize(512, 512).png().toFile(out);
  console.log(`${path.basename(file)} ${slot}: mean rgb ${means} -> ${out}`);
}
