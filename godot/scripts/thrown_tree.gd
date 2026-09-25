# A tree torn out and thrown by a titan that has lost an arm (26 Sep 2026, titan.gd phases): one of the
# Meshy forest trees (MODELS, HEIGHT metres, picked from the throw's origin so host and clients agree)
# with a root ball of soil under its trunk tumbles along an arc from the giant's hand to the aimed point,
# crushes whatever stands within RADIUS of the impact (players with a shove, gates, sandbag lines,
# towers, the hut, even zombies) and then lies on the ground for a while before sinking away. The host
# owns the damage; clients spawn a replica from NetSession._titan_throw with the same arc. Without the
# GLBs (a stripped build) the old procedural trunk and crown stand in.
class_name ThrownTree
extends Node3D

const RADIUS := 5.5
const REST_SECONDS := 24.0
const SPIN := 3.2
const MODELS := ["tree_autumn_a", "tree_autumn_b"]
const HEIGHT := 11.5
static var _scenes: Dictionary = {}

var from := Vector3.ZERO
var to := Vector3.ZERO
var flight := 1.8
var replica := false
var titan: Titan
var damage := 55.0
var structure := 190.0
var damage_mul := 1.0
var landed := false
var _t := 0.0
var _rest := 0.0
var _spin_axis := Vector3.RIGHT
var _visual: Node3D
static var _bark: Material
static var _crown: StandardMaterial3D
static var _soil: StandardMaterial3D

static func _shared() -> void:
	if _bark: return
	_bark = Foliage.pbr("bark", 1.0)
	_crown = StandardMaterial3D.new()
	_crown.albedo_color = Color(0.22, 0.32, 0.12)
	_crown.roughness = 1.0
	_soil = StandardMaterial3D.new()
	_soil.albedo_color = Color(0.2, 0.15, 0.1)
	_soil.roughness = 1.0

func setup(a: Vector3, b: Vector3, seconds: float, thrower: Titan, is_replica: bool) -> void:
	_shared()
	from = a
	to = b
	flight = maxf(seconds, 0.6)
	titan = thrower
	replica = is_replica
	if thrower and is_instance_valid(thrower):
		damage = float(thrower.type.damage) * 0.8
		damage_mul = thrower.damage_mul
	var dir := (b - a)
	dir.y = 0.0
	_spin_axis = Vector3.UP.cross(dir.normalized()).normalized() if dir.length() > 0.1 else Vector3.RIGHT
	_visual = Node3D.new()
	add_child(_visual)
	var roots := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.3
	ball.height = 2.0
	ball.radial_segments = 10
	ball.rings = 5
	roots.mesh = ball
	roots.material_override = _soil
	roots.position.y = -0.7
	roots.scale = Vector3(1.1, 0.75, 1.1)
	_visual.add_child(roots)
	var model := _tree_model(a)
	if model:
		_visual.add_child(model)
	else:
		var trunk := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.32
		cylinder.bottom_radius = 0.62
		cylinder.height = 9.0
		cylinder.radial_segments = 10
		trunk.mesh = cylinder
		trunk.material_override = _bark
		trunk.position.y = 3.5
		_visual.add_child(trunk)
		var crown := MeshInstance3D.new()
		var leaves := SphereMesh.new()
		leaves.radius = 3.4
		leaves.height = 8.0
		leaves.radial_segments = 12
		leaves.rings = 7
		crown.mesh = leaves
		crown.material_override = _crown
		crown.position.y = 8.6
		_visual.add_child(crown)
	global_position = a

# One of the forest tree GLBs, HEIGHT metres tall with the foot of its trunk on the visual's origin.
static func _tree_model(origin: Vector3) -> Node3D:
	var name: String = MODELS[int(absf(origin.x * 7.3 + origin.z * 3.1)) % MODELS.size()]
	if not _scenes.has(name):
		var path := "res://assets/models/%s.glb" % name
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[name]
	if scene == null: return null
	var model: Node3D = scene.instantiate()
	var bounds := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var n: Node = m
		while n != model and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var b: AABB = t * (m as MeshInstance3D).get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if bounds.size.y <= 0.0:
		model.free()
		return null
	var s := HEIGHT / bounds.size.y
	model.scale = Vector3.ONE * s
	model.position = Vector3(-bounds.get_center().x * s, -bounds.position.y * s, -bounds.get_center().z * s)
	return model

func _process(delta: float) -> void:
	if landed:
		_rest += delta
		if _rest > REST_SECONDS - 3.0: global_position.y -= delta * 1.6
		if _rest > REST_SECONDS: queue_free()
		return
	_t += delta
	var k := _t / flight
	if k >= 1.0:
		_impact()
		return
	var apex := maxf(7.0, from.distance_to(to) * 0.28)
	global_position = from.lerp(to, k) + Vector3.UP * 4.0 * apex * k * (1.0 - k)
	_visual.basis = Basis(_spin_axis, _t * SPIN)

func _impact() -> void:
	landed = true
	global_position = to
	var dir := to - from
	dir.y = 0.0
	# lie along the throw, roots first: the root ball digs in at the impact, the crown props the trunk
	# up a little, so the tree rests on its branches instead of the crown lying half in the ground
	_visual.basis = Basis(Vector3.RIGHT, PI * 0.5 - 0.14)
	rotation.y = atan2(dir.x, dir.z) if dir.length() > 0.1 else 0.0
	global_position.y = Map.ground_height(to.x, to.z) + 0.9
	var scene := get_tree().current_scene
	Sfx.play_at(scene if scene else self, "crash", to, 2.0, 0.8, 30.0, 220.0)
	_dust(scene)
	if replica or NetSession.is_client() or not scene: return
	if titan and is_instance_valid(titan): titan.emit_cue("slam", to)
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [scene.player]
	for actor in actors:
		if not is_instance_valid(actor) or not actor.alive: continue
		var d: float = actor.global_position.distance_to(to)
		if d < RADIUS:
			actor.damage(damage * damage_mul * (1.0 - 0.5 * d / RADIUS), to)
			if actor.has_method("shove"): actor.shove((actor.global_position - to).normalized() * 6.0 + Vector3.UP * 3.0)
	var lines: Array = scene.defence_lines() if scene.has_method("defence_lines") else scene.get("barricades")
	for line in lines:
		if is_instance_valid(line) and line.hp > 0.0 and line.attack_point(to).distance_to(to) < RADIUS + 1.0:
			line.damage(structure * damage_mul)
	for tower in get_tree().get_nodes_in_group("defence_towers"):
		if tower.hp > 0.0 and tower.attack_point(to).distance_to(to) < RADIUS + 1.0: tower.damage(structure * damage_mul)
	var hut = scene.get("hut")
	if hut and hut.hp > 0.0 and hut.attack_point(to).distance_to(to) < RADIUS + 1.5: hut.damage(structure * 2.0 * damage_mul)
	for z in scene.zombies_root.get_children():
		if z is Zombie and z.alive and not Zombie.is_boss_kind(z.net_kind) and z.global_position.distance_to(to) < RADIUS:
			z.last_headshot = false
			z.killer_weapon = "titan"
			z.damage(140.0, (z.global_position - to).normalized())

func _dust(scene: Node) -> void:
	var dust := CPUParticles3D.new()
	dust.amount = 60
	dust.lifetime = 1.8
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.direction = Vector3.UP
	dust.spread = 75.0
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 9.0
	dust.gravity = Vector3(0, -4, 0)
	dust.scale_amount_min = 0.3
	dust.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _soil
	dust.mesh = mesh
	(scene if scene else self).add_child(dust)
	dust.global_position = to + Vector3.UP * 0.3
	dust.emitting = true
	get_tree().create_timer(2.5, false).timeout.connect(dust.queue_free)
