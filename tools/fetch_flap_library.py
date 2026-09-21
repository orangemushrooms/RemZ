"""Bake a real bird wingbeat into godot/assets/cornfield/flap_cycle.json.

Source library: the animated bird models shipped with three.js
(https://github.com/mrdoob/three.js -> examples/models/gltf/{Stork,Parrot,Flamingo}.glb,
originally from the "ro.me" project by mirada, CC-BY).  Each model stores one full
flight cycle as a flip book of morph targets, so the wing geometry of every pose can
be measured directly - no Blender and no runtime dependency on the library.

For each pose we take three vertex groups of the left wing (shoulder, wrist, tip),
picked once in the rest pose and then tracked through the morphs, and turn them into
the two angles our raven rig actually has:

    inner  - shoulder -> wrist elevation  (Wing_L / Wing_R bone)
    outer  - wrist -> tip elevation, made local to the parent bone (Tip_L / Tip_R)
    sweep  - wrist -> tip fore/aft rowing (folded axis of both bones)

The curves are centred on their own mean (0 = the extended rest pose of our model),
resampled to a smooth loop and written as radians.  Run after changing SAMPLES, the
vertex bands or the source list; the JSON is committed.
"""
import json, math, struct, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'tools' / 'out' / 'flap_src'
OUT = ROOT / 'godot' / 'scripts' / 'flap_cycle.gd'
BASE = 'https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/models/gltf/'
# name -> (file, shoulder band, wrist band, tip band) as fractions of the half span
SOURCES = {
	'parrot': ('Parrot.glb', (0.05, 0.17), (0.44, 0.60), (0.86, 1.01)),
	'stork': ('Stork.glb', (0.05, 0.17), (0.44, 0.60), (0.86, 1.01)),
}
SAMPLES = 32
CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def fetch(fname: str) -> bytes:
	CACHE.mkdir(parents=True, exist_ok=True)
	local = CACHE / fname
	if not local.exists():
		print('download', BASE + fname, flush=True)
		with urllib.request.urlopen(BASE + fname, timeout=60) as r:
			local.write_bytes(r.read())
	return local.read_bytes()


def glb(data: bytes):
	assert data[:4] == b'glTF', 'not a binary glTF'
	off, js, blob = 12, None, None
	while off < len(data):
		length, kind = struct.unpack_from('<II', data, off)
		if kind == 0x4E4F534A:
			js = json.loads(data[off + 8:off + 8 + length].decode('utf8'))
		else:
			blob = data[off + 8:off + 8 + length]
		off += 8 + length
	return js, blob


def accessor(js, blob, index):
	acc = js['accessors'][index]
	view = js['bufferViews'][acc['bufferView']]
	fmt, size = CT[acc['componentType']]
	count = NC[acc['type']]
	stride = view.get('byteStride') or size * count
	start = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
	return [struct.unpack_from('<' + fmt * count, blob, start + i * stride) for i in range(acc['count'])]


def poses(js, blob):
	"""Every morph target of the flight cycle as absolute vertex positions."""
	prim = js['meshes'][0]['primitives'][0]
	rest = accessor(js, blob, prim['attributes']['POSITION'])
	targets = [accessor(js, blob, t['POSITION']) for t in prim['targets']]
	sampler = js['animations'][0]['samplers'][0]
	times = [t[0] for t in accessor(js, blob, sampler['input'])]
	flat = [w[0] for w in accessor(js, blob, sampler['output'])]
	weights = [flat[i * len(targets):(i + 1) * len(targets)] for i in range(len(times))]
	out = []
	for time, keyed in zip(times, weights):
		if out and time >= times[-1]:
			break  # the closing key repeats the first pose
		moved = [(rest[i][0] + sum(w * targets[j][i][0] for j, w in enumerate(keyed) if w),
			rest[i][1] + sum(w * targets[j][i][1] for j, w in enumerate(keyed) if w),
			rest[i][2] + sum(w * targets[j][i][2] for j, w in enumerate(keyed) if w)) for i in range(len(rest))]
		out.append(moved)
	return rest, out, times[-1]


def centred(values):
	mean = sum(values) / len(values)
	return [v - mean for v in values]


def resample(values, count):
	"""Catmull-Rom over the closed loop; the 10 fps flip book gets a smooth cycle."""
	n = len(values)
	out = []
	for i in range(count):
		x = i * n / count
		k = int(math.floor(x))
		t = x - k
		p0, p1, p2, p3 = (values[(k - 1) % n], values[k % n], values[(k + 1) % n], values[(k + 2) % n])
		out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
			+ (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
	return out


def measure(name, fname, bands):
	js, blob = glb(fetch(fname))
	rest, frames, duration = poses(js, blob)
	span = max(abs(p[0]) for p in rest)
	groups = [[i for i, p in enumerate(rest) if lo * span <= -p[0] <= hi * span] for lo, hi in bands]
	assert all(groups), '%s: a vertex band is empty, adjust SOURCES' % name
	inner, outer, sweep = [], [], []
	for frame in frames:
		def mid(group):
			return tuple(sum(axis(frame[i]) for i in group) / len(group)
				for axis in (lambda p: -p[0], lambda p: p[1], lambda p: p[2]))
		shoulder, wrist, tip = (mid(g) for g in groups)
		a = math.atan2(wrist[1] - shoulder[1], max(1e-6, wrist[0] - shoulder[0]))
		b = math.atan2(tip[1] - wrist[1], max(1e-6, tip[0] - wrist[0]))
		inner.append(a)
		outer.append(b - a)  # Tip_* hangs under Wing_*, so store the local angle
		sweep.append(math.atan2(tip[2] - wrist[2], max(1e-6, tip[0] - wrist[0])))
	cycle = {'duration': round(duration, 3), 'poses': len(frames),
		'inner': [round(v, 5) for v in resample(centred(inner), SAMPLES)],
		'outer': [round(v, 5) for v in resample(centred(outer), SAMPLES)],
		'sweep': [round(v, 5) for v in resample(centred(sweep), SAMPLES)]}
	for key in ('inner', 'outer', 'sweep'):
		values = cycle[key]
		print('%-7s %-6s %5.1f deg .. %5.1f deg' % (name, key, math.degrees(min(values)), math.degrees(max(values))))
	return cycle


def emit(cycles):
	"""A plain GDScript const beats a res:// JSON: preload works in exported builds too."""
	lines = ['# Generated by tools/fetch_flap_library.py - do not edit by hand.',
		'# Wingbeat cycles measured from the animated bird models of the three.js library',
		'# (examples/models/gltf/{Parrot,Stork}.glb, flight cycles from ro.me by mirada, CC-BY).',
		'# Angles in radians, centred on the extended rest pose, %d samples per loop:' % SAMPLES,
		'#   inner = shoulder joint (Wing_L/R), outer = wrist joint local to it (Tip_L/R),',
		'#   sweep = fore/aft rowing of the hand wing.',
		'extends RefCounted', '', 'const SAMPLES := %d' % SAMPLES, '', 'const CYCLES := {']
	for name, cycle in cycles.items():
		lines.append('\t"%s": {  # %.2f s, %d poses' % (name, cycle['duration'], cycle['poses']))
		for key in ('inner', 'outer', 'sweep'):
			lines.append('\t\t"%s": [%s],' % (key, ', '.join('%.5f' % v for v in cycle[key])))
		lines.append('\t},')
	lines += ['}', '']
	OUT.write_text('\n'.join(lines), encoding='utf-8')
	print('WROTE', OUT)


if __name__ == '__main__':
	emit({name: measure(name, fname, (bands[0], bands[1], bands[2]))
		for name, (fname, *bands) in SOURCES.items()})
