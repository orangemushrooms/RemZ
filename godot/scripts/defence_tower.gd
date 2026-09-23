class_name DefenceTower
extends Node3D

const COST := 120
const REPAIR_COST := 35
const LIMIT := 6
const HEALTH := [240.0, 400.0, 600.0]
const RANGE := [26.0, 32.0, 38.0]
const UPGRADES := [100, 175]
# Completed waves relative to each type: basic, reinforced, elite.
const UPGRADE_WAVE_OFFSETS := [0, 2, 5]
const HALF_ARC := 80.0 * PI / 180.0
const TYPES := ["standard", "flame", "mortar", "mg42", "tesla"]
const SPECS := {
	"standard": {"unlock_waves": 0, "name": "Sentinel", "cost": 120, "range": 26.0, "damage": 18.0, "rate": 0.22, "heat": 0.13, "health": 1.0, "info": "Precise bursts"},
	"flame": {"unlock_waves": 2, "name": "Flamethrower", "cost": 260, "range": 14.0, "damage": 14.0, "rate": 0.12, "heat": 0.035, "health": 1.2, "info": "Cone of fire hits several enemies"},
	"mortar": {"unlock_waves": 4, "name": "Mortar", "cost": 380, "range": 60.0, "damage": 145.0, "rate": 2.8, "heat": 0.2, "health": 1.4, "info": "Arcing shot · 6 m blast radius"},
	"mg42": {"unlock_waves": 6, "name": "Heavy MG", "cost": 450, "range": 44.0, "damage": 27.0, "rate": 0.085, "heat": 0.055, "health": 1.6, "info": "High rate of fire · watch the heat"},
	"tesla": {"unlock_waves": 8, "name": "Tesla Coil", "cost": 600, "range": 22.0, "damage": 75.0, "rate": 0.9, "heat": 0.16, "health": 1.8, "info": "Chain lightning jumps to nearby enemies"},
}
var kind := "standard"
var operator_peer := 0
var trigger := false
var aiming := false
var control_timeout := 0.0
var exit_position := Vector3.ZERO
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
var chain_points := PackedVector3Array()
var _scan := 0.0
var _flash_t := 0.0
var aim_yaw := 0.0
var aim_pitch := 0.0
var reinforcement: Node3D
var armour: Node3D
var flame: CPUParticles3D
var fx: Node3D
var shot_audio: Node3D
var _weapon_model: Node3D
var _model_rest := Vector3.ZERO
var _recoil := 0.0
var _recoil_velocity := 0.0
var _trace_origin := Vector3.ZERO
var _trace_direction := Vector3.FORWARD
var _trace_distance := 0.0
var _trace_travel := 0.0
var _lightning: MeshInstance3D
static var _boxes: Dictionary = {}
static var _cylinders: Dictionary = {}
static var _model_scenes: Dictionary = {}

func spec() -> Dictionary:
	return SPECS.get(kind, SPECS.standard)

func attack_range() -> float:
	return float(spec().range) + (level-1)*6.0

func manual_spread() -> float:
	# Small unaimed cone; holding the sights steadies every manually operated turret.
	var degrees: float = {"standard": 0.65, "mg42": 0.9, "mortar": 0.8, "flame": 0.7, "tesla": 0.35}.get(kind, 0.65)
	return tan(deg_to_rad(degrees)) * (0.25 if aiming else 1.0)

func upgrade_cost() -> int:
	return roundi(UPGRADES[mini(level-1,1)] * float(spec().cost)/COST)

func refund() -> int:
	return int(spec().cost)/3

func seat_position() -> Vector3:
	# Tall mortar tubes and the coil need a side operating position to keep the reticle clear.
	var seat := Vector3(0.7 if kind in ["tesla","mortar"] else 0.35 if kind=="flame" else 0.0,2.55,0.85)
	return to_global(seat.rotated(Vector3.UP,gun.rotation.y if gun else 0.0))

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
	if not _boxes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_boxes[size] = mesh
	return piece(parent, _boxes[size], pos, mat)

static func cylinder(parent: Node3D, radius: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var key := Vector2(radius, length)
	if not _cylinders.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		mesh.radial_segments = 16
		_cylinders[key] = mesh
	return piece(parent, _cylinders[key], pos, mat)

func _ready() -> void:
	add_to_group("defence_towers")
	add_to_group("render_dynamic")
	_scan = float(tower_id % 8) * 0.03
	if kind == "tesla":
		_lightning = preload("res://scripts/tower_lightning.gd").new()
		add_child(_lightning)
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
			var bag := WorldModels.attach(self, "sandbag", Vector3(x, 2.52, z), 0.65, 0)
			if bag:
				bag.rotation.y = PI * 0.5
			else:
				var preview := cylinder(self, 0.22, 0.65, Vector3(x, 2.7, z), sand)
				preview.rotation.x = PI * 0.5
	for i in 7:
		box(self, Vector3(0.55, 0.075, 0.1), Vector3(0, 0.26 + i * 0.33, 1.08), steel)
	for x in [-0.31, 0.31]:
		box(self, Vector3(0.065, 2.5, 0.07), Vector3(x, 1.28, 1.08), steel)
	cylinder(self, 0.12, 0.7, Vector3(0, 2.85, 0), steel)
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
	_build_variant(steel, brass)
	body = StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = Vector3(2.15, 2.52, 2.15)
	shape.shape = collider
	shape.position.y = 1.26
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
	fx = preload("res://scripts/tower_effects.gd").new()
	fx.kind = kind
	muzzle.add_child(fx)
	flame = fx.jet
	_weapon_model = gun.get_node_or_null("WeaponModel")
	if _weapon_model:
		_model_rest = _weapon_model.position
	refresh()

func max_hp() -> float:
	return HEALTH[level - 1]*float(spec().health)

func attack_point(from: Vector3) -> Vector3:
	var direction := Vector3(from.x - global_position.x, 0, from.z - global_position.z).normalized()
	return global_position + direction * 1.05

func damage(amount: float) -> void:
	if replica or NetSession.is_client() or hp <= 0.0: return
	hp = maxf(0, hp - amount)
	refresh()
	if hp <= 0:
		game.defences.release_tower(self)
		Sfx.play_at(game, "barricade_break", global_position, -2)
		game.hud.message("Gun turret destroyed!", 2)
		queue_free()

func refresh() -> void:
	if reinforcement: reinforcement.visible = level >= 2
	if armour: armour.visible = level >= 3
	if label:
		label.visible = operator_peer == 0 or operator_peer != (NetSession.local_id() if NetSession.enabled else game.player.peer_id)
		var args := [spec().name, Lang.raw("I".repeat(level)), ceili(hp), int(max_hp())]
		label.text = Lang.t("%s %s · %d / %d · OCCUPIED", args) if operator_peer else Lang.t("%s %s · %d / %d", args)
		label.modulate = Color(1, 0.58, 0.32) if hp < max_hp() * 0.4 else Color(0.82, 0.9, 0.76)

func target_point(enemy: Zombie) -> Vector3:
	if enemy is Earthworm: return enemy.aim_point()
	# Aim inside an animated torso hitbox, including hunched/leaning variants.
	for volume in enemy._shot_volumes:
		var bone: String = volume.bone_name.to_lower()
		if "spine" in bone or "chest" in bone: return volume.to_global(volume.center)
	for area in enemy._hitboxes:
		var bone: String = str(area.get_parent().bone_name).to_lower()
		if not ("spine" in bone or "chest" in bone): continue
		var shape: CollisionShape3D = area.get_child(0)
		if not shape.has_meta("tower_center"):
			var center := Vector3.ZERO
			var points: PackedVector3Array = shape.shape.points
			for point in points: center += point
			shape.set_meta("tower_center",center/maxi(1,points.size()))
		return shape.to_global(shape.get_meta("tower_center"))
	return enemy.global_position+Vector3.UP*enemy.height*0.55

func can_see(z: Zombie) -> bool:
	if not is_instance_valid(z) or not z.targetable(): return false
	var direction := z.global_position - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.01:
		var yaw := atan2(-direction.x, -direction.z)
		if absf(angle_difference(rotation.y, yaw)) > HALF_ARC: return false
	var aim := target_point(z)
	if muzzle.global_position.distance_squared_to(aim) > pow(attack_range(), 2): return false
	var q := PhysicsRayQueryParameters3D.create(muzzle.global_position, aim, Zombie.SHOT_MASK, [body.get_rid()])
	q.collide_with_areas = true
	if not z._shot_volumes.is_empty() and z._hitboxes.is_empty():
		# Reject a covered target before searching every other enemy for an
		# occluder. Limbs protruding in front of cover remain valid targets.
		q.collision_mask = 1 | 8
		var world_hit := get_world_3d().direct_space_state.intersect_ray(q)
		var endpoint: Vector3 = world_hit.position if not world_hit.is_empty() else aim
		var exposed := false
		for volume in z._shot_volumes:
			if not volume.intersect(q.from, endpoint, false).is_empty():
				exposed = true
				break
		if not exposed: return false
		q.collision_mask = Zombie.SHOT_MASK
	var hit := Zombie.cast_ray(self, q)
	return Zombie.from_hit(hit) == z

func _physics_process(delta: float) -> void:
	_flash_t = maxf(0, _flash_t - delta)
	_trace_travel += delta * 280.0
	tracer.visible = _trace_travel < _trace_distance and kind in ["standard", "mg42"]
	if tracer.visible:
		var length := minf(2.2, minf(_trace_travel, _trace_distance - _trace_travel))
		tracer.global_position = _trace_origin + _trace_direction * _trace_travel
		tracer.scale = Vector3(0.7, 0.7, maxf(0.02, length))
	flash.visible = _flash_t > 0
	flash.light_energy = (1.7 + sin(Time.get_ticks_msec() * 0.067) * 0.3) if kind == "flame" else 3.5 * clampf(_flash_t / 0.045, 0, 1)
	# Exact damped-spring solution: the mesh recoils, the ballistic aim and seat stay stable.
	var omega := 15.0 if kind == "mortar" else 24.0
	var impulse := _recoil_velocity + omega * _recoil
	var decay := exp(-omega * delta)
	_recoil = (_recoil + impulse * delta) * decay
	_recoil_velocity = (_recoil_velocity - omega * impulse * delta) * decay
	if _weapon_model:
		_weapon_model.position = _model_rest + Vector3(0, 0, _recoil)
		_weapon_model.rotation.x = _recoil * 0.4
	gun.rotation.y = lerp_angle(gun.rotation.y, aim_yaw, minf(1, delta * 4.0))
	gun.rotation.x = lerp_angle(gun.rotation.x,0.0 if kind=="tesla" else maxf(0.8,aim_pitch) if kind=="mortar" else aim_pitch,minf(1,delta*4.0))
	if replica or NetSession.is_client() or not game.started or game.over: return
	cooldown -= delta
	heat = maxf(0, heat - delta * (0.3 if overheated else 0.1))
	if overheated and heat <= 0.05: overheated = false
	if operator_peer:
		var p: Player = NetSession.world.actor(operator_peer) if NetSession.enabled else game.player
		if not is_instance_valid(p) or not p.alive:
			game.defences.release_tower(self)
			return
		p.global_position = seat_position()
		control_timeout -= delta
		if control_timeout <= 0:
			trigger = false
			aiming = false
		if trigger and cooldown <= 0 and not overheated:
			var basis := p.camera.global_basis
			var direction := preload("res://scripts/aim_model.gd").sample_direction(-basis.z, basis.x, basis.y, manual_spread(), randf(), randf() * TAU)
			var aim := p.camera.global_position + direction*attack_range()
			var ray := PhysicsRayQueryParameters3D.create(p.camera.global_position,aim,Zombie.SHOT_MASK,[body.get_rid(),p.get_rid()])
			ray.collide_with_areas = true
			var hit := Zombie.cast_ray(self, ray)
			fire_at(hit.position if not hit.is_empty() else aim)
		return
	_scan -= delta
	if _scan <= 0:
		_scan = 0.25
		target = null
		var candidates: Array[Zombie] = []
		var reach_squared := pow(attack_range(), 2)
		for z in game.zombies_root.get_children():
			if not z is Zombie or not z.alive: continue
			if muzzle.global_position.distance_squared_to(target_point(z)) > reach_squared: continue
			candidates.append(z)
		# Preserve nearest-visible targeting, but stop after the first visible
		# candidate instead of casting through the horde in spawn order.
		candidates.sort_custom(func(a: Zombie, b: Zombie): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
		for z in candidates:
			if can_see(z):
				target = z
				break
	if not is_instance_valid(target) or not target.alive: return
	var direction := target_point(target) - gun.global_position
	aim_yaw = wrapf(atan2(-direction.x, -direction.z) - rotation.y, -PI, PI)
	aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	if cooldown <= 0 and not overheated and absf(angle_difference(gun.rotation.y, aim_yaw)) < 0.12 and (kind in ["tesla","mortar"] or absf(angle_difference(gun.rotation.x, aim_pitch)) < 0.12) and can_see(target):
		shoot()

func shoot() -> void:
	if not is_instance_valid(target) or not target.alive: return
	var aim := target_point(target)
	# Ballistic dispersion can miss; world geometry and other enemies stop each shot.
	var distance := muzzle.global_position.distance_to(aim)
	aim += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * distance * 0.009
	fire_at(aim)

func fire_at(aim: Vector3) -> void:
	chain_points.clear()
	cooldown = float(spec().rate) * (1.0-(level-1)*0.1)
	heat = minf(1, heat + float(spec().heat))
	if heat >= 0.99: overheated = true
	var direction := (aim - muzzle.global_position).normalized()
	var end: Vector3 = muzzle.global_position + direction * attack_range()
	var q := PhysicsRayQueryParameters3D.create(muzzle.global_position, end, Zombie.SHOT_MASK, [body.get_rid()])
	q.collide_with_areas = true
	var hit := Zombie.cast_ray(self, q)
	last_impact = hit.position if not hit.is_empty() else end
	var z := Zombie.from_hit(hit)
	if not z and kind in ["standard", "mg42"]:
		preload("res://scripts/bullet_impacts.gd").hit(game, hit)
	if kind != "mortar" and not hit.is_empty():
		game.hunting.hit(hit.collider, float(spec().damage) + (level - 1) * 7.0, operator_peer if operator_peer else owner_peer)
	match kind:
		"mortar":
			last_impact = muzzle.global_position + (aim - muzzle.global_position).limit_length(attack_range())
			launch_shell(true)
		"flame":
			for enemy in game.zombies_root.get_children():
				if not enemy is Zombie or not enemy.alive: continue
				var offset: Vector3 = target_point(enemy)-muzzle.global_position
				if offset.length()<=attack_range() and offset.normalized().dot(direction)>cos(deg_to_rad(20)) and clear_ray(muzzle.global_position,enemy):
					hurt(enemy,direction)
		"tesla":
			if z and z.alive:
				var chained: Array[Zombie] = [z]
				var previous := z
				hurt(z,direction)
				for i in 2+level:
					var next: Zombie
					var best := 7.0
					for enemy in game.zombies_root.get_children():
						if not enemy is Zombie or not enemy.alive or enemy in chained: continue
						var gap: float = previous.global_position.distance_to(enemy.global_position)
						if gap<best and clear_ray(previous.global_position+Vector3.UP*previous.height*0.7,enemy):
							next = enemy
							best = gap
					if not next: break
					chain_points.append(target_point(previous))
					chain_points.append(target_point(next))
					hurt(next,direction,0.75)
					chained.append(next)
					previous = next
		_:
			if z and z.alive: hurt(z,direction)
	shots += 1
	show_shot()

func hurt(enemy: Zombie, direction: Vector3, multiplier := 1.0) -> void:
	enemy.killer_peer = operator_peer if operator_peer else owner_peer
	enemy.killer_weapon = "tower"
	enemy.last_headshot = false
	enemy.damage((float(spec().damage)+(level-1)*7.0)*multiplier,direction)

func clear_ray(from: Vector3, enemy: Zombie) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from,target_point(enemy),1|8,[body.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func launch_shell(authoritative: bool) -> void:
	var shell = preload("res://scripts/tower_shell.gd").new()
	shell.start = muzzle.global_position
	shell.destination = last_impact
	shell.damage_amount = float(spec().damage)+(level-1)*35.0
	shell.owner_peer = operator_peer if operator_peer else owner_peer
	shell.authoritative = authoritative
	shell.excluded.append(body.get_rid())
	shell.game = game
	game.add_child(shell)

func _build_variant(steel: Material, copper: Material) -> void:
	var path := "res://assets/models/tower_%s.glb" % kind
	if kind == "standard" and not ResourceLoader.exists(path): return
	for child in gun.get_children():
		if child is MeshInstance3D: child.hide()
	if ResourceLoader.exists(path):
		if not _model_scenes.has(path): _model_scenes[path] = load(path)
		var model: Node3D = _model_scenes[path].instantiate()
		model.name = "WeaponModel"
		gun.add_child(model)
		if kind=="flame": gun.position.y = 3.4
	else:
		# Functional preview while generated assets are being imported.
		box(gun,Vector3(0.6,0.5,0.8),Vector3.ZERO,steel)
		var barrel := cylinder(gun,0.2 if kind=="mortar" else 0.07,1.7,Vector3(0,0,-0.9),steel)
		barrel.rotation.x = PI/2
		if kind=="flame":
			for x in [-0.5,0.5]: cylinder(gun,0.2,0.9,Vector3(x,0,0.25),material(Color(0.5,0.12,0.06)))
		if kind=="tesla":
			barrel.hide()
			for i in 9: cylinder(gun,0.35,0.055,Vector3(0,0.1+i*0.09,0),copper)
	if kind=="tesla": muzzle.position = Vector3(0,1.25,0)

func show_shot() -> void:
	if not is_inside_tree() or not muzzle: return
	var start := muzzle.global_position
	var direction := last_impact - start
	if direction.length() < 0.05: return
	if not shot_audio:
		shot_audio = preload("res://scripts/tower_audio.gd").new()
		shot_audio.tower = self
		muzzle.add_child(shot_audio)
	shot_audio.fire()
	fx.global_basis = muzzle.global_basis if kind == "mortar" else Basis.looking_at(direction.normalized(), Vector3.UP)
	fx.fire(minf(direction.length(), attack_range()))
	_recoil_velocity = minf(7, _recoil_velocity + (6.0 if kind == "mortar" else 1.3 if kind == "mg42" else 1.8 if kind == "standard" else 0.12 if kind == "flame" else 0.0))
	_flash_t = 0.20 if kind == "flame" else 0.09 if kind == "mortar" else 0.045
	flash.light_color = Color(0.3, 0.6, 1) if kind == "tesla" else Color(1, 0.58, 0.18)
	if operator_peer == game.player.peer_id:
		game.player.add_tremor(0.22 if kind == "mortar" else 0.045, 0.18)
	if kind == "mortar":
		if replica or NetSession.is_client(): launch_shell(false)
		return
	if kind == "tesla":
		var links := PackedVector3Array([start, last_impact])
		links.append_array(chain_points)
		_lightning.fire(links)
	_trace_origin = start
	_trace_direction = direction.normalized()
	_trace_distance = minf(direction.length(), attack_range()) if kind != "mg42" or shots % 3 == 0 else 0.0
	_trace_travel = 0.0
	tracer.global_position = start
	tracer.look_at(last_impact, Vector3.UP)
