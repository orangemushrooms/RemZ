extends RefCounted

const Recipes = preload("res://scripts/brew_recipes.gd")

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
	var bounds := Map.BOUNDS.grow(-4)
	# Little groups of two, with a guaranteed mix of all six species across the fields.
	var kinds := Recipes.FLOWERS.keys()
	var patch_index := 0
	for row in ceili(bounds.size.y / 22.0):
		for column in ceili(bounds.size.x / 22.0):
			var origin := bounds.position + Vector2(column, row) * 22.0
			for attempt in 10:
				var at := origin + Vector2(rng.randf_range(2, 20), rng.randf_range(2, 20))
				if not clear_ground(game, at): continue
				var kind: String = kinds[patch_index % kinds.size()]
				patch_index += 1
				result.append({"at": at, "kind": kind, "yaw": rng.randf() * TAU})
				var beside := at + Vector2(rng.randf_range(0.9, 1.8), rng.randf_range(-1.5, 1.5))
				if clear_ground(game, beside): result.append({"at": beside, "kind": kind, "yaw": rng.randf() * TAU})
				break
	return result

static func build(game: Node3D) -> void:
	for entry in locations(game):
		var spec: Dictionary = Recipes.FLOWERS[entry.kind]
		var loot := Loot.new()
		loot.setup("flower", entry.kind, spec.name)
		loot.name = "FieldFlower_%d" % game.loots.size()
		game.add_child(loot)
		loot.position = Map.ground_pos(entry.at.x, entry.at.y)
		loot.rotation.y = entry.yaw
		var visual := WorldModels.create(spec.model, spec.height)
		if visual:
			loot.add_child(visual)
			# The violet source includes a tied base; bury it so only living foliage shows.
			if entry.kind == "violet_bell": visual.position.y = -0.16
			for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.visibility_range_end = 65.0
		game.loots.append(loot)
