class_name DefenceTower
extends Node3D

const COST := 120
const REPAIR_COST := 35
const LIMIT := 6
const HEALTH := [240.0, 400.0, 600.0]
const RANGE := [26.0, 32.0, 38.0]
const UPGRADES := [100, 175]
const HALF_ARC := 80.0 * PI / 180.0
var tower_id := 0
var owner_peer := 1
var level := 1
var hp := 240.0
var replica := false
var game: Node
var body: StaticBody3D
var gun: Node3D
var muzzle: Node3D
var label: Label3D
var tracer: MeshInstance3D
var flash: OmniLight3D
var target: Zombie
var cooldown := 0.0
var heat := 0.0
var overheated := false
var shots := 0
var last_impact := Vector3.ZERO
var _scan := 0.0
var _flash_t := 0.0
var aim_yaw := 0.0
var aim_pitch := 0.0
var reinforcement: Node3D
var armour: Node3D

static func material(color: Color, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.78 if metal == 0.0 else 0.42
	return mat

static func piece(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	parent.add_child(instance)
	return instance

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return piece(parent, mesh, pos, mat)

static func cylinder(parent: Node3D, radius: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	return piece(parent, mesh, pos, mat)

func _ready() -> void:
	add_to_group("defence_towers")
	add_to_group("render_dynamic")
	var steel := material(Color(0.12, 0.15, 0.14), 0.8)
	var wood := material(Color(0.75, 0.69, 0.57))
	wood.albedo_texture = load("res://assets/textures/planks_albedo.jpg")
	wood.normal_enabled = true
	wood.normal_texture = load("res://assets/textures/planks_normal.jpg")
	wood.roughness_texture = load("res://assets/textures/planks_rough.jpg")
	var concrete := material(Color(0.75, 0.73, 0.66))
	concrete.albedo_texture = load("res://assets/textures/ph_concrete_albedo.jpg")
	concrete.normal_enabled = true
	concrete.normal_texture = load("res://assets/textures/ph_concrete_normal.jpg")
	var brass := material(Color(0.54, 0.39, 0.13), 0.7)
	var sand := material(Color(0.39, 0.37, 0.23))
	for x in [-0.8, 0.8]:
		for z in [-0.8, 0.8]:
			box(self, Vector3(0.55, 0.3, 0.55), Vector3(x, 0.07, z), concrete)
			box(self, Vector3(0.19, 2.5, 0.19), Vector3(x, 1.32, z), steel)
	for z in [-0.8, 0.8]:
		for sign_x in [-1, 1]:
			Barricade._add_bar(self, Vector3(-0.8 * sign_x, 0.25, z), Vector3(0.8 * sign_x, 2.4, z), 0.09, steel)
	for i in 9:
		box(self, Vector3(2.15, 0.14, 0.235), Vector3(0, 2.45, (i - 4) * 0.24), wood)
	for x in [-0.92, 0.92]:
		for z in [-0.68, 0.0, 0.68]:
			var bag := cylinder(self, 0.22, 0.65, Vector3(x, 2.7, z), sand)
			bag.rotation.x = PI * 0.5
	for i in 7:
		box(self, Vector3(0.55, 0.075, 0.1), Vector3(0, 0.26 + i * 0.33, 1.08), steel)
	for x in [-0.31, 0.31]:
		box(self, Vector3(0.065, 2.5, 0.07), Vector3(x, 1.28, 1.08), steel)
	cylinder(self, 0.27, 0.7, Vector3(0, 2.85, 0), steel)
	gun = Node3D.new()
	gun.position.y = 3.15
	add_child(gun)
	box(gun, Vector3(0.48, 0.38, 0.85), Vector3(0, 0, -0.08), steel)
	box(gun, Vector3(0.32, 0.4, 0.48), Vector3(0.4, -0.03, 0), sand)
	for x in [-0.13, 0.13]:
		var barrel := cylinder(gun, 0.058, 1.4, Vector3(x, 0, -0.99), steel)
		barrel.rotation.x = PI * 0.5
		for i in 7:
			var fin := cylinder(gun, 0.087, 0.035, Vector3(x, 0, -0.65 - i * 0.11), steel)
			fin.rotation.x = PI * 0.5
	for i in 7:
		cylinder(gun, 0.025, 0.15, Vector3(0.24 + i * 0.03, -0.18, -0.1), brass)
	box(gun, Vector3(0.2, 0.18, 0.22), Vector3(0, 0.3, -0.05), steel)
	var lens := material(Color(0.7, 0.12, 0.035))
	lens.emission_enabled = true
	lens.emission = Color(1, 0.15, 0.02)
	box(gun, Vector3(0.09, 0.075, 0.01), Vector3(0, 0.3, -0.165), lens)
	reinforcement = Node3D.new()
	add_child(reinforcement)
	for x in [-0.92, 0.92]:
		box(reinforcement, Vector3(0.08, 0.8, 1.8), Vector3(x, 1.95, 0), steel)
	armour = Node3D.new()
	gun.add_child(armour)
	for x in [-0.38, 0.38]:
		var plate := box(armour, Vector3(0.35, 0.6, 0.09), Vector3(x, 0.06, -0.49), steel)
		plate.rotation.y = -signf(x) * 0.3
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -1.7)
	gun.add_child(muzzle)
	body = StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = Vector3(2.15, 2.9, 2.15)
	shape.shape = collider
	shape.position.y = 1.4
	body.add_child(shape)
	label = Label3D.new()
	label.position = Vector3(0, 4, 0)
	label.font_size = 36
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 18.0
	add_child(label)
	var glow := material(Color(1, 0.75, 0.22))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer = box(self, Vector3(0.018, 0.018, 1), Vector3.ZERO, glow)
	tracer.top_level = true
	tracer.visible = false
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.58, 0.12)
	flash.omni_range = 5
	flash.visible = false
	muzzle.add_child(flash)
	refresh()

func max_hp() -> float:
	return HEALTH[level - 1]

func attack_point(from: Vector3) -> Vector3:
	var direction := Vector3(from.x - global_position.x, 0, from.z - global_position.z).normalized()
	return global_position + direction * 1.05

func damage(amount: float) -> void:
	if replica or NetSession.is_client() or hp <= 0.0: return
	hp = maxf(0, hp - amount)
	refresh()
	if hp <= 0:
		Sfx.play_at(game, "barricade_break", global_position, -2)
		game.hud.message("Geschützturm zerstört!", 2)
		queue_free()

func refresh() -> void:
	if reinforcement: reinforcement.visible = level >= 2
	if armour: armour.visible = level >= 3
	if label:
		label.text = "WÄCHTER %s · %d / %d" % ["I".repeat(level), ceili(hp), int(max_hp())]
		label.modulate = Color(1, 0.58, 0.32) if hp < max_hp() * 0.4 else Color(0.82, 0.9, 0.76)

func can_see(z: Zombie) -> bool:
	if not is_instance_valid(z) or not z.alive: return false
	var direction := z.global_position - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.01:
		var yaw := atan2(-direction.x, -direction.z)
		if absf(angle_difference(rotation.y, yaw)) > HALF_ARC: return false
	var aim := z.global_position + Vector3.UP * z.height * 0.55
	if muzzle.global_position.distance_squared_to(aim) > pow(RANGE[level - 1], 2): return false
	var q := PhysicsRayQueryParameters3D.create(muzzle.global_position, aim, Zombie.SHOT_MASK, [body.get_rid()])
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return Zombie.from_hit(hit) == z

func _physics_process(delta: float) -> void:
	_flash_t = maxf(0, _flash_t - delta)
	tracer.visible = _flash_t > 0
	flash.visible = _flash_t > 0
	gun.rotation.y = lerp_angle(gun.rotation.y, aim_yaw, minf(1, delta * 4.0))
	gun.rotation.x = lerp_angle(gun.rotation.x, aim_pitch, minf(1, delta * 4.0))
	if replica or NetSession.is_client() or not game.started or game.over: return
	cooldown -= delta
	heat = maxf(0, heat - delta * (0.3 if overheated else 0.1))
	if overheated and heat <= 0.05: overheated = false
	_scan -= delta
	if _scan <= 0:
		_scan = 0.25
		target = null
		var best := INF
		for z in game.zombies_root.get_children():
			if not z is Zombie or not z.alive: continue
			var d: float = global_position.distance_squared_to(z.global_position)
			if d < best and can_see(z):
				best = d
				target = z
	if not is_instance_valid(target) or not target.alive: return
	var direction := target.global_position + Vector3.UP * target.height * 0.55 - gun.global_position
	aim_yaw = wrapf(atan2(-direction.x, -direction.z) - rotation.y, -PI, PI)
	aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	if cooldown <= 0 and not overheated and absf(angle_difference(gun.rotation.y, aim_yaw)) < 0.12 and absf(angle_difference(gun.rotation.x, aim_pitch)) < 0.12 and can_see(target):
		shoot()

func shoot() -> void:
	cooldown = 0.22 - (level - 1) * 0.025
	heat = minf(1, heat + 0.13)
	if heat >= 0.99: overheated = true
	var aim := target.global_position + Vector3.UP * target.height * 0.55
	# Ballistic dispersion can miss; world geometry and other enemies stop each shot.
	var distance := muzzle.global_position.distance_to(aim)
	aim += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * distance * 0.009
	var direction := (aim - muzzle.global_position).normalized()
	var end: Vector3 = muzzle.global_position + direction * RANGE[level - 1]
	var q := PhysicsRayQueryParameters3D.create(muzzle.global_position, end, Zombie.SHOT_MASK, [body.get_rid()])
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	last_impact = hit.position if not hit.is_empty() else end
	var z := Zombie.from_hit(hit)
	if z and z.alive:
		z.killer_peer = owner_peer
		z.killer_weapon = "tower"
		z.last_headshot = false
		z.damage(18.0 + (level - 1) * 7.0, direction)
	shots += 1
	show_shot()

func show_shot() -> void:
	if not is_inside_tree() or not muzzle: return
	var start := muzzle.global_position
	var direction := last_impact - start
	if direction.length() < 0.05: return
	tracer.global_position = (start + last_impact) * 0.5
	tracer.look_at(last_impact, Vector3.UP)
	tracer.scale = Vector3(1, 1, direction.length())
	_flash_t = 0.06
	flash.light_energy = 3.0
	Sfx.play_at(game, "smg", start, -13.0, 0.87)
