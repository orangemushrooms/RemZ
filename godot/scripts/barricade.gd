# A complete defence line: one purchase, continuous models and terrain-following collision.
class_name Barricade
extends Node3D

signal changed

const COST_BUILD := 50
const COST_REPAIR := 25
const MAX_LEVEL := 3
const SEGMENT_LENGTH := 3.2
const HEIGHT := 1.55
const BUILD_REACH := 6.0
const MODEL := preload("res://assets/models/barricade.glb")
const PLAN_COLOR := Color(1.0, 0.16, 0.12)
const BUILT_COLOR := Color(0.25, 0.91, 0.65)

var slot: Dictionary
var level := 0
var hp := 0.0
var center: Vector3
var half_len: float
var dir2: Vector2
var normal2: Vector2
var body: StaticBody3D
var visual: Node3D
var hud: Hud
var preview: Node3D
var footprint: Node3D
var _line_material: StandardMaterial3D
var _segment_transforms: Array[Transform3D] = []
var _focused := false

func setup(s: Dictionary, h: Hud) -> void:
	slot = s
	hud = h
	var p: Vector2 = s["pos"]
	center = Map.ground_pos(p.x, p.y)
	half_len = int(s["segments"]) * SEGMENT_LENGTH * 0.5
	var yaw: float = s["yaw"]
	dir2 = Vector2(cos(yaw), -sin(yaw))
	normal2 = Vector2(sin(yaw), cos(yaw))
	position = center
	rotation.y = yaw

func _ready() -> void:
	body = StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.add_to_group("barricade")
	add_child(body)
	visual = Node3D.new()
	add_child(visual)
	preview = Node3D.new()
	preview.name = "WholeLinePreview"
	add_child(preview)
	footprint = Node3D.new()
	add_child(footprint)
	_line_material = _marker_material(PLAN_COLOR, 1.0)
	var ghost := _marker_material(PLAN_COLOR, 0.23)
	for i in int(slot["segments"]):
		var along := (i - (int(slot["segments"]) - 1) * 0.5) * SEGMENT_LENGTH
		var a := point_at(along - SEGMENT_LENGTH * 0.5)
		var b := point_at(along + SEGMENT_LENGTH * 0.5)
		var slope := atan2(b.y - a.y, SEGMENT_LENGTH)
		var frame := Transform3D(Basis(Vector3.BACK, slope), Vector3(along, (a.y + b.y) * 0.5 - center.y, 0))
		_segment_transforms.append(frame)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(SEGMENT_LENGTH + 0.06, HEIGHT, 0.9)
		shape.shape = box
		shape.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT * 0.5 - 0.06, 0))
		shape.disabled = true
		body.add_child(shape)
		var planned := _make_segment()
		planned.transform = frame
		_override_preview(planned, ghost)
		preview.add_child(planned)
	# Short strips follow the terrain between the model endpoints too.
	var steps := ceili(half_len * 2.0 / 0.4)
	for i in steps:
		for side in [-0.6, 0.6]:
			var a := _ground_local(lerpf(-half_len, half_len, float(i) / steps), side) + Vector3.UP * 0.07
			var b := _ground_local(lerpf(-half_len, half_len, float(i + 1) / steps), side) + Vector3.UP * 0.07
			_add_bar(footprint, a, b, 0.045, _line_material)
	for along in [-half_len, half_len]:
		var a := _ground_local(along, -0.6) + Vector3.UP * 0.07
		var b := _ground_local(along, 0.6) + Vector3.UP * 0.07
		_add_bar(footprint, a, b, 0.06, _line_material)
		_add_bar(footprint, (a + b) * 0.5, (a + b) * 0.5 + Vector3.UP * 2.1, 0.04, _line_material)
	_batch_footprint()
	rebuild()

func _batch_footprint() -> void:
	# Every ground strip and endpoint shares a single draw call.
	var pieces := footprint.get_children()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = pieces.size()
	for i in pieces.size():
		var piece: MeshInstance3D = pieces[i]
		batch.set_instance_transform(i, piece.transform.scaled_local(piece.mesh.size))
		piece.free()
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batch
	instance.material_override = _line_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprint.add_child(instance)

func point_at(along: float) -> Vector3:
	return Map.ground_pos(center.x + dir2.x * along, center.z + dir2.y * along)

func _ground_local(along: float, side: float) -> Vector3:
	var p := Map.ground_pos(center.x + dir2.x * along + normal2.x * side, center.z + dir2.y * along + normal2.y * side)
	return Vector3(along, p.y - center.y, side)

static func _bounds(node: Node3D, parent_transform := Transform3D.IDENTITY) -> AABB:
	var xf := parent_transform * node.transform
	var bounds := AABB()
	if node is MeshInstance3D and node.mesh:
		bounds = xf * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _bounds(child, xf)
			if child_bounds.has_volume():
				bounds = bounds.merge(child_bounds) if bounds.has_volume() else child_bounds
	return bounds

func _make_segment() -> Node3D:
	var holder := Node3D.new()
	var fit := Node3D.new()
	var model: Node3D = MODEL.instantiate()
	holder.add_child(fit)
	fit.add_child(model)
	var bounds := _bounds(model)
	fit.scale = Vector3((SEGMENT_LENGTH + 0.06) / maxf(bounds.size.x, 0.001), HEIGHT / maxf(bounds.size.y, 0.001), 0.8 / maxf(bounds.size.z, 0.001))
	fit.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit.scale - Vector3.UP * 0.06
	return holder

static func _marker_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color, alpha)
	# Road ribbons blend after opaque geometry at priority 1. Draw both guides and
	# ghosts afterwards, or the road incorrectly erases the middle of the preview.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 3
	return mat

static func _override_preview(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_override_preview(child, mat)

static func _add_bar(parent: Node3D, a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, a.distance_to(b), width)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = (a + b) * 0.5
	mesh.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	parent.add_child(mesh)

func max_hp() -> float:
	return level * 300.0

func rebuild() -> void:
	for child in visual.get_children():
		visual.remove_child(child)
		child.queue_free()
	for shape: CollisionShape3D in body.get_children():
		shape.set_deferred("disabled", level == 0)
	if level > 0:
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.21, 0.23, 0.22)
		metal.metallic = 0.75
		metal.roughness = 0.65
		for frame in _segment_transforms:
			var model := _make_segment()
			model.transform = frame
			visual.add_child(model)
			for reinforcement in level - 1:
				var y := 0.48 + reinforcement * 0.65
				for side in [-0.43, 0.43]:
					_add_bar(model, Vector3(-SEGMENT_LENGTH * 0.5, y, side), Vector3(SEGMENT_LENGTH * 0.5, y, side), 0.095, metal)
	_update_preview()
	changed.emit()

func set_preview(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	_update_preview()

func _update_preview() -> void:
	footprint.visible = _focused
	preview.visible = _focused and level == 0
	_line_material.albedo_color = BUILT_COLOR if level > 0 else PLAN_COLOR

func build() -> bool:
	if level >= MAX_LEVEL:
		return false
	level += 1
	hp = max_hp()
	rebuild()
	var scene := get_tree().current_scene
	if "achievements" in scene and scene.achievements:
		scene.achievements.event("barricades")
	if "stats" in scene and scene.stats:
		scene.stats.barricades_built += 1
	return true

func repair() -> bool:
	if level == 0 or hp >= max_hp():
		return false
	hp = max_hp()
	changed.emit()
	return true

func damage(n: float) -> void:
	if hp <= 0.0 or n <= 0.0:
		return
	# Reinforced lines absorb pressure as well as having more structural health.
	hp = maxf(0.0, hp - n / (1.0 + 0.45 * (level - 1)))
	if hp <= 0.0:
		level = 0
		hud.message("Barrikade %s durchbrochen!" % slot["name"], 2.0)
		Sfx.play_at(get_parent(), "barricade_break", center, 0.0)
		rebuild()
	else:
		Sfx.play_at(get_parent(), "wood", center, -4.0)
		changed.emit()

func _local(p: Vector3) -> Vector2:
	var dx := p.x - center.x
	var dz := p.z - center.z
	return Vector2(dx * dir2.x + dz * dir2.y, dx * normal2.x + dz * normal2.y)

func distance_to_line(p: Vector3) -> float:
	return p.distance_to(attack_point(p))

func crosses(a: Vector3, b: Vector3) -> bool:
	var la := _local(a)
	var lb := _local(b)
	if signf(la.y) == signf(lb.y):
		return false
	var t := la.y / (la.y - lb.y)
	return absf(la.x + (lb.x - la.x) * t) < half_len + 0.6

func attack_point(from: Vector3) -> Vector3:
	return point_at(clampf(_local(from).x, -half_len, half_len))

func approach_point(from: Vector3) -> Vector3:
	var side := signf(_local(from).y)
	if side == 0.0: side = 1.0
	var p := attack_point(from) + Vector3(normal2.x, 0, normal2.y) * side * 1.15
	return Map.ground_pos(p.x, p.z)

func intercepts(from: Vector3, destination: Vector3, path: PackedVector3Array) -> bool:
	if hp <= 0.0: return false
	if crosses(from, destination): return true
	# Catch a route around the end of a defended entrance before avoidance can
	# turn it into a permanent flank. Open countryside remains traversable.
	var a := _local(from)
	var b := _local(destination)
	if a.y * b.y < 0.0 and absf(a.x) < half_len + 9.0 and absf(a.y) < 18.0:
		return true
	var previous := from
	for point in path:
		if crosses(previous, point): return true
		previous = point
	return false

func placement_blocked(player: Player) -> bool:
	# A just-moved player may not be in the physics broad phase yet.
	var p := _local(player.global_position)
	if absf(p.x) < half_len + 0.4 and absf(p.y) < 0.95 and absf(player.global_position.y - point_at(p.x).y) < 2.0:
		return true
	for shape: CollisionShape3D in body.get_children():
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = body.global_transform * shape.transform
		query.collision_mask = 2 | 4
		query.margin = 0.08
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return true
	return false

func action_error(player: Player, action: String, require_reach := true) -> String:
	if not player.alive:
		return "Bauen ist momentan nicht möglich."
	if action != "build" and action != "repair":
		return "Unbekannte Aktion."
	if require_reach and distance_to_line(player.global_position) > BUILD_REACH:
		return "Zu weit entfernt. Gehe auf höchstens 6 m an die Linie heran."
	if action == "build" and level >= MAX_LEVEL:
		return "Maximale Ausbaustufe erreicht."
	if action == "repair" and (level == 0 or hp >= max_hp()):
		return "Keine Reparatur nötig."
	var cost := COST_REPAIR if action == "repair" else COST_BUILD
	if player.score < cost:
		return "Es fehlen %d Punkte." % (cost - player.score)
	if action == "build" and level == 0 and placement_blocked(player):
		return "Baufläche belegt. Du oder ein Gegner stehen in der Linie."
	return ""

func purchase(player: Player, action: String, require_reach := true) -> bool:
	var error := action_error(player, action, require_reach)
	if not error.is_empty():
		hud.message(error, 2.0)
		return false
	var success := repair() if action == "repair" else build()
	if not success:
		return false
	player.add_score(-COST_REPAIR if action == "repair" else -COST_BUILD)
	Sfx.play(self, "confirm", -8.0)
	Sfx.play_at(get_parent(), "wood", center, -8.0)
	return true

func prompt_text() -> String:
	return "[E] %s  ·  %s\nGanze Linie: %.1f m  ·  E: bauen / reparieren%s" % [slot["name"], "Bauplatz" if level == 0 else "Stufe %d · %d/%d" % [level, ceili(hp), int(max_hp())], half_len * 2.0, "  ·  Leertaste: drüberklettern" if level > 0 else ""]

func interact(player: Player) -> void:
	# Scripted callers keep the original shortcut; the game opens the planner.
	purchase(player, "repair" if level > 0 and hp < max_hp() else "build", false)
