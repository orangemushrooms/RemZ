class_name Door
extends Node3D

const INTERACT_REACH := 2.8
const HOLD_STRENGTH := 160.0
const ACTOR_MARGIN := 0.02
var taken := false # Doors remain interactable after opening.
var label := "Tür"
var width := 2.6
var height := 2.1
var key_id := ""
var main: Node3D
var is_open := false
var moving := false
var body: StaticBody3D
var leaves: Array = []
var _colliders: Array[CollisionShape3D] = []
var _offsets: Array[Transform3D] = []
var _motion: Tween
var _pressure := 0.0
var _forced_cooldown := 0.0
var _pending_collision := false
var _swing_shape: BoxShape3D
var _open_side := -1.0
var center: Vector3:
	get: return global_position
var hp: float:
	get: return 0.0 if is_open else HOLD_STRENGTH - _pressure

# Local x=0 is the doorway; interaction opens the leaves away from the player.
func setup(w: float, h: float, text: String, mat: Material) -> void:
	width = w
	height = h
	label = text
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.15, 0.16, 0.17)
	iron.metallic = 0.75
	iron.roughness = 0.38
	var sides: Array = [-1.0] if width < 1.4 else [-1.0, 1.0]
	var leaf_width := width / sides.size()
	for side: float in sides:
		var hinge := Node3D.new()
		hinge.position.z = side * width / 2.0
		add_child(hinge)
		var offset := Vector3(0, height / 2.0, -side * leaf_width / 2.0)
		var model := WorldModels.create("hut_door_leaf")
		if model:
			# Preserve the precise moving collision slab and hinge location.
			model.rotation.y = side * PI / 2.0
			var bounds := Barricade._bounds(model)
			var fit := Node3D.new()
			fit.add_to_group("render_dynamic")
			hinge.add_child(fit)
			fit.add_child(model)
			fit.scale = Vector3(0.10, height - 0.02, leaf_width - 0.015) / bounds.size
			fit.position = offset - bounds.get_center() * fit.scale
		else:
			_piece(hinge, Vector3(0.10, height - 0.02, leaf_width - 0.015), offset, mat)
			for y: float in [height * 0.22, height * 0.77]:
				_piece(hinge, Vector3(0.13, 0.055, leaf_width - 0.10), Vector3(-0.025, y, offset.z), iron)
			_piece(hinge, Vector3(0.17, 0.14, 0.04), Vector3(-0.06, height * 0.48, -side * (leaf_width - 0.13)), iron)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.12, height, leaf_width)
		cs.shape = shape
		var local_offset := Transform3D(Basis.IDENTITY, offset)
		cs.transform = hinge.transform * local_offset
		body.add_child(cs)
		_colliders.append(cs)
		_offsets.append(local_offset)
		leaves.append([hinge, side])
	_swing_shape = BoxShape3D.new()
	_swing_shape.size = Vector3(leaf_width + 0.12, height + 0.1, width + 0.12)

func _piece(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	mesh.add_to_group("render_dynamic")
	parent.add_child(mesh)

func _ready() -> void:
	add_to_group("hut_doors")
	set_physics_process(false)

func is_locked() -> bool:
	return not key_id.is_empty() and (main == null or main.forest_keys == null or not main.forest_keys.has_key(key_id))

func interaction_point() -> Vector3:
	return to_global(Vector3(0, minf(height * 0.5, 1.2), 0))

func can_interact(player: Node3D) -> bool:
	var eye: Vector3 = player.camera.global_position
	var target := interaction_point()
	if eye.distance_to(target) > INTERACT_REACH:
		return false
	var ray := PhysicsRayQueryParameters3D.create(eye, target, 1 | 8, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == body

func prompt_text() -> String:
	if is_locked():
		return "%s · Verschlossen\nSchlüssel für %s im Wald finden" % [label, ForestKeys.KEYS[key_id]]
	if moving:
		return "%s wird %s …" % [label, "geöffnet" if is_open else "geschlossen"]
	if _forced_cooldown > 0:
		return "%s · Aufgedrückt! Einen Moment warten" % label
	return "[E] %s %s" % [label, "schliessen" if is_open else "öffnen"]

func take(weapons, hud) -> bool:
	if NetSession.is_client():
		NetSession.command("interact", [str(get_meta("coop_id", ""))])
		return false
	var player = weapons.player
	if not player.active or not player.alive or not can_interact(player) or moving:
		return false
	if is_locked():
		hud.message("Schlüssel fehlt: %s\nSuche im Wald. In der Nähe erscheint ein Hinweis." % ForestKeys.KEYS[key_id])
		Sfx.play_at(get_parent(), "door_locked", global_position + Vector3.UP, -8.0)
		return false
	if _forced_cooldown > 0:
		return false
	var excluded: Array[RID] = []
	if not is_open:
		_open_side = 1.0 if to_local(player.global_position).x < 0.0 else -1.0
		# At the closed door the player can touch its collider. The leaves move away,
		# so that contact must not prevent opening; other actors still block the sweep.
		excluded.append(player.get_rid())
	if _swing_blocked(excluded):
		hud.message("Türbereich blockiert.\nHalte den Schwenkbereich frei.")
		return false
	_set_open(not is_open)
	return true

func _swing_blocked(excluded: Array[RID] = []) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _swing_shape
	query.transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(_open_side * width / leaves.size() * 0.5, height * 0.5, 0))
	query.collision_mask = 2 | 4
	query.margin = ACTOR_MARGIN
	query.exclude = excluded
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _set_open(open: bool) -> void:
	if _motion and _motion.is_valid():
		_motion.kill()
	is_open = open
	moving = true
	_pending_collision = false
	for cs in _colliders:
		cs.set_deferred("disabled", true)
	_motion = create_tween().set_parallel().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_motion.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	for leaf in leaves:
		_motion.tween_property(leaf[0], "rotation:y", -leaf[1] * _open_side * 1.65 if open else 0.0, 0.75)
	_motion.chain().tween_callback(_finish_motion)
	set_physics_process(true)
	if open: Sfx.play_at(get_parent(), "door_open", global_position + Vector3.UP, -6.0)
	else: Sfx.play_at(get_parent(), "door_close", global_position + Vector3.UP, -8.0)

func _finish_motion() -> void:
	if not NetSession.is_client() and not is_open and _swing_blocked():
		_set_open(true)
		return
	moving = false
	_pressure = 0.0
	_pending_collision = true
	_sync_collision()

func _sync_collision() -> void:
	_pending_collision = false
	for i in _colliders.size():
		var cs := _colliders[i]
		cs.transform = leaves[i][0].transform * _offsets[i]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = cs.shape
		query.transform = body.global_transform * cs.transform
		query.collision_mask = 2 | 4
		query.margin = ACTOR_MARGIN
		var occupied := not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
		cs.set_deferred("disabled", occupied)
		_pending_collision = _pending_collision or occupied

func _physics_process(delta: float) -> void:
	_forced_cooldown = maxf(0.0, _forced_cooldown - delta)
	if not NetSession.is_client() and moving and not is_open and _swing_blocked():
		_set_open(true)
	elif not moving and _pending_collision:
		_sync_collision()
	if not moving and not _pending_collision and _forced_cooldown <= 0:
		set_physics_process(false)

# Same small defence interface as barricades, for enemies approaching a shut door.
func crosses(a: Vector3, b: Vector3) -> bool:
	if is_open or moving or is_locked():
		return false
	var start := to_local(a + Vector3.UP * 0.8)
	var end := to_local(b + Vector3.UP * 0.8)
	if start.x * end.x >= 0 or absf(end.x - start.x) < 0.001:
		return false
	var hit := start.lerp(end, -start.x / (end.x - start.x))
	return absf(hit.z) <= width * 0.5 and hit.y >= 0 and hit.y <= height

func attack_point(from: Vector3) -> Vector3:
	var local := to_local(from)
	return to_global(Vector3(0.35 if local.x > 0 else -0.35, 0, clampf(local.z, -width * 0.35, width * 0.35)))

func damage(amount: float) -> void:
	if is_open or moving or is_locked():
		return
	_pressure += maxf(amount, 0)
	Sfx.play_at(get_parent(), "wood_hit", global_position + Vector3.UP, -7.0)
	if _pressure >= HOLD_STRENGTH:
		_forced_cooldown = 4.0
		_set_open(true)
		if main and main.player.global_position.distance_to(global_position) < 18:
			main.hud.message("%s wurde aufgedrückt!" % label)
