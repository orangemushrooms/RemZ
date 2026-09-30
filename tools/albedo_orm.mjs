// Gives a base-colour-only Meshy web export (metallic 0, roughness 0.8, no metallic/roughness map - the AR-15,
// the SPAS-12 and the Tommy gun of 30 Sep 2026 came that way) a metallic/roughness texture derived from its
// own albedo, so blued steel, black polymer and walnut stop reading as one flat matte plastic:
//   - saturated warm texels (wood, brass, leather) stay dielectric: metallic 0, roughness 0.45-0.65
//   - grey / black texels are metal: metallic rises with the lack of colour, roughness falls with darkness
//     (blued steel 0.35, worn aluminium 0.55), scratches and highlights in the albedo modulate it
// The map is blurred slightly so JPEG noise does not sparkle. glTF packs roughness in G and metallic in B.
// Usage: node tools/albedo_orm.mjs <in.glb> <out.glb> [--preview orm.png] [--metal-max 0.9] [--wood-rough 0.55]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import sharp from 'sharp';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const [input, output] = plain;
const previewPath = opt('--preview', null);
const METAL_MAX = Number(opt('--metal-max', 0.9));
const WOOD_ROUGH = Number(opt('--wood-rough', 0.55));
const force = args.includes('--force');

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const clamp01 = v => Math.min(1, Math.max(0, v));
const smooth = (a, b, v) => { const t = clamp01((v - a) / (b - a)); return t * t * (3 - 2 * t); };

let written = 0;
for (const material of root.listMaterials()) {
	if (material.getMetallicRoughnessTexture() && !force) { console.log(`${material.getName() || 'material'}: keeps its own metallic/roughness map`); continue; }
	const base = material.getBaseColorTexture();
	if (!base) continue;
	const { data, info } = await sharp(Buffer.from(base.getImage())).removeAlpha().raw().toBuffer({ resolveWithObject: true });
	const w = info.width, h = info.height;
	// A 3x3 box blur on the albedo first: JPEG blocks and grain must not turn into speckled metal.
	const blurred = await sharp(data, { raw: { width: w, height: h, channels: 3 } }).blur(1.2).raw().toBuffer();
	const orm = Buffer.alloc(w * h * 3);
	let metalSum = 0;
	for (let i = 0; i < w * h; i++) {
		const r = blurred[i * 3] / 255, g = blurred[i * 3 + 1] / 255, b = blurred[i * 3 + 2] / 255;
		const max = Math.max(r, g, b), min = Math.min(r, g, b);
		const luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
		const sat = max > 0.02 ? (max - min) / max : 0;
		// warm hue = red over blue: wood, brass, leather. Cold or neutral tints stay metal.
		const warm = clamp01((r - b) * 3.0);
		const dielectric = smooth(0.18, 0.42, sat) * (0.35 + 0.65 * warm);
		let metallic = (1 - dielectric) * METAL_MAX * (0.55 + 0.45 * smooth(0.55, 0.12, luma));
		// Blued steel is smooth and dark, bright scratched metal rougher; wood sits in the middle.
		const metalRough = 0.32 + 0.38 * smooth(0.05, 0.6, luma);
		const roughness = dielectric * (WOOD_ROUGH + 0.12 * (1 - warm)) + (1 - dielectric) * metalRough;
		metallic = clamp01(metallic);
		metalSum += metallic;
		orm[i * 3] = 255;                                   // occlusion channel unused (white)
		orm[i * 3 + 1] = Math.round(clamp01(roughness) * 255);
		orm[i * 3 + 2] = Math.round(metallic * 255);
	}
	const encoded = await sharp(orm, { raw: { width: w, height: h, channels: 3 } }).webp({ quality: 92 }).toBuffer();
	const texture = doc.createTexture('metal_rough').setImage(encoded).setMimeType('image/webp');
	material.setMetallicRoughnessTexture(texture).setMetallicFactor(1).setRoughnessFactor(1);
	if (previewPath) await sharp(orm, { raw: { width: w, height: h, channels: 3 } }).resize(1024, 1024).png().toFile(previewPath);
	console.log(`${material.getName() || 'material'}: metallic/roughness map ${w}x${h} from the albedo, mean metallic ${(metalSum / (w * h)).toFixed(2)}`);
	written++;
}
await io.write(output, doc);
console.log(`${input} -> ${output}: ${written} map(s) written`);
