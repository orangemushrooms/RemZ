extends RefCounted

const Recipes = preload("res://scripts/brew_recipes.gd")
const MIN_SPACING := 2.2
const CANDIDATE_AREA := 28.0

static func clear_ground(game: Node3D, point: Vector2) -> bool:
	if not Map.BOUNDS.grow(-3).has_point(point): return false
	if Map.meadow_weight(point.x, point.y) < 0.72 or Map.leaf_weight(point.x, point.y) > 0.2: return false
	if Map.is_clear_zone(point.x, point.y) or Map.ground_normal(point.x, point.y).y < 0.83: return false
	if game.cornfield.field_ground(point): return false
	if not Map.POND.is_empty() and point.distance_to(Map.POND.pos) < float(Map.POND.r) + 3: return false
	for tree in Map.TREES:
		if point.distance_squared_to(Vector2(tree[0], tree[1])) < 9: return false
	for npc: Dictionary in Progression.NPCS.values():
		if point.distance_to(npc.pos) < 4: return false
	return true

static func locations(game: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 927461
	var appearance := RandomNumberGenerator.new()
	appearance.seed = 927462
	var patches := FastNoiseLite.new()
	patches.seed = 927463
	patches.frequency = 0.025
	patches.fractal_octaves = 3
	var bounds := Map.BOUNDS.grow(-4)
	var kinds := Recipes.FLOWERS.keys()
	var occupied := {}
	# Random candidates cover the whole meadow without visible rows or paired offsets.
	# Broad density changes leave loose groups and open gaps, with individual flowers
	# between them. The spatial index only prevents crowding; it does not place plants.
	for attempt in ceili(bounds.get_area() / CANDIDATE_AREA):
		var at := bounds.position + Vector2(rng.randf() * bounds.size.x, rng.randf() * bounds.size.y)
		var density := smoothstep(-0.5, 0.5, patches.get_noise_2d(at.x, at.y))
		if rng.randf() > lerpf(0.25, 0.85, density): continue
		if not clear_ground(game, at) or not _has_space(at, occupied): continue
		var cell := Vector2i(floori(at.x / MIN_SPACING), floori(at.y / MIN_SPACING))
		if not occupied.has(cell): occupied[cell] = []
		occupied[cell].append(at)
		var kind: String = kinds[appearance.randi_range(0, kinds.size() - 1)]
		result.append({"at": at, "kind": kind, "yaw": appearance.randf() * TAU, "size": appearance.randf_range(0.8, 1.2)})
	return result

static func _has_space(at: Vector2, occupied: Dictionary) -> bool:
	var cell := Vector2i(floori(at.x / MIN_SPACING), floori(at.y / MIN_SPACING))
	for z in range(-1, 2):
		for x in range(-1, 2):
			for other: Vector2 in occupied.get(cell + Vector2i(x, z), []):
				if at.distance_squared_to(other) < MIN_SPACING * MIN_SPACING: return false
	return true

static func build(game: Node3D) -> void:
	for entry in locations(game):
		var spec: Dictionary = Recipes.FLOWERS[entry.kind]
		var loot := Loot.new()
		loot.setup("flower", entry.kind, spec.name)
		loot.name = "FieldFlower_%d" % game.loots.size()
		game.add_child(loot)
		loot.position = Map.ground_pos(entry.at.x, entry.at.y)
		loot.rotation.y = entry.yaw
		var visual := WorldModels.create(spec.model, spec.height * entry.size)
		if visual:
			loot.add_child(visual)
			# The violet source includes a tied base; bury it so only living foliage shows.
			if entry.kind == "violet_bell": visual.position.y = -0.16 * entry.size
			for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.visibility_range_end = 65.0
		game.loots.append(loot)
