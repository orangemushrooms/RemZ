extends Node3D
## Four-metre wheat cells, fixed particle pool, four damage/spread ticks per second.
## No per-stalk nodes, physics bodies, lights or per-frame crop iteration.
const CELL := 4.0
const MAX_ACTIVE := 16
const BURN_SECONDS := 10.0
const TICK := 0.25
var crops: Node3D
var game: Node3D
var wheat: Dictionary = {}
var active: Dictionary = {}
var burned: Dictionary = {}
var effects: Array[CPUParticles3D] = []
var mask: Image
var texture: ImageTexture
var origin := Vector2.ZERO
var clock := 0.0

func setup(field: Node3D) -> void:
	crops = field
	game = field.game
	origin = Map.extent().position
	var size := (Map.extent().size / CELL).ceil() + Vector2.ONE
	mask = Image.create(int(size.x), int(size.y), false, Image.FORMAT_R8)
	texture = ImageTexture.create_from_image(mask)
	var material: ShaderMaterial = field.wind.duplicate()
	material.set_shader_parameter("burn_enabled", true)
	material.set_shader_parameter("burn_mask", texture)
	material.set_shader_parameter("burn_origin", origin)
	material.set_shader_parameter("burn_size", size * CELL)
	# Use construction data, not renderer readback (headless servers have no MultiMesh data).
	wheat = field.wheat_fire_cells
	for batch in field.batches:
		if batch.get_meta("kind") != "wheat": continue
		batch.material_override = material
	for i in MAX_ACTIVE:
		var particles := preload("res://scripts/elemental_effects.gd").particles("fire", 1.7, 1.0)
		particles.amount = 28
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = Vector3(1.7, 0.15, 1.7)
		particles.visibility_range_end = 110
		particles.emitting = false
		add_child(particles)
		effects.append(particles)

func cell_at(pos: Vector3) -> Vector2i:
	return Vector2i(((Vector2(pos.x, pos.z) - origin) / CELL).floor())

func ignite(pos: Vector3, radius: float, peer: int, weapon: String) -> void:
	if NetSession.is_client() or not game.survival_active: return
	if absf(pos.y - Map.ground_height(pos.x, pos.z)) > radius + 1.5: return
	var center := cell_at(pos)
	var reach := ceili(radius / CELL)
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var cell := center + Vector2i(x, y)
			if not wheat.has(cell): continue
			var at: Vector3 = wheat[cell]
			if Vector2(at.x-pos.x, at.z-pos.z).length() <= radius + 1.0:
				_light(cell, peer, weapon)

func _light(cell: Vector2i, peer: int, weapon: String) -> void:
	if active.size() >= MAX_ACTIVE or burned.has(cell) or not wheat.has(cell): return
	active[cell] = {"age": 0.0, "peer": peer, "weapon": weapon, "spread": false}
	burned[cell] = true
	mask.set_pixelv(cell, Color.WHITE)
	texture.update(mask)

func _process(delta: float) -> void:
	if not game or not game.survival_active: return
	clock += delta
	if clock < TICK: return
	var elapsed := clock
	clock = 0.0
	if not NetSession.is_client():
		for cell: Vector2i in active.keys():
			var fire: Dictionary = active[cell]
			fire.age += elapsed
			if fire.age >= BURN_SECONDS:
				active.erase(cell)
				continue
			if fire.age >= 2.0 and not fire.spread:
				fire.spread = true
				# At most two neighbours per burning cell; roads and gaps have no fuel.
				var count := 0
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = cell + offset
					if wheat.has(next) and not burned.has(next):
						_light(next, int(fire.peer), str(fire.weapon))
						count += 1
						if count == 2: break
		if not active.is_empty() and game.zombies_root:
			for zombie in game.zombies_root.get_children():
				if not zombie is Zombie or not zombie.alive: continue
				var cell := cell_at(zombie.global_position)
				if not active.has(cell): continue
				var fire: Dictionary = active[cell]
				game.weapons.specials.ignite(zombie, "fire", 2.0, int(fire.peer), str(fire.weapon))
	_update_effects()

func _update_effects() -> void:
	var nearby: Array = active.keys()
	nearby.sort_custom(func(a, b): return wheat[a].distance_squared_to(game.player.position) < wheat[b].distance_squared_to(game.player.position))
	for i in effects.size():
		var visible_fire: bool = i < nearby.size() and wheat[nearby[i]].distance_squared_to(game.player.position) < 110.0 * 110.0
		if visible_fire: effects[i].position = wheat[nearby[i]] + Vector3.UP * 0.2
		effects[i].emitting = visible_fire

func reset_run() -> void:
	active.clear()
	burned.clear()
	clock = 0.0
	mask.fill(Color.BLACK)
	texture.update(mask)
	for effect in effects: effect.emitting = false

func snapshot() -> Dictionary:
	var cells := PackedVector2Array()
	for cell: Vector2i in burned: cells.append(Vector2(cell))
	return {"burned": cells, "active": active.duplicate(true)}

func apply_snapshot(data: Dictionary) -> void:
	var cells: PackedVector2Array = data.get("burned", PackedVector2Array())
	if cells.size() < burned.size(): reset_run()
	var changed := false
	for point in cells:
		var cell := Vector2i(point)
		if not wheat.has(cell) or burned.has(cell): continue
		burned[cell] = true
		mask.set_pixelv(cell, Color.WHITE)
		changed = true
	if changed: texture.update(mask)
	active = data.get("active", {}).duplicate(true)
	_update_effects()
