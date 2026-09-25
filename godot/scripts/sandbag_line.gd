# The second line of defence (26 Sep 2026): a sandbag emplacement FALLBACK_DEPTH metres inside the ring
# behind every gate, parallel to it. It stays a marked site until the gate in front of it is breached -
# then it rises for free (main._gate_breached -> deploy) and the zombies pouring in have to break it too,
# while the players fire over it (0.95 m, Space vaults it like a gate). It takes the same hits a gate
# takes (zombie swings, acid, titan slams, rams), can be repaired with E for REPAIR_COST and, once
# destroyed, rebuilt with E for DEPLOY_COST. It never joins the palisade ring or the planner: it is a
# Barricade for the zombie AI, the HUD arrows, the minimap and the co-op snapshot ("sandbags").
class_name SandbagLine
extends Barricade

const FALLBACK_DEPTH := 9.0
const SANDBAG_HP := 450.0
const SANDBAG_HEIGHT := 0.95
const COLLISION_HEIGHT := 1.25      # taller than the bags: blocks the zombies' sight line to a player behind it
const DEPLOY_COST := 60
const REPAIR_COST_SB := 40
const ARMOR := 0.2
static var _sandbag_scene: PackedScene
static var _sandbag_loaded := false
var gate: Barricade
var deployments := 0           # free deployments so far (statistics / tests)

# The slot of the line behind a gate: same direction, FALLBACK_DEPTH metres towards the ring's centre.
static func slot_behind(gate_slot: Dictionary, inside: Vector2) -> Dictionary:
	var at: Vector2 = gate_slot["pos"] + inside * FALLBACK_DEPTH
	return {"id": str(gate_slot["id"]) + "_sb", "name": gate_slot["name"], "pos": at, "yaw": float(gate_slot["yaw"]), "segments": int(gate_slot["segments"])}

static func _load_scene() -> void:
	if _sandbag_loaded: return
	_sandbag_loaded = true
	var path := "res://assets/models/sandbag.glb"
	_sandbag_scene = load(path) if ResourceLoader.exists(path) else null

func is_gate() -> bool:
	return false

func wall_height() -> float:
	return SANDBAG_HEIGHT

func collision_height() -> float:
	return COLLISION_HEIGHT

func segment_scene(_tier_level: int) -> PackedScene:
	_load_scene()
	return _sandbag_scene

func max_hp() -> float:
	return SANDBAG_HP if level > 0 else 0.0

func armor() -> float:
	return ARMOR

func hit_sound() -> String:
	return "hit"

func tier_name() -> String:
	return "Sandbag line" if level > 0 else "Fallback site"

func next_cost() -> int:
	return DEPLOY_COST if level == 0 else 0

func breach_message() -> String:
	return Lang.t("Sandbag line behind %s destroyed!", [slot["name"]])

# One segment = three staggered rows of small bags (BAG_LENGTH long) instead of one bag stretched over
# 3.2 m. The bag mesh comes from sandbag.glb (its longest side turned along the line); without the GLB
# the plain boxes stand in. The holder's frame follows the terrain like every barricade segment.
const BAG_LENGTH := 0.62
const BAG_HEIGHT := 0.31
const BAG_DEPTH := 0.5
const BAG_ROWS := 3
static var _bag_mesh: Mesh
static var _bag_material: Material
static var _bag_fit := Transform3D.IDENTITY

static func _load_bag() -> void:
	if _bag_mesh: return
	_load_scene()
	if _sandbag_scene:
		var model: Node3D = _sandbag_scene.instantiate()
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			var mesh_node := meshes[0] as MeshInstance3D
			_bag_mesh = mesh_node.mesh
			_bag_material = mesh_node.mesh.surface_get_material(0) if mesh_node.mesh.get_surface_count() > 0 else null
			var bounds := _bounds(model)
			var turned := bounds.size.z > bounds.size.x
			var length := maxf(bounds.size.z if turned else bounds.size.x, 0.001)
			var depth := maxf(bounds.size.x if turned else bounds.size.z, 0.001)
			var fit_scale := Vector3(BAG_LENGTH / length, BAG_HEIGHT / maxf(bounds.size.y, 0.001), BAG_DEPTH / depth)
			var basis := Basis(Vector3.UP, PI * 0.5) if turned else Basis.IDENTITY
			var centre := bounds.get_center()
			_bag_fit = Transform3D(basis.scaled(fit_scale), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -Vector3(centre.x, bounds.position.y, centre.z))
		model.free()
	if not _bag_mesh:
		var box := BoxMesh.new()
		box.size = Vector3(BAG_LENGTH, BAG_HEIGHT, BAG_DEPTH)
		_bag_mesh = box
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = Color(0.58, 0.5, 0.36)
		cloth.roughness = 1.0
		_bag_material = cloth
		_bag_fit = Transform3D(Basis.IDENTITY, Vector3(0, BAG_HEIGHT * 0.5, 0))

func _make_segment(_tier_level := 1) -> Node3D:
	_load_bag()
	var holder := Node3D.new()
	var per_row := int(SEGMENT_LENGTH / BAG_LENGTH) + 1
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _bag_mesh
	var transforms: Array[Transform3D] = []
	for row in BAG_ROWS:
		var shift := (row % 2) * BAG_LENGTH * 0.5
		var count := per_row - (row % 2)
		for i in count:
			var along := -SEGMENT_LENGTH * 0.5 + BAG_LENGTH * 0.5 + i * BAG_LENGTH + shift
			if along > SEGMENT_LENGTH * 0.5 - BAG_LENGTH * 0.3: continue
			var yaw := (float((i * 7 + row * 3) % 5) - 2.0) * 0.04
			var at := Vector3(along, row * BAG_HEIGHT * 0.92 - 0.06, (float((i + row) % 3) - 1.0) * 0.03)
			transforms.append(Transform3D(Basis(Vector3.UP, yaw), at) * _bag_fit)
	multimesh.instance_count = transforms.size()
	for i in transforms.size(): multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	if _bag_material: instance.material_override = _bag_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.add_child(instance)
	return holder

# a breached gate raises the line for free
func deploy() -> bool:
	if level > 0: return false
	level = 1
	hp = max_hp()
	deployments += 1
	rebuild()
	Sfx.play_at(get_parent(), "build", center, -4.0)
	return true

func build() -> bool:
	if level > 0: return false
	level = 1
	hp = max_hp()
	rebuild()
	var scene := get_tree().current_scene
	if "stats" in scene and scene.stats: scene.stats.barricades_built += 1
	return true

func action_error(player: Player, action: String, require_reach := true) -> String:
	if not player.alive or player.downed:
		return "Building is not possible right now."
	if action != "build" and action != "repair":
		return "Unknown action."
	if require_reach and distance_to_line(player.global_position) > BUILD_REACH:
		return "Too far away. Move within 6 m of the line."
	if action == "build" and level > 0:
		return "The sandbag line already stands."
	if action == "repair" and (level == 0 or hp >= max_hp()):
		return "No repair needed."
	var cost := REPAIR_COST_SB if action == "repair" else DEPLOY_COST
	if player.score + purse() < cost:
		return Lang.t("You are %d Rem Dollars short.", [cost - player.score - purse()])
	if action == "build" and placement_blocked(player):
		return "Building area occupied. You or an enemy is standing in the line."
	return ""

func purchase(player: Player, action: String, require_reach := true) -> bool:
	var error := action_error(player, action, require_reach)
	if not error.is_empty():
		hud.message(error, 2.0)
		return false
	var cost := REPAIR_COST_SB if action == "repair" else DEPLOY_COST
	var success := repair() if action == "repair" else build()
	if not success: return false
	spend(player, cost)
	Sfx.play(self, "confirm", -8.0)
	Sfx.play_at(get_parent(), "build", center, -6.0)
	return true

func prompt_text() -> String:
	if level == 0: return Lang.t("[E] Sandbag line behind %s  ·  build for %d R\nRises for free when the gate is breached  ·  Space: climb over", [slot["name"], DEPLOY_COST])
	return Lang.t("[E] Sandbag line behind %s  ·  %d/%d  ·  repair %d R\nSpace: climb over", [slot["name"], ceili(hp), int(max_hp()), REPAIR_COST_SB])
