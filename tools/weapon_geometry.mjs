// Measures weapon and attachment GLBs so weapon mods can be mounted without hand-guessed offsets.
// Meshy statics arrive as ~1.9-unit boxes with the barrel along -X; this probe reports, in that
// raw model frame, where the bore sits, how thick the barrel is, where the magazine hangs and how
// far the receiver reaches. scripts/weapon_attachments.gd consumes the baked JSON.
//
// Usage: node tools/weapon_geometry.mjs [--json tools/out/weapon_geometry.json] [--slabs] <name...>
//        node tools/weapon_geometry.mjs --all-weapons
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MODELS = path.join(ROOT, 'godot', 'assets', 'models');
const WEAPONS = ['pistol', 'revolver', 'smg', 'ak47', 'rifle', 'marksman', 'lmg', 'breacher', 'titanbreaker'];

const argv = process.argv.slice(2);
const jsonAt = argv.indexOf('--json');
const jsonPath = jsonAt >= 0 ? argv[jsonAt + 1] : '';
const showSlabs = argv.includes('--slabs');
let names = argv.filter((a, i) => !a.startsWith('--') && i !== jsonAt + 1);
if (argv.includes('--all-weapons')) names = WEAPONS;

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);

function matMul(a, b) {
	const out = new Array(16).fill(0);
	for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) {
		let v = 0;
		for (let k = 0; k < 4; k++) v += a[k * 4 + r] * b[c * 4 + k];
		out[c * 4 + r] = v;
	}
	return out;
}

function apply(m, v) {
	return [
		m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12],
		m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13],
		m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14],
	];
}

function vertices(doc) {
	const points = [];
	const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
	const walk = (node, parent) => {
		const m = matMul(parent, node.getMatrix());
		const mesh = node.getMesh();
		if (mesh) for (const prim of mesh.listPrimitives()) {
			const pos = prim.getAttribute('POSITION');
			if (!pos) continue;
			for (let i = 0; i < pos.getCount(); i++) points.push(apply(m, pos.getElement(i, [0, 0, 0])));
		}
		for (const child of node.listChildren()) walk(child, m);
	};
	for (const scene of doc.getRoot().listScenes()) for (const node of scene.listChildren()) walk(node, identity);
	return points;
}

const percentile = (sorted, q) => sorted.length ? sorted[Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))))] : 0;

// Principal axes of the point cloud (Jacobi eigenvalue iteration on the 3x3 covariance).
// An attachment GLB can sit tilted inside its own file - mod_ghost does - so the axis the part
// actually runs along is not the longest side of its bounding box.
function principalAxes(points) {
	const n = points.length;
	const mean = [0, 0, 0];
	for (const p of points) for (let a = 0; a < 3; a++) mean[a] += p[a] / n;
	const c = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
	for (const p of points) {
		const d = [p[0] - mean[0], p[1] - mean[1], p[2] - mean[2]];
		for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) c[i][j] += (d[i] * d[j]) / n;
	}
	let v = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
	for (let sweep = 0; sweep < 24; sweep++) {
		let p = 0, q = 1, best = Math.abs(c[0][1]);
		for (const [i, j] of [[0, 2], [1, 2]]) if (Math.abs(c[i][j]) > best) { best = Math.abs(c[i][j]); p = i; q = j; }
		if (best < 1e-12) break;
		const theta = 0.5 * Math.atan2(2 * c[p][q], c[q][q] - c[p][p]);
		const cs = Math.cos(theta), sn = Math.sin(theta);
		const rot = (m, byRow) => {
			for (let k = 0; k < 3; k++) {
				const a = byRow ? m[p][k] : m[k][p];
				const b = byRow ? m[q][k] : m[k][q];
				if (byRow) { m[p][k] = cs * a - sn * b; m[q][k] = sn * a + cs * b; }
				else { m[k][p] = cs * a - sn * b; m[k][q] = sn * a + cs * b; }
			}
		};
		rot(c, false); rot(c, true); rot(v, false);
	}
	const eig = [0, 1, 2]
		.map(i => ({ value: c[i][i], axis: [v[0][i], v[1][i], v[2][i]] }))
		.sort((a, b) => b.value - a.value);
	// Right-handed, longest axis first.
	const [e0, e1] = [eig[0].axis, eig[1].axis];
	const cross = [e0[1] * e1[2] - e0[2] * e1[1], e0[2] * e1[0] - e0[0] * e1[2], e0[0] * e1[1] - e0[1] * e1[0]];
	return { mean, axes: [e0, e1, cross], spread: eig.map(e => Math.sqrt(e.value)) };
}

const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

// Robust centre of a cross section: the median rejects a front sight or a rail sitting off-bore,
// the 10/90 span rejects the few stray vertices every Meshy mesh has.
function crossSection(points, a, b) {
	const as = points.map(p => p[a]).sort((x, y) => x - y);
	const bs = points.map(p => p[b]).sort((x, y) => x - y);
	return {
		centre: [percentile(as, 0.5), percentile(bs, 0.5)],
		span: [percentile(as, 0.9) - percentile(as, 0.1), percentile(bs, 0.9) - percentile(bs, 0.1)],
		full: [as[as.length - 1] - as[0], bs[bs.length - 1] - bs[0]],
		count: points.length,
	};
}

function measure(name) {
	const file = path.join(MODELS, name + '.glb');
	if (!fs.existsSync(file)) return { name, missing: true };
	return io.read(file).then(doc => {
		const points = vertices(doc);
		if (!points.length) return { name, missing: true };
		const min = [Infinity, Infinity, Infinity];
		const max = [-Infinity, -Infinity, -Infinity];
		for (const p of points) for (let a = 0; a < 3; a++) {
			if (p[a] < min[a]) min[a] = p[a];
			if (p[a] > max[a]) max[a] = p[a];
		}
		const size = [max[0] - min[0], max[1] - min[1], max[2] - min[2]];
		const long = size.indexOf(Math.max(...size));
		const rest = [0, 1, 2].filter(a => a !== long);
		// Of the two remaining axes the thinner one is the weapon's width, the other its height.
		const up = size[rest[0]] >= size[rest[1]] ? rest[0] : rest[1];
		const side = rest[0] === up ? rest[1] : rest[0];

		// Which end is the muzzle: the barrel end is the slimmer one over the outer eighth.
		const band = size[long] * 0.12;
		const lowEnd = points.filter(p => p[long] <= min[long] + band);
		const highEnd = points.filter(p => p[long] >= max[long] - band);
		const area = s => s.span[0] * s.span[1];
		const lowSection = crossSection(lowEnd, up, side);
		const highSection = crossSection(highEnd, up, side);
		const muzzleAtMin = area(lowSection) <= area(highSection);
		const front = muzzleAtMin ? min[long] : max[long];
		const forward = muzzleAtMin ? -1 : 1;

		// Bore: the frontmost 3 % of the barrel, median centred, radius from the tight span.
		const tip = points.filter(p => Math.abs(p[long] - front) <= size[long] * 0.03);
		const bore = crossSection(tip, up, side);
		const boreRadius = Math.max(bore.span[0], bore.span[1]) * 0.5;

		// Magazine: the lowest vertices of the gun; their long-axis median is the magwell centre.
		const floor = min[up] + size[up] * 0.06;
		const low = points.filter(p => p[up] <= floor);
		const lowLong = low.map(p => p[long]).sort((x, y) => x - y);
		const magSection = crossSection(low, long, side);

		// Receiver: the thickest quarter along the barrel axis carries bolt and rails.
		const steps = 24;
		const profile = [];
		for (let k = 0; k < steps; k++) {
			const a = min[long] + (size[long] * k) / steps;
			const slab = points.filter(p => p[long] >= a && p[long] < a + size[long] / steps);
			profile.push({
				at: a + size[long] / steps / 2,
				n: slab.length,
				section: slab.length ? crossSection(slab, up, side) : null,
			});
		}
		const bulk = profile.filter(s => s.section).reduce((best, s) => (area(s.section) > area(best.section) ? s : best));

		return {
			name,
			min, max, size,
			axes: { long: 'XYZ'[long], up: 'XYZ'[up], side: 'XYZ'[side], forward },
			bore: { at: front, up: bore.centre[0], side: bore.centre[1], radius: boreRadius, span: bore.span, samples: bore.count },
			magazine: { bottom: min[up], along: percentile(lowLong, 0.5), side: magSection.centre[1], width: magSection.span[1], length: magSection.span[0], samples: low.length },
			receiver: { at: bulk.at, up: bulk.section.centre[0], side: bulk.section.centre[1], height: bulk.section.span[0], width: bulk.section.span[1] },
			top: { up: max[up], side: crossSection(points.filter(p => p[up] >= max[up] - size[up] * 0.08), long, side).centre },
			profile: showSlabs ? profile.map(s => ({ at: +s.at.toFixed(4), n: s.n, up: s.section ? +s.section.centre[0].toFixed(4) : null, h: s.section ? +s.section.span[0].toFixed(4) : null, w: s.section ? +s.section.span[1].toFixed(4) : null })) : undefined,
		};
	});
}

// Attachment parts are measured in their own principal frame: where the part runs, how thick it
// is, which end bolts onto the gun. Everything the mount code needs to place it without guessing.
function measurePart(name) {
	const file = path.join(MODELS, name + '.glb');
	if (!fs.existsSync(file)) return Promise.resolve({ name, missing: true });
	return io.read(file).then(doc => {
		const points = vertices(doc);
		if (!points.length) return { name, missing: true };
		const { mean, axes, spread } = principalAxes(points);
		// A drum magazine is a disc: two long axes and one short one. Its mounting axis is the
		// short one (the drum's face normal), not the longest side.
		const disc = spread[1] > spread[0] * 0.75 && spread[2] < spread[1] * 0.55;
		const main = disc ? axes[2] : axes[0];
		const second = disc ? axes[0] : axes[1];
		const third = [main[1] * second[2] - main[2] * second[1], main[2] * second[0] - main[0] * second[2], main[0] * second[1] - main[1] * second[0]];
		const local = points.map(p => {
			const d = [p[0] - mean[0], p[1] - mean[1], p[2] - mean[2]];
			return [dot(d, main), dot(d, second), dot(d, third)];
		});
		const along = local.map(p => p[0]).sort((a, b) => a - b);
		const lo = percentile(along, 0.002), hi = percentile(along, 0.998);
		const length = hi - lo;
		const band = length * 0.08;
		const section = pts => crossSection(pts, 1, 2);
		const lowEnd = section(local.filter(p => p[0] <= lo + band));
		const highEnd = section(local.filter(p => p[0] >= hi - band));
		const area = s => s.span[0] * s.span[1];
		// The muzzle end of a suppressor or barrel is the slimmer end; for a magazine the slim
		// end is its floor plate, so the mount code flips it per slot anyway.
		const frontAtHigh = area(highEnd) <= area(lowEnd);
		const body = section(local.filter(p => Math.abs(p[0] - (lo + hi) / 2) <= length * 0.25));
		const forward = frontAtHigh ? main : main.map(v => -v);
		const front = frontAtHigh ? highEnd : lowEnd;
		const rear = frontAtHigh ? lowEnd : highEnd;
		return {
			name,
			shape: disc ? 'disc' : length / Math.max(0.0001, Math.max(body.span[0], body.span[1])) > 4 ? 'tube' : 'block',
			centre: mean,
			forward,
			up: second,
			side: third,
			length,
			radius: Math.max(body.span[0], body.span[1]) * 0.5,
			upSpan: body.span[0],
			sideSpan: body.span[1],
			front: { offset: frontAtHigh ? hi : -lo, radius: Math.max(front.span[0], front.span[1]) * 0.5, centre: front.centre },
			rear: { offset: frontAtHigh ? -lo : hi, radius: Math.max(rear.span[0], rear.span[1]) * 0.5, centre: rear.centre },
			spread,
		};
	});
}

const partMode = argv.includes('--parts');
const results = [];
for (const name of names) results.push(await (partMode ? measurePart(name) : measure(name)));

const f = n => (typeof n === 'number' ? n.toFixed(4).padStart(8) : String(n).padStart(8));
const vec = v => '[' + v.map(x => x.toFixed(4).padStart(8)).join(' ') + ']';
for (const r of results) {
	if (r.missing) { console.log(`${r.name}: MISSING`); continue; }
	if (partMode) {
		console.log(`\n=== ${r.name} (${r.shape}) ===`);
		console.log(`forward ${vec(r.forward)}  up ${vec(r.up)}`);
		console.log(`centre  ${vec(r.centre)}  length ${f(r.length)}  radius ${f(r.radius)}  slenderness ${f(r.length / (r.radius * 2))}`);
		console.log(`front   +${f(r.front.offset)} r=${f(r.front.radius)}   rear -${f(r.rear.offset)} r=${f(r.rear.radius)}  offcentre ${vec(r.rear.centre)}`);
		continue;
	}
	console.log(`\n=== ${r.name} ===`);
	console.log(`size      ${r.size.map(f).join(' ')}   long ${r.axes.long} (forward ${r.axes.forward > 0 ? '+' : '-'}${r.axes.long})  up ${r.axes.up}  side ${r.axes.side}`);
	console.log(`bore      at ${f(r.bore.at)}  ${r.axes.up}=${f(r.bore.up)}  ${r.axes.side}=${f(r.bore.side)}  r=${f(r.bore.radius)}  (${r.bore.samples} verts)`);
	console.log(`magazine  bottom ${f(r.magazine.bottom)}  along ${f(r.magazine.along)}  ${r.axes.side}=${f(r.magazine.side)}  ${f(r.magazine.length)} x ${f(r.magazine.width)}`);
	console.log(`receiver  at ${f(r.receiver.at)}  ${r.axes.up}=${f(r.receiver.up)}  h=${f(r.receiver.height)}  w=${f(r.receiver.width)}   top ${r.axes.up}=${f(r.top.up)}`);
	if (showSlabs) for (const s of r.profile) console.log(`   slab ${f(s.at)} n=${String(s.n).padStart(5)} up=${f(s.up)} h=${f(s.h)} w=${f(s.w)}`);
}

const bakeAt = argv.indexOf('--bake');
if (bakeAt >= 0) {
	const out = path.join(ROOT, argv[bakeAt + 1]);
	const v = a => `Vector3(${a.map(x => +x.toFixed(5)).join(', ')})`;
	const n = x => +x.toFixed(5);
	const lines = [];
	lines.push('# Measured geometry of the weapon and attachment models - GENERATED, do not hand-edit.');
	lines.push('# Rebuild with: node tools/weapon_geometry.mjs --all-weapons --bake godot/scripts/weapon_mount_data.gd');
	lines.push('# Values are in the raw GLB frame (Meshy normalises every static to a ~1.9 unit box, barrel');
	lines.push('# along -X). weapon_attachments.gd pushes them through the view model node transform, so they');
	lines.push('# stay correct when a weapon\'s "height" in Weapons.DEFS changes.');
	lines.push('class_name WeaponMountData');
	lines.push('extends RefCounted');
	lines.push('');
	const weapons = results.filter(r => !r.missing && r.bore);
	const head = lines.length;
	if (weapons.length) {
		lines.push('# bore: muzzle centre. mag: lowest point of the magazine. receiver: thickest cross section.');
		lines.push('const WEAPONS := {');
		for (const r of weapons) {
			const axis = r.axes;
			const toRaw = (along, up, side) => {
				const p = [0, 0, 0];
				p['XYZ'.indexOf(axis.long)] = along;
				p['XYZ'.indexOf(axis.up)] = up;
				p['XYZ'.indexOf(axis.side)] = side;
				return p;
			};
			lines.push(`\t"${r.name}": {`);
			lines.push(`\t\t"bore": ${v(toRaw(r.bore.at, r.bore.up, r.bore.side))}, "bore_radius": ${n(r.bore.radius)},`);
			lines.push(`\t\t"mag": ${v(toRaw(r.magazine.along, r.magazine.bottom, r.magazine.side))}, "mag_width": ${n(r.magazine.width)},`);
			lines.push(`\t\t"receiver": ${v(toRaw(r.receiver.at, r.receiver.up, r.receiver.side))}, "receiver_top": ${n(r.top.up)}, "receiver_width": ${n(r.receiver.width)},`);
			lines.push(`\t},`);
		}
		lines.push('}');
		lines.push('');
	}
	const parts = results.filter(r => !r.missing && r.forward);
	if (parts.length) {
		lines.push('# forward points away from the gun (muzzle end), rear is the face that meets the weapon.');
		lines.push('const PARTS := {');
		for (const r of parts) {
			lines.push(`\t"${r.name}": {"shape": "${r.shape}", "forward": ${v(r.forward)}, "up": ${v(r.up)}, "centre": ${v(r.centre)},`);
			lines.push(`\t\t"length": ${n(r.length)}, "radius": ${n(r.radius)}, "up_span": ${n(r.upSpan)}, "side_span": ${n(r.sideSpan)},`);
			lines.push(`\t\t"front": ${n(r.front.offset)}, "front_radius": ${n(r.front.radius)}, "front_centre": Vector2(${n(r.front.centre[0])}, ${n(r.front.centre[1])}),`);
			lines.push(`\t\t"rear": ${n(r.rear.offset)}, "rear_radius": ${n(r.rear.radius)}, "rear_centre": Vector2(${n(r.rear.centre[0])}, ${n(r.rear.centre[1])})},`);
		}
		lines.push('}');
		lines.push('');
	}
	// Weapons and parts are baked in separate runs; keep whichever block this run did not write.
	let text = lines.join('\n');
	if (fs.existsSync(out) && (!weapons.length || !parts.length)) {
		const old = fs.readFileSync(out, 'utf8');
		const match = old.match(new RegExp(`(# [^\\n]*\\n)*const ${weapons.length ? 'PARTS' : 'WEAPONS'} := \\{[\\s\\S]*?\\n\\}\\n`));
		const kept = match ? match[0] : '';
		if (kept) text = weapons.length ? text.trimEnd() + '\n\n' + kept : lines.slice(0, head).join('\n') + '\n' + kept + '\n' + lines.slice(head).join('\n');
	}
	fs.writeFileSync(out, text.replace(/\n+$/, '\n'));
	console.log(`\nbaked ${path.relative(ROOT, out)}`);
}

if (jsonPath) {
	const out = path.isAbsolute(jsonPath) ? jsonPath : path.join(ROOT, jsonPath);
	fs.mkdirSync(path.dirname(out), { recursive: true });
	fs.writeFileSync(out, JSON.stringify(Object.fromEntries(results.filter(r => !r.missing).map(r => [r.name, r])), null, 2));
	console.log(`\nwrote ${path.relative(ROOT, out)}`);
}
