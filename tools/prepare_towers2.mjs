// Fit the Meshy weapon assemblies of the 2 Oct 2026 towers to the shared climbable tower, like
// prepare_towers.mjs did for the first five: the model is turned so its business end points down Godot's
// -Z, scaled to its length, and placed with the muzzle (or lens, or horn mouth) at (0, 0, FRONT) so the
// tower's muzzle node and the gun pivot line up with it. Unlike the first tool the long axis and the
// front end are measured (the front is the slimmer end over the outer eighth, as weapon_geometry.mjs does
// for the hand weapons); SPECS overrides either when a shape fools the rule (a searchlight drum is as
// wide as it is long). PBR maps are kept and shrunk to 1024 px WebP.
// Usage: node tools/prepare_towers2.mjs <kind...>   (reads meshy_output/tower_<kind>_state.json -> refine.glb)
//        node tools/prepare_towers2.mjs --report <kind>   (measurements only, writes nothing)
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, textureCompress, transformMesh, getBounds } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

// length: the assembly's extent along its barrel in metres on the tower; front: where that end sits on the
// gun's z axis (the muzzle node of a gun tower is at -1.7); axis / forward override the measured frame:
// axis 'x' | 'y' | 'z' of the raw file, forward +1 / -1 along it.
const SPECS = {
	rocket: { length: 1.9, front: -1.7 },
	frost: { length: 2.0, front: -1.7 },
	harpoon: { length: 1.9, front: -1.7 },
	graviton: { length: 1.8, front: -1.7 },
	sniper: { length: 2.4, front: -1.7 },
	searchlight: { length: 1.5, front: -1.1, axis: 'z', forward: 1 },   // the drum runs along raw z, the lens disc (5700 vertices) sits at +z
	siren: { length: 1.2, front: -1.0, axis: 'z', forward: 1 },   // the two horns side by side make raw x the widest side; their mouths face raw +z
	supply: { length: 1.6, front: -0.8, upright: true },
};
const argv = process.argv.slice(2);
const report = argv.includes('--report');
const kinds = argv.filter(a => !a.startsWith('--'));
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const identity = () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const percentile = (sorted, q) => sorted[Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))))];

function points(meshes) {
	const out = [];
	for (const mesh of meshes) for (const prim of mesh.listPrimitives()) {
		const pos = prim.getAttribute('POSITION');
		for (let i = 0; i < pos.getCount(); i++) out.push(pos.getElement(i, []));
	}
	return out;
}
function span(pts, a) {
	const v = pts.map(p => p[a]).sort((x, y) => x - y);
	return percentile(v, 0.9) - percentile(v, 0.1);
}

for (const kind of kinds) {
	const spec = SPECS[kind];
	if (!spec) throw new Error(`no SPECS entry for ${kind}`);
	const state = JSON.parse(fs.readFileSync(`meshy_output/tower_${kind}_state.json`, 'utf8'));
	const input = `${state.folder}/refine.glb`;
	if (!fs.existsSync(input)) throw new Error(`Textured Meshy asset still pending: ${kind}`);
	const doc = await io.read(input), root = doc.getRoot(), scene = root.listScenes()[0];
	const meshes = [];
	for (const node of root.listNodes()) if (node.getMesh()) {
		const mesh = node.getMesh(); transformMesh(mesh, node.getWorldMatrix()); meshes.push(mesh);
	}
	for (const child of scene.listChildren()) scene.removeChild(child);
	for (const mesh of meshes) scene.addChild(doc.createNode(`tower_${kind}`).setMesh(mesh));
	let bounds = getBounds(scene);
	let size = bounds.max.map((n, i) => n - bounds.min[i]);
	const pts = points(meshes);
	// the barrel axis: the longest side of the box (upright assemblies keep y as up and use the longest horizontal side)
	let axis = spec.axis ? 'xyz'.indexOf(spec.axis) : (spec.upright ? (size[0] >= size[2] ? 0 : 2) : size.indexOf(Math.max(...size)));
	const rest = [0, 1, 2].filter(a => a !== axis);
	const band = size[axis] * 0.12;
	const lowEnd = pts.filter(p => p[axis] <= bounds.min[axis] + band);
	const highEnd = pts.filter(p => p[axis] >= bounds.max[axis] - band);
	const area = s => span(s, rest[0]) * span(s, rest[1]);
	let forward = spec.forward ?? (area(lowEnd) <= area(highEnd) ? -1 : 1);
	console.log(`${kind}: raw size ${size.map(n => n.toFixed(3)).join(' x ')}, barrel along ${'xyz'[axis]}, front at ${forward < 0 ? 'min' : 'max'} (end areas ${area(lowEnd).toFixed(4)} / ${area(highEnd).toFixed(4)})`);
	if (report) continue;
	// rotation about y that turns the barrel axis onto -z with the front forward; a y barrel (a vertical
	// assembly) stays as it is
	const yaw = axis === 2 ? (forward < 0 ? 0 : Math.PI) : axis === 0 ? (forward < 0 ? -Math.PI / 2 : Math.PI / 2) : 0;
	const rotation = identity();
	rotation[0] = rotation[10] = Math.cos(yaw);
	rotation[2] = -Math.sin(yaw); rotation[8] = Math.sin(yaw);
	for (const mesh of meshes) transformMesh(mesh, rotation);
	bounds = getBounds(scene);
	size = bounds.max.map((n, i) => n - bounds.min[i]);
	const scale = spec.length / (axis === 1 ? size[1] : size[2]);
	// the front slab's median x / y is the bore (or the lens centre): it goes onto the gun's own axis
	const front = [[], []];
	for (const p of points(meshes)) if (p[2] < bounds.min[2] + size[2] * 0.03) { front[0].push(p[0]); front[1].push(p[1]); }
	const median = values => values.sort((a, b) => a - b)[Math.floor(values.length / 2)];
	const matrix = identity();
	matrix[0] = matrix[5] = matrix[10] = scale;
	if (spec.upright) {
		matrix[12] = -(bounds.min[0] + size[0] / 2) * scale;
		matrix[13] = -bounds.min[1] * scale;
		matrix[14] = -(bounds.min[2] + size[2] / 2) * scale;
	} else {
		matrix[12] = -median(front[0]) * scale;
		matrix[13] = -median(front[1]) * scale;
		matrix[14] = -bounds.min[2] * scale + spec.front;
	}
	for (const mesh of meshes) transformMesh(mesh, matrix);
	await doc.transform(dedup(), prune(), textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [1024, 1024] }));
	const output = `godot/assets/models/tower_${kind}.glb`;
	await io.write(output, doc);
	const final = getBounds(scene);
	console.log('PREPARED', output, final.min.map(n => n.toFixed(3)).join(' '), '..', final.max.map(n => n.toFixed(3)).join(' '));
}
