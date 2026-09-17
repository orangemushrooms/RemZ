# Level layout from the user's hand-drawn plan (Map_1 / Map_2). +X = east, +Z = south, north is -Z.
# Scale: the plan is treated as 210 m x 115 m, origin in the middle.
class_name Map

# ---- roads and paths: polylines of Vector2(x, z), with width and surface ----
const ROADS := [
	{ "name": "Nordstrasse", "pts": [Vector2(-110, -39), Vector2(110, -39)], "width": 5.0, "surface": "asphalt" },
	{ "name": "Weg Richtung Dorf", "pts": [Vector2(54, -39), Vector2(54, 62)], "width": 4.5, "surface": "asphalt" },
	{ "name": "Weg zur Hütte", "pts": [Vector2(41, -39), Vector2(41, 16)], "width": 3.6, "surface": "gravel" },
	{ "name": "Waldweg nach Hütte", "pts": [Vector2(-110, 16), Vector2(54, 16)], "width": 4.0, "surface": "gravel" },
]
const STREAM := [Vector2(-44, 22), Vector2(-42, 30), Vector2(-38, 40), Vector2(-37, 50), Vector2(-36, 64)]

# ---- forest blocks (Rect2 x, z, w, d) ----
const FORESTS := {
	"Wald Nord (Streifen zur Nordstrasse)": Rect2(-110, -36, 143, 13),   # one continuous forest, no gap to the road
	"Wald Nord West": Rect2(-110, -23, 54, 33),
	"Wald Nord 2": Rect2(-15, -23, 46, 8),
	"Wald Süd 2": Rect2(-110, 24, 74, 42),
	"Wald Süd 1": Rect2(15, 29, 17, 37),
	"Wald Süd hinten": Rect2(-36, 49, 51, 17),
	"Wald West": Rect2(-150, -60, 40, 130),
	"Wald Nord hinten": Rect2(-150, -80, 300, 36),
	"Wald Süd ganz": Rect2(-150, 66, 200, 30),
}
const CLEARING := Rect2(-56, -23, 89, 35)     # the campsite clearing (leaf litter floor)
const MEADOW_X := 56.0                        # everything east of this is the meadow

# ---- buildings ----
const WALDHUETTE := { "pos": Vector2(12, -4), "size": Vector2(10, 8), "yaw": PI / 2.0 }   # door faces west
const HOLZAGER := { "pos": Vector2(-6, 38), "size": Vector2(16, 9), "yaw": 0.0 }

# ---- campsite ----
const FIRE := Vector2(-28, -9)
const BENCHES := [   # pos, yaw (bench length axis)
	[Vector2(-37.5, -9), PI / 2.0],   # Bank 1 west
	[Vector2(-18.5, -9), PI / 2.0],   # Bank 2 east
	[Vector2(-28, -3.5), 0.0],        # Bank 3 south
	[Vector2(-28, -16.5), 0.0],       # Bank 4 north
]
const TABLE := Vector2(-23.5, -1.0)
const WELL := Vector2(-17, 5)
const PLAYER_START := Vector2(-28, -1)

const BOUNDS := Rect2(-120, -75, 240, 150)

const BARRICADES := [
	{ "id": "e", "name": "Weg zur Hütte", "pos": Vector2(34, -6), "yaw": PI / 2.0, "segments": 2 },
	{ "id": "sw", "name": "Waldweg West", "pos": Vector2(-44, 12), "yaw": 0.0, "segments": 3 },
	{ "id": "s", "name": "Waldweg Mitte", "pos": Vector2(-14, 12), "yaw": 0.0, "segments": 3 },
	{ "id": "se", "name": "Waldweg Ost", "pos": Vector2(20, 12), "yaw": 0.0, "segments": 3 },
]
const SPAWNS := {
	"north": [Vector2(41, -46), Vector2(30, -46), Vector2(48, -46), Vector2(-20, -46)],
	"south": [Vector2(-60, 22), Vector2(-20, 22), Vector2(30, 22), Vector2(54, 58)],
	"east": [Vector2(68, -20), Vector2(70, 0), Vector2(66, 20)],
	"west": [Vector2(-95, 16), Vector2(-100, 13)],
}

static func dist_to_polyline(p: Vector2, pts: Array) -> float:
	var best := 1e9
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, (a + ab * t).distance_to(p))
	return best

static func on_road(x: float, z: float, margin: float = 0.0) -> bool:
	var p := Vector2(x, z)
	for r in ROADS:
		if dist_to_polyline(p, r["pts"]) < r["width"] / 2.0 + margin:
			return true
	return false

static func in_building(x: float, z: float, margin: float = 0.0) -> bool:
	for b in [WALDHUETTE, HOLZAGER]:
		var pos: Vector2 = b["pos"]
		var size: Vector2 = b["size"]
		var d := Vector2(x, z) - pos
		var yaw: float = b["yaw"]
		var l := Vector2(d.x * cos(yaw) + d.y * sin(yaw), -d.x * sin(yaw) + d.y * cos(yaw))
		if absf(l.x) < size.x / 2.0 + margin and absf(l.y) < size.y / 2.0 + margin:
			return true
	return false

static func in_forest(x: float, z: float) -> bool:
	for r in FORESTS.values():
		if (r as Rect2).has_point(Vector2(x, z)):
			return true
	return false

static func ground_height(x: float, z: float) -> float:
	var h := 0.35 * sin(x * 0.07 + 1.0) * cos(z * 0.05) + 0.2 * sin(x * 0.19 + z * 0.13)
	h += -0.004 * x   # the land falls away gently towards the meadow in the east
	# stream bed
	var ds := dist_to_polyline(Vector2(x, z), STREAM)
	if ds < 2.2:
		h -= (1.0 - smoothstep(0.0, 2.2, ds)) * 0.7
	# roads sit on a flattened bed
	for r in ROADS:
		var d := dist_to_polyline(Vector2(x, z), r["pts"])
		var w: float = r["width"] / 2.0 + 1.5
		if d < w:
			var flat := 0.35 * sin(x * 0.07 + 1.0) * cos(z * 0.05) * 0.2 - 0.004 * x
			h = lerpf(flat, h, smoothstep(w - 1.5, w, d))
	return h

static func ground_pos(x: float, z: float) -> Vector3:
	return Vector3(x, ground_height(x, z), z)

# 1 = leaf litter (forest floor and clearing), 0 = meadow grass
static func leaf_weight(x: float, z: float) -> float:
	var w := 0.0
	var p := Vector2(x, z)
	for r in FORESTS.values():
		var rr := (r as Rect2).grow(3.0)
		if rr.has_point(p):
			var edge := minf(minf(p.x - rr.position.x, rr.end.x - p.x), minf(p.y - rr.position.y, rr.end.y - p.y))
			w = maxf(w, smoothstep(0.0, 4.0, edge))
	var c := CLEARING.grow(2.0)
	if c.has_point(p):
		var edge := minf(minf(p.x - c.position.x, c.end.x - p.x), minf(p.y - c.position.y, c.end.y - p.y))
		w = maxf(w, smoothstep(0.0, 3.0, edge))
	if on_road(x, z, 0.6):
		w *= 0.0
	return w

# Areas that must stay free of trees and shrubs
static func is_clear_zone(x: float, z: float) -> bool:
	if on_road(x, z, 2.5):
		return true
	if in_building(x, z, 3.0):
		return true
	if dist_to_polyline(Vector2(x, z), STREAM) < 2.5:
		return true
	if Vector2(x, z).distance_to(FIRE) < 14.0:
		return true
	if Vector2(x, z).distance_to(WELL) < 4.0:
		return true
	return false
