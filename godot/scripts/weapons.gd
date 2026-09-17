# Weapons: five guns with COD-style recoil (camera kick + view-model kick), aim down sights,
# muzzle flash, hitscan against zombies, plus hand grenades.
class_name Weapons
extends Node3D

const Hands = preload("res://scripts/viewmodel_hands.gd")
const Viewmodel = preload("res://scripts/viewmodel_viewport.gd")
const Effects = preload("res://scripts/weapon_effects.gd")

const DEFS := {
	"pistol":   { "name": "Pistole", "model": "pistol", "height": 0.11, "mag": 12, "reserve": 72, "damage": 34.0, "rate": 0.16, "reload": 1.1, "pellets": 1, "spread": 0.012, "range": 60.0, "auto": false, "sfx": "pistol", "sfx_db": 2.0,
				  "pos": Vector3(0.26, -0.21, -0.5), "ads": Vector3(0.0, -0.13, -0.38), "kick_pitch": 1.4, "kick_yaw": 0.5, "kick_back": 0.06, "recover": 9.0 },
	"revolver": { "name": "Revolver", "model": "revolver", "height": 0.13, "mag": 6, "reserve": 30, "damage": 95.0, "rate": 0.45, "reload": 2.2, "pellets": 1, "spread": 0.008, "range": 80.0, "auto": false, "sfx": "revolver",
				  "pos": Vector3(0.26, -0.21, -0.5), "ads": Vector3(0.0, -0.13, -0.38), "kick_pitch": 4.0, "kick_yaw": 1.2, "kick_back": 0.12, "recover": 7.0 },
	"smg":      { "name": "MP5", "model": "smg", "height": 0.16, "mag": 30, "reserve": 120, "damage": 22.0, "rate": 0.075, "reload": 1.6, "pellets": 1, "spread": 0.03, "range": 45.0, "auto": true, "sfx": "smg",
				  "pos": Vector3(0.24, -0.22, -0.55), "ads": Vector3(0.0, -0.135, -0.4), "kick_pitch": 0.7, "kick_yaw": 0.45, "kick_back": 0.04, "recover": 12.0 },
	"ak47":     { "name": "AK-47", "model": "ak47", "height": 0.18, "mag": 30, "reserve": 90, "damage": 42.0, "rate": 0.1, "reload": 2.0, "pellets": 1, "spread": 0.022, "range": 90.0, "auto": true, "sfx": "ak47",
				  "pos": Vector3(0.24, -0.23, -0.58), "ads": Vector3(0.0, -0.14, -0.42), "kick_pitch": 1.1, "kick_yaw": 0.7, "kick_back": 0.06, "recover": 10.0 },
	"shotgun":  { "name": "Schrotflinte", "model": "rifle", "height": 0.16, "mag": 6, "reserve": 24, "damage": 22.0, "rate": 0.85, "reload": 2.0, "pellets": 8, "spread": 0.07, "range": 28.0, "auto": false, "sfx": "shotgun",
				  "pos": Vector3(0.22, -0.24, -0.6), "ads": Vector3(0.0, -0.15, -0.45), "kick_pitch": 5.0, "kick_yaw": 1.5, "kick_back": 0.16, "recover": 6.0 },
}
const ORDER := ["pistol", "revolver", "smg", "ak47", "shotgun"]

var player: Player
var hud: Hud
var camera: Camera3D
var viewmodel: ViewmodelViewport
var state := {}
var current := "pistol"
var unlocked := { "pistol": true, "revolver": false, "smg": false, "ak47": false, "shotgun": false }
var recoil := 0.0
var sway_t := 0.0
var flash: OmniLight3D
var flash_mesh: MeshInstance3D
var effects: WeaponEffects
var _model_kick := Vector3.ZERO # pitch (radians), roll (radians), rearward distance
var _model_velocity := Vector3.ZERO
var zombies_root: Node3D
# upgrades (from the skill menu)
var damage_mul := 1.0
var reload_mul := 1.0
var spread_mul := 1.0
var grenades := 2
var grenades_max := 2
# recoil state
var kick_pitch := 0.0
var kick_yaw := 0.0
var ads := 0.0
var _shots_in_burst := 0
var _burst_t := 0.0
var _grenade_scene: PackedScene
var _blood_pool: Array[GPUParticles3D] = []
var _blood_next := 0

func setup(p: Player, h: Hud, zr: Node3D) -> void:
	player = p
	hud = h
	camera = p.camera
	zombies_root = zr
	viewmodel = Viewmodel.new()
	add_child(viewmodel)
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		var holder := Node3D.new()
		holder.position = d["pos"]
		var path := "res://assets/models/%s.glb" % d["model"]
		var scene = load(path) if ResourceLoader.exists(path) else null
		if scene:
			var model: Node3D = scene.instantiate()
			# This asset's barrel faces the opposite way to the other Meshy guns.
			model.rotation.y = PI / 2.0 if id == "ak47" else -PI / 2.0
			var inner := Node3D.new()
			inner.add_child(model)
			holder.add_child(inner)
			_fit_height(model, d["height"])
			for m in model.find_children("*", "MeshInstance3D", true, false):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.06, 0.3)
			box.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.12, 0.12, 0.13)
			box.material_override = mat
			holder.add_child(box)
		holder.visible = false
		viewmodel.camera.add_child(holder)
		var bounds := Hands.weapon_bounds(holder)
		var hands := Hands.build(id, bounds)
		holder.add_child(hands)
		for mesh in holder.find_children("*", "MeshInstance3D", true, false):
			mesh.layers = 2
		var aim_position: Vector3 = d["ads"]
		aim_position.y = -bounds.end.y - 0.008
		aim_position.z = minf(aim_position.z, -bounds.end.z - 0.18)
		state[id] = { "def": d, "ammo": d["mag"], "reserve": d["reserve"], "node": holder, "hands": hands, "bounds": bounds, "aim_position": aim_position, "cooldown": 0.0, "reloading": 0.0 }
	# Gentle light on the view model keeps hands readable in deep forest shade.
	var view_light := DirectionalLight3D.new()
	view_light.light_cull_mask = 2
	view_light.light_color = Color(0.9, 0.94, 1.0)
	view_light.light_energy = 0.7
	view_light.shadow_enabled = false
	view_light.rotation_degrees = Vector3(-18, -20, 0)
	view_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	viewmodel.camera.add_child(view_light)
	effects = Effects.new()
	viewmodel.camera.add_child(effects)
	effects.setup(camera)
	flash = effects.world_light
	flash_mesh = effects.front
	var gp := "res://assets/models/grenade.glb"
	_grenade_scene = load(gp) if ResourceLoader.exists(gp) else null
	set_weapon("pistol")
	_prepare_blood_pool()

static func _fit_height(node: Node3D, height: float) -> void:
	var aabb := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).get_aabb()
		var t: Transform3D = node.global_transform.affine_inverse() * (m as Node3D).global_transform if node.is_inside_tree() else (m as Node3D).transform
		b = t * b
		aabb = b if first else aabb.merge(b)
		first = false
	if aabb.size.y > 0.0:
		var s := height / aabb.size.y
		node.scale = Vector3.ONE * s
		node.position = Vector3(-aabb.get_center().x * s, -aabb.get_center().y * s, -aabb.get_center().z * s)

func cur() -> Dictionary:
	return state[current]

func set_weapon(id: String) -> void:
	if not DEFS.has(id):
		return
	if not unlocked.get(id, false):
		hud.message("%s im Skillmenü (Tab) freischalten" % DEFS[id]["name"], 1.4)
		return
	if current == id and cur()["node"].visible:
		return
	cur()["reloading"] = 0.0
	(cur()["hands"] as ViewmodelHands).reset_motion()
	for s in state.values():
		s["node"].visible = false
	current = id
	cur()["node"].visible = true
	cur()["reloading"] = 0.0
	ads = 0.0
	_shots_in_burst = 0
	_model_kick = Vector3.ZERO
	_model_velocity = Vector3.ZERO
	recoil = 0.0
	effects.cancel_flash()
	(cur()["hands"] as ViewmodelHands).reset_motion()
	var holder: Node3D = cur()["node"]
	holder.position = cur()["def"]["pos"]
	holder.rotation = Vector3.ZERO
	effects.sync_muzzle(muzzle_transform())
	hud.set_reload(0.0, 1.0)
	update_hud()

func unlock(id: String) -> void:
	unlocked[id] = true

func add_ammo(id: String, n: int) -> void:
	state[id]["reserve"] += n
	update_hud()

func refill_all() -> void:
	for id in state:
		if unlocked[id]:
			state[id]["reserve"] += int(DEFS[id]["mag"]) * 3
	grenades = grenades_max
	update_hud()

func update_hud() -> void:
	var s := cur()
	hud.set_ammo(s["ammo"], s["reserve"], "%s   ·   Granaten %d" % [s["def"]["name"], grenades])

func reload() -> void:
	var s := cur()
	if s["reloading"] > 0.0 or s["ammo"] == s["def"]["mag"] or s["reserve"] <= 0:
		return
	s["reloading"] = float(s["def"]["reload"]) * reload_mul
	Sfx.play(self, "reload", -8.0)

func try_fire() -> void:
	if not player.active or not player.alive:
		return
	var s := cur()
	if s["cooldown"] > 0.0 or s["reloading"] > 0.0:
		return
	if s["ammo"] <= 0:
		s["cooldown"] = 0.2
		Sfx.play(self, "empty", -10.0)
		reload()
		return
	var d: Dictionary = s["def"]
	s["ammo"] -= 1
	s["cooldown"] = maxf(s["cooldown"], -float(d["rate"])) + float(d["rate"])
	recoil = 1.0
	Sfx.play(self, d["sfx"], float(d.get("sfx_db", -6.0)))
	effects.fire(current, muzzle_transform(), player.velocity)
	# recoil climbs while holding the trigger, drifts sideways, less when aiming
	_shots_in_burst += 1
	_burst_t = 0.25
	var climb := minf(1.0 + _shots_in_burst * 0.12, 2.2)
	var aim_f := 1.0 - ads * 0.45
	var impulse := Vector3(deg_to_rad(float(d["kick_pitch"]) * 2.2 + 1.0), deg_to_rad(0.7 if _shots_in_burst % 2 == 0 else -0.7), float(d["kick_back"]) * 0.65) * aim_f
	_model_kick += impulse * 0.25
	_model_velocity += impulse * (22.0 + float(d["recover"])) * 1.7
	(s["hands"] as ViewmodelHands).shot_impulse(0.6 + float(d["kick_pitch"]) * 0.16)
	kick_pitch += float(d["kick_pitch"]) * climb * aim_f * randf_range(0.85, 1.15)
	kick_yaw += float(d["kick_yaw"]) * aim_f * randf_range(-1.0, 1.0) * (1.0 if _shots_in_burst % 2 == 0 else -0.6)
	player.wobble = maxf(player.wobble, 0.35)
	var origin := camera.global_position
	var base := -camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var spread: float = float(d["spread"]) * spread_mul * (1.0 - ads * 0.6) * (1.0 + minf(_shots_in_burst, 8) * 0.06)
	for i in int(d["pellets"]):
		var dir: Vector3 = (base + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * float(d["range"]), 1 | 2 | 8)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit and hit.collider is Breakable:
			(hit.collider as Breakable).shatter()
		if hit and hit.collider is Zombie:
			var z: Zombie = hit.collider
			var headshot: bool = hit.position.y > z.global_position.y + z.height * 0.78
			z.damage(float(d["damage"]) * damage_mul * (2.2 if headshot else 1.0), dir)
			_blood(hit.position, dir)
			hud.hitmarker(headshot)
	update_hud()

func throw_grenade() -> void:
	if not player.active or not player.alive or grenades <= 0:
		return
	grenades -= 1
	update_hud()
	var g := Grenade.new()
	g.setup(_grenade_scene, zombies_root, player)
	get_tree().current_scene.add_child(g)
	var dir := -camera.global_transform.basis.z
	g.global_position = camera.global_position + dir * 0.6 + Vector3(0.2, -0.1, 0)
	g.linear_velocity = dir * 15.0 + Vector3(0, 4.0, 0) + player.velocity
	g.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	player.wobble = maxf(player.wobble, 0.2)

var _mist_pool: Array[GPUParticles3D] = []
var _decal_pool: Array[Decal] = []
var _decal_next := 0
var _splat_tex: ImageTexture

func _blood(pos: Vector3, dir: Vector3) -> void:
	var p := _blood_pool[_blood_next]
	var m := _mist_pool[_blood_next]
	_blood_next = (_blood_next + 1) % _blood_pool.size()
	p.global_position = pos
	m.global_position = pos
	(p.process_material as ParticleProcessMaterial).direction = (dir + Vector3(0, 0.25, 0)).normalized()
	(m.process_material as ParticleProcessMaterial).direction = dir
	p.restart()
	m.restart()
	p.emitting = true
	m.emitting = true
	# splat: on the ground below the wound, and on whatever the exit direction hits within 2.5 m
	var space: PhysicsDirectSpaceState3D = get_parent().get_world_3d().direct_space_state
	for ray in [[pos + Vector3(0, 0.3, 0), pos + Vector3(0, -3.0, 0), 0.7], [pos, pos + dir * 2.5, 0.5]]:
		var q := PhysicsRayQueryParameters3D.create(ray[0], ray[1], 1)
		var hit: Dictionary = space.intersect_ray(q)
		if hit:
			_splat(hit.position, hit.normal, ray[2] * randf_range(0.6, 1.4))

func _splat(pos: Vector3, normal: Vector3, size: float) -> void:
	var d := _decal_pool[_decal_next]
	_decal_next = (_decal_next + 1) % _decal_pool.size()
	d.size = Vector3(size, 0.6, size)
	d.global_position = pos + normal * 0.02
	var up := Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP
	d.look_at_from_position(d.global_position, pos - normal, up)
	d.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	d.modulate = Color(randf_range(0.3, 0.45), 0.02, 0.02, 1.0)
	d.visible = true

static func _make_splat_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var blobs: Array = []
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.42) * n
		blobs.append([Vector2(n / 2.0 + cos(a) * r * 0.5, n / 2.0 + sin(a) * r * 0.5), rng.randf_range(0.03, 0.22) * n])
	for y in n:
		for x in n:
			var v := 0.0
			for b in blobs:
				var dd: float = (b[0] as Vector2).distance_to(Vector2(x, y)) / (b[1] as float)
				v += maxf(0.0, 1.0 - dd * dd)
			var alpha := clampf((v - 0.35) * 2.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.4, 0.02, 0.02, alpha))
	return ImageTexture.create_from_image(img)

func _prepare_blood_pool() -> void:
	var dot := Foliage._soft_dot()
	# droplets: small billboards, dark red, fall with gravity and shrink
	var mat := ParticleProcessMaterial.new()
	mat.spread = 32.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0, -12.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	mat.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.04, 0.03, 1.0))
	grad.set_color(1, Color(0.25, 0.01, 0.01, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var qm := StandardMaterial3D.new()
	qm.albedo_texture = dot
	qm.vertex_color_use_as_albedo = true
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = qm
	# mist: a few big soft puffs that hang for a moment
	var mm := ParticleProcessMaterial.new()
	mm.spread = 50.0
	mm.initial_velocity_min = 0.6
	mm.initial_velocity_max = 2.0
	mm.gravity = Vector3(0, -1.0, 0)
	mm.scale_min = 1.0
	mm.scale_max = 2.5
	mm.damping_min = 2.0
	mm.damping_max = 4.0
	var mg := Gradient.new()
	mg.set_color(0, Color(0.45, 0.03, 0.02, 0.55))
	mg.set_color(1, Color(0.3, 0.02, 0.02, 0.0))
	var mgt := GradientTexture1D.new()
	mgt.gradient = mg
	mm.color_ramp = mgt
	var mq := QuadMesh.new()
	mq.size = Vector2(0.25, 0.25)
	mq.material = qm
	for i in 16:
		var p := GPUParticles3D.new()
		p.process_material = mat.duplicate()
		p.draw_pass_1 = quad
		p.amount = 48
		p.lifetime = 0.9
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-5, -6, -5), Vector3(10, 12, 10))
		get_parent().add_child(p)
		_blood_pool.append(p)
		var m := GPUParticles3D.new()
		m.process_material = mm.duplicate()
		m.draw_pass_1 = mq
		m.amount = 10
		m.lifetime = 0.5
		m.one_shot = true
		m.explosiveness = 1.0
		m.emitting = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
		get_parent().add_child(m)
		_mist_pool.append(m)
	_splat_tex = _make_splat_texture()
	for i in 48:
		var d := Decal.new()
		d.texture_albedo = _splat_tex
		d.albedo_mix = 1.0
		d.cull_mask = 1
		d.visible = false
		get_parent().add_child(d)
		_decal_pool.append(d)


func _process(delta: float) -> void:
	if not player or not player.active:
		return
	effects.advance(delta, player.velocity)
	_step_model_recoil(delta)
	for weapon_state: Dictionary in state.values():
		weapon_state["cooldown"] = maxf(-delta, weapon_state["cooldown"] - delta)
	var s := cur()
	var d: Dictionary = s["def"]
	if s["reloading"] > 0.0:
		s["reloading"] -= delta
		if s["reloading"] <= 0.0:
			var need: int = d["mag"] - s["ammo"]
			var take: int = mini(need, s["reserve"])
			s["ammo"] += take
			s["reserve"] -= take
			s["reloading"] = 0.0
			update_hud()
	hud.set_reload(s["reloading"], float(d["reload"]) * reload_mul)
	if d["auto"]:
		if Input.is_action_pressed("fire"):
			try_fire()
	elif Input.is_action_just_pressed("fire"):
		try_fire()
	if Input.is_action_just_pressed("reload"):
		reload()
	if Input.is_action_just_pressed("grenade"):
		throw_grenade()
	for i in ORDER.size():
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			set_weapon(ORDER[i])
	if Input.is_action_just_pressed("weapon_next"):
		var idx := ORDER.find(current)
		for k in ORDER.size():
			idx = (idx + 1) % ORDER.size()
			if unlocked[ORDER[idx]]:
				set_weapon(ORDER[idx])
				break
	s = cur()
	d = s["def"]
	_burst_t -= delta
	if _burst_t <= 0.0:
		_shots_in_burst = 0
	# aim down sights
	var want_ads := 1.0 if Input.is_action_pressed("aim") and s["reloading"] <= 0.0 else 0.0
	ads = lerpf(ads, want_ads, minf(1.0, delta * 10.0))
	camera.fov = lerpf(75.0, 52.0, ads)
	# camera recoil recovery: part of the kick stays (the camera really moved), the rest settles back
	var rec: float = float(d["recover"])
	var applied_pitch := kick_pitch * (1.0 - exp(-delta * rec))
	var applied_yaw := kick_yaw * (1.0 - exp(-delta * rec))
	kick_pitch -= applied_pitch
	kick_yaw -= applied_yaw
	player.pitch = clampf(player.pitch + deg_to_rad(applied_pitch) * 0.35, -1.45, 1.45)
	player.rotate_y(deg_to_rad(applied_yaw) * 0.35)
	player.recoil_offset = Vector2(deg_to_rad(kick_pitch) * 0.65, deg_to_rad(kick_yaw) * 0.65)
	# view model
	recoil = maxf(0.0, recoil - delta * 7.0)
	sway_t += delta
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	var n: Node3D = s["node"]
	var base_pos: Vector3 = (d["pos"] as Vector3).lerp(s["aim_position"], ads)
	var sway_amp := 1.0 - ads * 0.8
	n.position = base_pos + Vector3(sin(sway_t * 5.0) * (0.008 if moving else 0.002) * sway_amp, sin(sway_t * 10.0) * (0.005 if moving else 0.0015) * sway_amp + (-0.12 if s["reloading"] > 0.0 else 0.0), _model_kick.z)
	n.rotation.x = _model_kick.x + (-0.4 if s["reloading"] > 0.0 else 0.0)
	n.rotation.z = _model_kick.y
	(s["hands"] as ViewmodelHands).animate_reload(1.0 - float(s["reloading"]) / (float(d["reload"]) * reload_mul), s["reloading"] > 0.0)
	(s["hands"] as ViewmodelHands).animate_cloth(delta, Vector2(player.velocity.x, player.velocity.z).length(), ads)
	effects.sync_muzzle(muzzle_transform())

func muzzle_transform() -> Transform3D:
	var s := cur()
	var bounds: AABB = s["bounds"]
	var tip := Vector3(bounds.get_center().x, bounds.end.y - 0.015, bounds.position.z - 0.006)
	return (s["node"] as Node3D).transform * Transform3D(Basis.IDENTITY, tip)

func _step_model_recoil(delta: float) -> void:
	# Exact damped-spring integration remains stable during slow frames and pauses.
	var omega := 22.0 + float(cur()["def"]["recover"])
	var damping := 0.62
	var damped := omega * sqrt(1.0 - damping * damping)
	var decay := exp(-damping * omega * delta)
	var c := cos(damped * delta)
	var s := sin(damped * delta)
	var position := _model_kick
	var velocity := _model_velocity
	_model_kick = decay * (position * c + (velocity + damping * omega * position) * s / damped)
	_model_velocity = decay * (velocity * c - (damping * omega * velocity + omega * omega * position) * s / damped)
	_model_kick = _model_kick.clamp(Vector3(-0.08, -0.07, -0.02), Vector3(0.32, 0.07, 0.12))
