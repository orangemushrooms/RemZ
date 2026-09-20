class_name ForestKeys
extends Node

const KEYS := {"waldhuette": "Waldhütte", "holzlager": "Holzlager"}
const HINT_RADIUS := 16.0
const SPAWN_CHANCE := 0.30
var main: Node3D
var owned: Dictionary = {}
var spawned: Array[ForestKey] = []
var hint: KeyHint
var _hint_time := 0.0
var _spawn_random := RandomNumberGenerator.new()
var _last_spawn_phase := ""

func setup(game: Node3D) -> void:
	main = game
	hint = KeyHint.new()
	main.hud.fps_label.get_parent().add_child(hint)
	# Keep start/pause overlays above the discovery marker.
	hint.get_parent().move_child(hint, 0)

func has_key(id: String) -> bool:
	return owned.get(id, false)

func populate() -> bool:
	if not spawned.is_empty(): return true
	var random := _spawn_random
	random.randomize()
	for flag in main._flags:
		if flag.begins_with("--key-seed="):
			random.seed = int(flag.trim_prefix("--key-seed="))
	var points := choose_spawn_points(random)
	if points.size() != KEYS.size():
		push_error("FOREST_KEYS: No reachable forest locations found.")
		return false
	var ids := KEYS.keys()
	for i in ids.size():
		var key := ForestKey.new()
		key.key_id = ids[i]
		key.manager = self
		main.add_child(key)
		key.global_position = points[i]
		key.rotation.y = random.randf_range(0, TAU)
		# Keep stable network IDs and empty stumps even when this run has no key.
		# Clients wait for the host's loot snapshot instead of making their own roll.
		if NetSession.is_client() or (not "--all-forest-keys" in main._flags and not roll_spawn(random)):
			key.taken = true
			key.pickup_visual.hide()
		spawned.append(key)
		main.loots.append(key)
	_last_spawn_phase = "%d:%s" % [main.waves.wave, main.waves.phase]
	return true

func refresh_availability() -> void:
	if not main or not main.started or main.over or get_tree().paused or NetSession.is_client(): return
	if main.waves.phase not in ["idle", "spawning"] or spawned.is_empty(): return
	var phase_id := "%d:%s" % [main.waves.wave, main.waves.phase]
	if phase_id == _last_spawn_phase: return
	_last_spawn_phase = phase_id
	for key in spawned:
		if not is_instance_valid(key) or not key.taken or has_key(key.key_id): continue
		if roll_spawn(_spawn_random):
			key.taken = false
			key.pickup_visual.show()

static func roll_spawn(random: RandomNumberGenerator) -> bool:
	return random.randf() < SPAWN_CHANCE

# Called once after navigation synchronizes; no pathfinding or world scans per frame.
func choose_spawn_points(random: RandomNumberGenerator) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var nav: RID = main.nav_region.get_navigation_map()
	var start := NavigationServer3D.map_get_closest_point(nav, Map.ground_pos(Map.PLAYER_START.x, Map.PLAYER_START.y))
	var capsule := CapsuleShape3D.new()
	var diagnostic := [0, 0, 0, 0]
	capsule.radius = 0.55
	capsule.height = 1.6
	for attempt in 2400:
		var road: Dictionary = Map.ROADS[random.randi_range(0, Map.ROADS.size() - 1)]
		var segment := random.randi_range(0, road.pts.size() - 2)
		var a: Vector2 = road.pts[segment]
		var b: Vector2 = road.pts[segment + 1]
		var normal := (b - a).normalized().orthogonal()
		var candidate: Vector2 = a.lerp(b, random.randf_range(0.05, 0.95)) + normal * (road.width * 0.5 + random.randf_range(3, 10)) * (-1 if random.randf() < 0.5 else 1)
		if not valid_forest_point(candidate):
			continue
		diagnostic[0] += 1
		var ground := Map.ground_pos(candidate.x, candidate.y)
		var point := NavigationServer3D.map_get_closest_point(nav, ground)
		if Vector2(point.x, point.z).distance_to(candidate) > 0.85 or absf(point.y - ground.y) > 1.2:
			continue
		diagnostic[1] += 1
		var too_close := false
		for previous in result:
			if previous.distance_to(ground) < 30:
				too_close = true
		if too_close:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 1.15)
		query.collision_mask = 1 | 8
		if not main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		diagnostic[2] += 1
		var path := NavigationServer3D.map_get_path(nav, start, point, true)
		if path.is_empty() or path[path.size() - 1].distance_to(point) > 0.8:
			continue
		diagnostic[3] += 1
		result.append(ground)
		if result.size() == KEYS.size():
			break
	if result.size() != KEYS.size():
		print("KEY_SPAWN_DIAGNOSTIC ", diagnostic, " nav_iteration=", NavigationServer3D.map_get_iteration_id(nav), " start=", start, " region_count=", NavigationServer3D.map_get_regions(nav).size(), " polygons=", main.nav_region.navigation_mesh.get_polygon_count(), " active=", NavigationServer3D.map_is_active(nav), " bounds=", main.nav_region.get_bounds())
	return result

func valid_forest_point(point: Vector2) -> bool:
	var distance := point.distance_to(Map.PLAYER_START)
	return distance >= 24 and distance <= 115 and Map.BOUNDS.grow(-5).has_point(point) and Map.in_forest(point.x, point.y) and not Map.on_road(point.x, point.y, 2.0) and not Map.in_building(point.x, point.y, 8.0) and not Map.in_clearing(point.x, point.y) and Map.ground_normal(point.x, point.y).y > 0.86

func collect(key: ForestKey) -> void:
	if key.taken or has_key(key.key_id):
		return
	key.taken = true
	owned[key.key_id] = true
	key.pickup_visual.hide()
	hint.update_target(null, main.player)
	main.hud.message("Schlüssel gefunden: %s\nAlle Türen dieser Hütte sind jetzt bedienbar. [I] Inventar" % KEYS[key.key_id], 4.0)
	Sfx.play(self, "key_pickup", -6.0)

func _process(delta: float) -> void:
	refresh_availability()
	_hint_time -= delta
	if _hint_time > 0 or not main:
		return
	_hint_time = 0.1
	var closest: ForestKey
	var distance := HINT_RADIUS
	if main.started and not main.over and main.player.active:
		for key in spawned:
			if not is_instance_valid(key) or key.taken:
				continue
			var d: float = main.player.global_position.distance_to(key.global_position)
			if d < distance:
				distance = d
				closest = key
	hint.update_target(closest, main.player)
