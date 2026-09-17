# Birkenhof layout shared by world building, spawning and AI. +X = east, +Z = south (downhill).
class_name Map

const ROAD_WIDTH := 3.6
const ROAD_START := -38.0
const ROAD_END := 120.0
const BAY := Rect2(-7.5, -58.0, 15.0, 20.0)      # asphalt parking bay (x, z, w, d)
const STRIP := Rect2(7.5, -60.0, 6.0, 20.0)      # grass strip with the benches
const BOUNDS := Rect2(-70.0, -95.0, 125.0, 223.0)

const BARRICADES := [
	{ "id": "south", "name": "Weg (Süd)", "pos": Vector2(0.2, -30.0), "yaw": 0.0, "segments": 2 },
	{ "id": "east", "name": "Waldrand (Ost)", "pos": Vector2(13.8, -50.0), "yaw": PI / 2.0, "segments": 2 },
	{ "id": "north", "name": "Kiesweg (Nord)", "pos": Vector2(-9.5, -63.0), "yaw": 0.35, "segments": 2 },
]

const SPAWNS := {
	"south": [Vector2(0, 30), Vector2(1, 45), Vector2(-1, 60), Vector2(1, 75)],
	"east": [Vector2(30, -52), Vector2(34, -44), Vector2(28, -36), Vector2(36, -50)],
	"north": [Vector2(-14, -88), Vector2(-11, -92), Vector2(-17, -85), Vector2(-9, -90)],
}

static func road_x(z: float) -> float:
	var x := 1.6 * sin(z / 40.0) + 0.5 * sin(z / 13.0)
	if z < -20.0:
		x -= (-20.0 - z) * 0.03
	return x

static func track_x(z: float) -> float:
	return -9.0 + (-58.0 - z) * 0.18

static func ground_height(x: float, z: float) -> float:
	var zz := maxf(z, ROAD_START)
	var h := -(zz - ROAD_START) * 0.085
	if z > 95.0:
		h -= (z - 95.0) * 0.03
	if z < -60.0:
		h += (-60.0 - z) * 0.02
	var dx := x - road_x(z)
	var in_bay := z < -34.0 and x > -12.0 and x < 16.0
	var flat := 0.0 if in_bay else clampf(minf(z + 34.0, 30.0) / 10.0, 0.0, 1.0)
	if dx < -2.0:
		var k := -dx - 2.0
		var f := minf(1.0, k / 8.0)
		h -= flat * (k * 0.06 + f * (sin(x * 0.11) * 0.4 + sin(z * 0.07 + x * 0.05) * 0.5))
	if dx > 2.0:
		var k := dx - 2.0
		var f := minf(1.0, k / 8.0)
		h += flat * (k * 0.03 + f * sin(x * 0.19 + z * 0.13) * 0.25)
	return h

static func ground_pos(x: float, z: float) -> Vector3:
	return Vector3(x, ground_height(x, z), z)

# Areas that must stay free of trees and bushes: road, bay + bench strip, gravel track, east approach
static func is_clear_zone(x: float, z: float) -> bool:
	var rw := ROAD_WIDTH / 2.0
	if z > ROAD_START - 3.0 and absf(x - road_x(z)) < rw + 2.2:
		return true
	if x > BAY.position.x - 2.0 and x < STRIP.end.x + 1.0 and z > BAY.position.y - 3.0 and z < BAY.end.y + 3.0:
		return true
	if z < -46.0 and absf(x - track_x(z)) < 3.2:
		return true
	if x > 13.0 and x < 40.0 and absf(z - (-50.0 + (x - 13.0) * 0.2)) < 2.6:
		return true
	return false
