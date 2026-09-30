// Bakes a rigid transform into the vertices of a static GLB: rotation, uniform scale to a target extent and a
// new origin. Used for the melee models, which weapons.gd mounts without any fitting (melee_models.gd): the
// knife's frame is blade along +Y, spine along -X, thickness along Z, 0.37 m long, origin at the guard - the
// frame knife_real.glb (Sep 2026) established. A Meshy web export arrives as a ~1.9 unit box with the blade
// along -X, so it is turned and shrunk here once instead of in every consumer.
// Usage: node tools/reframe_glb.mjs <in.glb> <out.glb> [--rotate rx,ry,rz] [--fit-axis y --fit 0.37]
//        [--anchor y=0.324] [--center x,z]
//   --rotate   degrees about X, then Y, then Z (applied in that order to positions, normals and tangents)
//   --fit      scales uniformly so the extent along --fit-axis becomes this length (metres)
//   --anchor   puts the origin at this fraction of the extent along that axis (0 = min, 1 = max)
//   --center   centres the mesh on these axes
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

const args = process.argv.slice(2);
const opt = (flag, fallback) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : fallback; };
const plain = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const [input, output] = plain;
const rotate = opt('--rotate', '0,0,0').split(',').map(Number);
const fitAxis = 'xyz'.indexOf(opt('--fit-axis', 'y'));
const fit = Number(opt('--fit', 0));
const anchor = opt('--anchor', null);
const center = opt('--center', '').split(',').filter(Boolean).map(a => 'xyz'.indexOf(a));

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();

// rotation matrix (row major 3x3) = Rz * Ry * Rx
const rad = d => (d * Math.PI) / 180;
const [ax, ay, az] = rotate.map(rad);
const Rx = [[1, 0, 0], [0, Math.cos(ax), -Math.sin(ax)], [0, Math.sin(ax), Math.cos(ax)]];
const Ry = [[Math.cos(ay), 0, Math.sin(ay)], [0, 1, 0], [-Math.sin(ay), 0, Math.cos(ay)]];
const Rz = [[Math.cos(az), -Math.sin(az), 0], [Math.sin(az), Math.cos(az), 0], [0, 0, 1]];
const mul = (A, B) => A.map((row, i) => [0, 1, 2].map(j => row[0] * B[0][j] + row[1] * B[1][j] + row[2] * B[2][j]));
const R = mul(Rz, mul(Ry, Rx));
const apply = v => [R[0][0] * v[0] + R[0][1] * v[1] + R[0][2] * v[2], R[1][0] * v[0] + R[1][1] * v[1] + R[1][2] * v[2], R[2][0] * v[0] + R[2][1] * v[1] + R[2][2] * v[2]];

// Node transforms are folded in first so the baked mesh stands in world space with identity nodes.
const nodeMatrix = new Map();
const walk = (node, parent) => {
	const m = node.getMatrix();
	const world = parent ? mat4mul(parent, m) : m;
	nodeMatrix.set(node, world);
	for (const c of node.listChildren()) walk(c, world);
};
function mat4mul(a, b) {
	const out = new Array(16).fill(0);
	for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) { let v = 0; for (let k = 0; k < 4; k++) v += a[k * 4 + r] * b[c * 4 + k]; out[c * 4 + r] = v; }
	return out;
}
const xf = (m, v) => [m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12], m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13], m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14]];
const xfDir = (m, v) => [m[0] * v[0] + m[4] * v[1] + m[8] * v[2], m[1] * v[0] + m[5] * v[1] + m[9] * v[2], m[2] * v[0] + m[6] * v[1] + m[10] * v[2]];
for (const scene of root.listScenes()) for (const n of scene.listChildren()) walk(n, null);

const prims = [];
for (const node of root.listNodes()) {
	const mesh = node.getMesh();
	if (!mesh) continue;
	for (const prim of mesh.listPrimitives()) prims.push({ prim, matrix: nodeMatrix.get(node) });
	node.setMatrix([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
}

// pass 1: rotate into the target frame, measure
const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
const seen = new Set();
for (const { prim, matrix } of prims) {
	const pos = prim.getAttribute('POSITION');
	if (seen.has(pos)) continue;
	seen.add(pos);
	const arr = pos.getArray();
	for (let i = 0; i < arr.length; i += 3) {
		const p = apply(xf(matrix, [arr[i], arr[i + 1], arr[i + 2]]));
		for (let a = 0; a < 3; a++) { arr[i + a] = p[a]; if (p[a] < min[a]) min[a] = p[a]; if (p[a] > max[a]) max[a] = p[a]; }
	}
	pos.setArray(arr);
	for (const name of ['NORMAL', 'TANGENT']) {
		const acc = prim.getAttribute(name);
		if (!acc || seen.has(acc)) continue;
		seen.add(acc);
		const d = acc.getArray(), stride = acc.getElementSize();
		for (let i = 0; i < d.length; i += stride) {
			const v = apply(xfDir(matrix, [d[i], d[i + 1], d[i + 2]]));
			const l = Math.hypot(v[0], v[1], v[2]) || 1;
			d[i] = v[0] / l; d[i + 1] = v[1] / l; d[i + 2] = v[2] / l;
		}
		acc.setArray(d);
	}
}
const size = [max[0] - min[0], max[1] - min[1], max[2] - min[2]];
const scale = fit > 0 ? fit / size[fitAxis] : 1;
const shift = [0, 0, 0];
if (anchor) {
	const [axisName, fraction] = anchor.split('=');
	const a = 'xyz'.indexOf(axisName);
	shift[a] = -(min[a] + (max[a] - min[a]) * Number(fraction));
}
for (const a of center) shift[a] = -(min[a] + max[a]) / 2;

// pass 2: scale about the anchor
seen.clear();
const outMin = [Infinity, Infinity, Infinity], outMax = [-Infinity, -Infinity, -Infinity];
for (const { prim } of prims) {
	const pos = prim.getAttribute('POSITION');
	if (seen.has(pos)) continue;
	seen.add(pos);
	const arr = pos.getArray();
	for (let i = 0; i < arr.length; i += 3) for (let a = 0; a < 3; a++) {
		arr[i + a] = (arr[i + a] + shift[a]) * scale;
		if (arr[i + a] < outMin[a]) outMin[a] = arr[i + a];
		if (arr[i + a] > outMax[a]) outMax[a] = arr[i + a];
	}
	pos.setArray(arr);
	pos.setMin ? null : null;
}
await io.write(output, doc);
const f = v => v.map(x => x.toFixed(3)).join(' ');
console.log(`${input} -> ${output}: rotated ${rotate.join('/')} deg, scale ${scale.toFixed(4)}, bounds ${f(outMin)} .. ${f(outMax)}`);
