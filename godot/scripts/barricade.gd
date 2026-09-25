# A complete defence line: one purchase, continuous models and terrain-following collision.
class_name Barricade
extends Node3D

signal changed
signal breached                 # a built line fell to zero (main deploys the sandbag line behind a gate)

# Three tiers, each with its own Meshy wall (Sep 2026): the timber palisade, an iron-banded log wall and
# the steel bulwark. "armor" is the share of every hit the wall shrugs off, "cost" what the next tier
# costs; the planner reads the same table. A missing GLB falls back to the timber model with steel bars.
const TIERS := [
	{"name": "Timber palisade", "model": "barricade", "hp": 300.0, "cost": 50, "armor": 0.0, "hit_sfx": "wood_hit", "repair": 25},
	{"name": "Iron-banded wall", "model": "barricade_iron", "hp": 800.0, "cost": 120, "armor": 0.3, "hit_sfx": "wood_hit", "repair": 50},
	{"name": "Steel bulwark", "model": "barricade_steel", "hp": 1600.0, "cost": 220, "armor": 0.5, "hit_sfx": "hit", "repair": 90},
]
const COST_BUILD := 50          # tier 1; later tiers come from TIERS
const COST_REPAIR := 25         # tier 1; later tiers come from TIERS
const MAX_LEVEL := 3
const HP_PER_LEVEL := 300.0     # tier 1 health, kept for older callers
const SEGMENT_LENGTH := 3.2
const HEIGHT := 1.55
const BUILD_REACH := 6.0
const ATTACK_ALERT_SECONDS := 5.0
var attack_alert_remaining := 0.0
const MODEL := preload("res://assets/models/barricade.glb")
static var _tier_scenes := {}

static func tier(level_index: int) -> Dictionary:
	return TIERS[clampi(level_index - 1, 0, TIERS.size() - 1)]

static func tier_hp(level_index: int) -> float:
	return float(tier(level_index)["hp"]) if level_index > 0 else 0.0

static func build_cost(level_index: int) -> int:
	# cost of reaching level_index (1..MAX_LEVEL)
	return int(tier(level_index)["cost"])

static func repair_cost(level_index: int) -> int:
	return int(tier(level_index)["repair"]) if level_index > 0 else COST_REPAIR

static func tier_scene(level_index: int) -> PackedScene:
	var name: String = tier(level_index)["model"]
	if not _tier_scenes.has(name):
		var path := "res://assets/models/%s.glb" % name
		_tier_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	return _tier_scenes[name]

# Overridable per line kind (sandbag_line.gd): a gate is one of the four palisade openings.
func is_gate() -> bool:
	return true

func wall_height() -> float:
	return HEIGHT

# the collision box may stand taller than the visual wall: a zombie's sight line to a player right behind
# it (1 m up) must hit the box, or the zombie sees the player, ignores the line and pushes against it forever
func collision_height() -> float:
	return wall_height()

func segment_scene(tier_level: int) -> PackedScene:
	return tier_scene(tier_level)

func armor() -> float:
	return float(tier(level)["armor"])

func hit_sound() -> String:
	return String(tier(level)["hit_sfx"])

func breach_message() -> String:
	return Lang.t("Barricade %s breached!", [slot["name"]])

# The team purse (26 Sep 2026, co-op only): deposits every teammate makes pay for gates and sandbag lines
# before the buyer's own Rem Dollars do. Solo play has no purse. Host authoritative (coop_world.purse).
static func purse() -> int:
	if NetSession.is_host() and NetSession.world: return int(NetSession.world.purse)
	if NetSession.is_client() and NetSession.world: return int(NetSession.world.purse)
	return 0

static func spend(player: Player, cost: int) -> void:
	var from_purse := 0
	if NetSession.is_host() and NetSession.world:
		from_purse = mini(int(NetSession.world.purse), cost)
		NetSession.world.purse -= from_purse
	if cost - from_purse > 0: player.add_score(-(cost - from_purse))
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
var health_display: Node3D
var health_fill: Sprite3D
var health_label: Label3D

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
		box.size = Vector3(SEGMENT_LENGTH + 0.06, collision_height(), 0.9)
		shape.shape = box
		shape.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, collision_height() * 0.5 - 0.06, 0))
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
	_create_health_display()
	changed.connect(_update_health_display)
	rebuild()

func _create_health_display() -> void:
	health_display = Node3D.new()
	health_display.name = "HealthDisplay"
	health_display.position.y = 3.4
	for frame in _segment_transforms:
		health_display.position.y = maxf(health_display.position.y, frame.origin.y + wall_height() + 0.6)
	add_child(health_display)
	var image := Image.create(256, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for background in [true, false]:
		var sprite := Sprite3D.new()
		sprite.texture = texture
		sprite.pixel_size = 0.008
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.render_priority = 10 if background else 11
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		health_display.add_child(sprite)
		if background:
			sprite.modulate = Color(0.025, 0.035, 0.04, 0.9)
			sprite.scale = Vector3(1.04, 1.6, 1)
		else:
			health_fill = sprite
			health_fill.region_enabled = true
	health_label = Label3D.new()
	health_label.position.y = 0.27
	health_label.font_size = 32
	health_label.outline_size = 8
	health_label.pixel_size = 0.006
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.no_depth_test = true
	health_label.render_priority = 12
	health_display.add_child(health_label)

func _update_health_display() -> void:
	health_display.visible = level > 0 and hp > 0.0
	if not health_display.visible: return
	var ratio := clampf(hp / max_hp(), 0.0, 1.0)
	var width := 256.0 * ratio
	health_fill.region_rect = Rect2(0, 0, width, 18)
	health_fill.offset.x = (width - 256.0) * 0.5
	health_fill.modulate = Color(0.3, 0.9, 0.5) if ratio > 0.5 else (Color(1.0, 0.72, 0.2) if ratio > 0.25 else Color(1.0, 0.25, 0.2))
	health_label.text = "%d / %d" % [ceili(hp), int(max_hp())]

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

func _make_segment(tier_level := 1) -> Node3D:
	# The wall of the requested tier, its longest horizontal side turned along the line (+x), then
	# scaled into the segment box. Tiers without a GLB use the timber model.
	var holder := Node3D.new()
	var fit := Node3D.new()
	var scene := segment_scene(tier_level)
	var model: Node3D = (scene if scene else MODEL).instantiate()
	holder.add_child(fit)
	fit.add_child(model)
	var bounds := _bounds(model)
	if bounds.size.z > bounds.size.x:
		model.rotation.y = PI * 0.5
		bounds = _bounds(model)
	var depth := 0.8 if tier_level <= 1 else 1.0
	if not is_gate(): depth = 1.1
	fit.scale = Vector3((SEGMENT_LENGTH + 0.06) / maxf(bounds.size.x, 0.001), wall_height() / maxf(bounds.size.y, 0.001), depth / maxf(bounds.size.z, 0.001))
	fit.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit.scale - Vector3.UP * 0.06
	return holder

static func has_tier_model(tier_level: int) -> bool:
	return tier_scene(tier_level) != null

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
	return tier_hp(level)

func tier_name() -> String:
	return String(tier(level)["name"]) if level > 0 else "Building site"

func next_cost() -> int:
	return build_cost(level + 1) if level < MAX_LEVEL else 0

func under_attack() -> bool:
	return level > 0 and hp > 0.0 and attack_alert_remaining > 0.0

func update_attack_alert(seconds: float, notify := true) -> void:
	var was_under_attack := under_attack()
	attack_alert_remaining = maxf(0.0, seconds) if level > 0 and hp > 0.0 else 0.0
	if notify and under_attack() and not was_under_attack and hud:
		hud.message(Lang.t("WARNING: %s is under attack!", [slot["name"]]), 3.0)

func _process(delta: float) -> void:
	attack_alert_remaining = maxf(0.0, attack_alert_remaining - delta) if level > 0 else 0.0

func rebuild() -> void:
	for child in visual.get_children():
		visual.remove_child(child)
		child.queue_free()
	for shape: CollisionShape3D in body.get_children():
		shape.set_deferred("disabled", level == 0)
	if level > 0:
		var own_model := has_tier_model(level)
		var metal: StandardMaterial3D = null
		if not own_model and level > 1:
			metal = StandardMaterial3D.new()
			metal.albedo_color = Color(0.21, 0.23, 0.22)
			metal.metallic = 0.75
			metal.roughness = 0.65
		for frame in _segment_transforms:
			var model := _make_segment(level)
			model.transform = frame
			visual.add_child(model)
			if metal:
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
	# Heavier tiers shrug off part of every hit on top of their larger health pool.
	hp = maxf(0.0, hp - n * (1.0 - armor()))
	update_attack_alert(ATTACK_ALERT_SECONDS)
	if hp <= 0.0:
		level = 0
		hud.message(breach_message(), 2.0)
		Sfx.play_at(get_parent(), "barricade_break", center, 0.0)
		rebuild()
		breached.emit()
	else:
		Sfx.play_at(get_parent(), hit_sound(), center, -4.0)
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
		return "Building is not possible right now."
	if action != "build" and action != "repair":
		return "Unknown action."
	if require_reach and distance_to_line(player.global_position) > BUILD_REACH:
		return "Too far away. Move within 6 m of the line."
	if action == "build" and level >= MAX_LEVEL:
		return "Maximum upgrade tier reached."
	if action == "repair" and (level == 0 or hp >= max_hp()):
		return "No repair needed."
	var cost := repair_cost(level) if action == "repair" else build_cost(level + 1)
	if player.score + purse() < cost:
		return Lang.t("You are %d Rem Dollars short.", [cost - player.score - purse()])
	if action == "build" and level == 0 and placement_blocked(player):
		return "Building area occupied. You or an enemy is standing in the line."
	return ""

func purchase(player: Player, action: String, require_reach := true) -> bool:
	var error := action_error(player, action, require_reach)
	if not error.is_empty():
		hud.message(error, 2.0)
		return false
	var cost := repair_cost(level) if action == "repair" else build_cost(level + 1)
	var success := repair() if action == "repair" else build()
	if not success:
		return false
	spend(player, cost)
	Sfx.play(self, "confirm", -8.0)
	Sfx.play_at(get_parent(), "build", center, -6.0)
	return true

func prompt_text() -> String:
	if level == 0: return Lang.t("[E] %s  ·  %s\nWhole line: %.1f m  ·  E: build / repair", [slot["name"], "Building site", half_len * 2.0])
	return Lang.t("[E] %s  ·  %s\nWhole line: %.1f m  ·  E: build / repair  ·  Space: climb over", [slot["name"], Lang.t("Tier %d · %s · %d/%d", [level, tier_name(), ceili(hp), int(max_hp())]), half_len * 2.0])

func interact(player: Player) -> void:
	# Scripted callers keep the original shortcut; the game opens the planner.
	purchase(player, "repair" if level > 0 and hp < max_hp() else "build", false)
