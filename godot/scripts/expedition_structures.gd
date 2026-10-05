extends Node3D
## Functional cover, a swing gate, and a ramp-accessible observation platform.
const COSTS := {"gate": 100, "embrasure": 90, "observation": 180}
const NAMES := {"gate": "Field gate", "embrasure": "Firing wall", "observation": "Observation platform"}
var director: RunDirector
var items: Dictionary = {}
var nodes: Dictionary = {}
var next_id := 1
var _clock := 0.0

func setup(run: RunDirector) -> void:
	director = run

func clear() -> void:
	for node in nodes.values():
		if is_instance_valid(node): node.queue_free()
	items.clear()
	nodes.clear()
	next_id = 1

func placement_error(p: Player, kind: String, at: Vector3, yaw: float) -> String:
	var game := director.game
	if director.config.region != "planes" or not COSTS.has(kind): return "This structure is available on Planes."
	if items.size()+game.barricades.size() >= 40: return "Maximum 40 field fortifications."
	if not at.is_finite() or not is_finite(yaw): return "Invalid building position."
	var bounds := Vector2(2.2, 6.8) if kind == "observation" else Vector2(2.2, 1)
	var basis := Basis(Vector3.UP, yaw)
	var low := INF
	var high := -INF
	for x in [-bounds.x, bounds.x]:
		for z in [-bounds.y, bounds.y]:
			var corner := at+basis*Vector3(x, 0, z)
			if not preload("res://scripts/planes_boundary.gd").contains(Vector2(corner.x, corner.z)): return "Keep the complete structure inside the playable area."
			var height := Map.ground_height(corner.x, corner.z)
			low = minf(low, height)
			high = maxf(high, height)
	if high-low > 0.6: return "Choose more level ground."
	if p.global_position.distance_to(at) > 9 or p.global_position.distance_to(at) < 3: return "Build between three and nine metres away."
	if at.distance_to(director.camp()) < 9: return "Keep camp access clear."
	for site in director.sites:
		if at.distance_to(site.at) < 8: return "Keep objective access clear."
	for npc in game.progression.SITES:
		var point: Vector2 = game.progression.SITES[npc]
		if Vector2(at.x, at.z).distance_to(point) < 7: return "Keep trader access clear."
	var shape := BoxShape3D.new()
	shape.size = Vector3(bounds.x*2, 3.2, bounds.y*2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(basis, at+Vector3.UP*1.8)
	query.collision_mask = 1|2|4|8
	query.exclude = [p.get_rid()]
	for terrain in get_tree().get_nodes_in_group("terrain_ground"):
		if terrain is CollisionObject3D: query.exclude.append(terrain.get_rid())
	if not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return "Building site occupied."
	var ray := PhysicsRayQueryParameters3D.create(p.global_position+Vector3.UP*1.7, at+Vector3.UP, 1|8, [p.get_rid()])
	if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return "No clear view of the building site."
	return ""

func build(p: Player, kind: String) -> String:
	if NetSession.is_client() or not COSTS.has(kind): return "Invalid expedition request."
	var forward := -p.global_basis.z
	forward.y = 0
	var distance := 8.5 if kind == "observation" else 5.0
	var at := p.global_position+forward.normalized()*distance
	at = Map.ground_pos(at.x, at.z)
	var error := placement_error(p, kind, at, p.rotation.y)
	if not error.is_empty(): return error
	if p.score < COSTS[kind]: return "Not enough Rem Dollars."
	p.add_score(-COSTS[kind])
	var id := next_id
	next_id += 1
	items[id] = {"id": id, "kind": kind, "at": at, "yaw": p.rotation.y, "hp": 600.0, "open": false, "owner": p.peer_id}
	_create(id)
	director.game.stats.barricades_built += 1
	director.game.progression.peer_event(p.peer_id, "built_wall")
	return "Fortification built."

func nearest(p: Player) -> String:
	var distance := 3.5
	var result := ""
	for id in items:
		var d := p.global_position.distance_to(items[id].at)
		if d < distance:
			distance = d
			result = "structure_%d" % id
	return result

func interact(p: Player, id: int, action: String) -> String:
	if NetSession.is_client() or not items.has(id) or not director._near(p, items[id].at, 4): return "Move closer to the fortification."
	var data: Dictionary = items[id]
	if action == "repair":
		if data.hp >= 600: return "Fortification already repaired."
		if p.score < 30: return "Not enough Rem Dollars."
		p.add_score(-30)
		data.hp = 600.0
		director.support(p.peer_id, "repairs", "structure:%d:%d" % [id, int(director.elapsed/30)])
		return "Fortification repaired."
	if action != "use": return "Invalid expedition request."
	if data.kind == "gate":
		if data.open:
			var shape := BoxShape3D.new()
			shape.size = Vector3(3.3, 2.2, 0.4)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(Basis(Vector3.UP, data.yaw), data.at+Vector3.UP)
			query.collision_mask = 2|4
			if not director.game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return "Keep the gate opening clear before closing it."
		data.open = not data.open
		_update_gate(id)
		return "Gate opened." if data.open else "Gate closed."
	return "Use the ramp to reach the observation platform." if data.kind == "observation" else "Fire through the opening above the cover."

func _box(root: Node3D, size: Vector3, position: Vector3, color: Color, angle := 0.0, collide := true) -> StaticBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := DefenceTower.piece(root, mesh, position, DefenceTower.material(color))
	visual.rotation.x = angle
	if not collide: return null
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = position
	body.rotation.x = angle
	root.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _create(id: int) -> void:
	var data: Dictionary = items[id]
	var root := Node3D.new()
	add_child(root)
	root.position = data.at
	root.rotation.y = data.yaw
	nodes[id] = root
	var color := Color(0.25, 0.3, 0.24)
	if data.kind == "gate":
		for x in [-1.8, 1.8]: _box(root, Vector3(0.25, 2.3, 0.3), Vector3(x, 1.15, 0), color)
		var door := Node3D.new()
		door.name = "Door"
		door.position.x = -1.6
		root.add_child(door)
		_box(door, Vector3(3.2, 2, 0.18), Vector3(1.6, 1, 0), color)
		_update_gate(id)
	elif data.kind == "embrasure":
		_box(root, Vector3(3.6, 1.05, 0.45), Vector3(0, 0.525, 0), color)
		for x in [-1.5, 1.5]: _box(root, Vector3(0.6, 1.15, 0.45), Vector3(x, 1.625, 0), color)
		_box(root, Vector3(3.6, 0.25, 0.45), Vector3(0, 2.325, 0), color)
	else:
		_box(root, Vector3(3.5, 0.18, 3.5), Vector3(0, 2, 1.5), color)
		for x in [-1.55, 1.55]:
			for z in [0, 3]: _box(root, Vector3(0.18, 2, 0.18), Vector3(x, 1, z), color)
		# The ramp overlaps the deck surface; its leading edge must not form a step.
		_box(root, Vector3(2.0, 0.15, 6.862), Vector3(0, 1.061, -3.25), color, -atan(2.2/6.5))
		for x in [-1.65, 1.65]: _box(root, Vector3(0.12, 0.9, 3.5), Vector3(x, 2.5, 1.5), color)
		_box(root, Vector3(3.5, 0.9, 0.12), Vector3(0, 2.5, 3.2), color)
	var caption := Label3D.new()
	caption.name = "Caption"
	caption.position = Vector3(0, 3.6, 0)
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size = 28
	caption.pixel_size = 0.01
	root.add_child(caption)
	_update_caption(id)

func _update_gate(id: int) -> void:
	if not nodes.has(id): return
	var door: Node3D = nodes[id].get_node("Door")
	door.rotation.y = PI*0.5 if items[id].open else 0.0
	# The swung leaf remains physical; the centre passage is now open.

func _update_caption(id: int) -> void:
	var label: Label3D = nodes[id].get_node("Caption")
	label.text = Lang.t("%s · %d / 600", [Lang.t(NAMES[items[id].kind]), ceili(items[id].hp)])

func _process(delta: float) -> void:
	if not director or NetSession.is_client() or director.game.over or not director.game.started: return
	_clock += delta
	if _clock < 0.25: return
	var step := _clock
	_clock = 0.0
	for id in items.keys():
		var data: Dictionary = items[id]
		for enemy: Zombie in director._enemies():
			if enemy.global_position.distance_to(data.at) < 2.8: data.hp -= step*(25 if Zombie.is_boss_kind(enemy.net_kind) else 5)
		if data.hp <= 0:
			nodes[id].queue_free()
			nodes.erase(id)
			items.erase(id)
		else: _update_caption(id)

func snapshot() -> Array:
	return items.values().duplicate(true)

func apply_snapshot(states: Array) -> void:
	var seen := {}
	for data: Dictionary in states:
		var id := int(data.id)
		seen[id] = true
		var fresh := not items.has(id)
		items[id] = data.duplicate(true)
		next_id = maxi(next_id, id+1)
		if fresh: _create(id)
		elif data.kind == "gate": _update_gate(id)
		_update_caption(id)
	for id in items.keys():
		if not seen.has(id):
			items.erase(id)
			nodes[id].queue_free()
			nodes.erase(id)
