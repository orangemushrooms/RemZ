# Weapons: five guns with COD-style recoil (camera kick + view-model kick), aim down sights,
# muzzle flash, hitscan against zombies, plus hand grenades.
class_name Weapons
extends Node3D

const DEFS := {
	"pistol":   { "name": "Pistole", "model": "pistol", "height": 0.11, "mag": 12, "reserve": 72, "damage": 34.0, "rate": 0.16, "reload": 1.1, "pellets": 1, "spread": 0.012, "range": 60.0, "auto": false, "sfx": "pistol",
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
var state := {}
var current := "pistol"
var unlocked := { "pistol": true, "revolver": false, "smg": false, "ak47": false, "shotgun": false }
var recoil := 0.0
var sway_t := 0.0
var flash: OmniLight3D
var flash_mesh: MeshInstance3D
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
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		var holder := Node3D.new()
		holder.position = d["pos"]
		var path := "res://assets/models/%s.glb" % d["model"]
		var scene = load(path) if ResourceLoader.exists(path) else null
		if scene:
			var model: Node3D = scene.instantiate()
			model.rotation.y = -PI / 2.0   # Meshy weapons come in side view along X
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
		camera.add_child(holder)
		state[id] = { "def": d, "ammo": d["mag"], "reserve": d["reserve"], "node": holder, "cooldown": 0.0, "reloading": 0.0 }
	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.45)
	flash.light_energy = 0.0
	flash.omni_range = 10.0
	flash.position = Vector3(0.2, -0.15, -0.9)
	camera.add_child(flash)
	flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	flash_mesh.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.8, 0.5)
	fm.albedo_texture = Foliage._soft_dot()
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mesh.material_override = fm
	flash_mesh.visible = false
	flash_mesh.position = Vector3(0.24, -0.16, -0.95)
	camera.add_child(flash_mesh)
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
	for s in state.values():
		s["node"].visible = false
	current = id
	cur()["node"].visible = true
	cur()["reloading"] = 0.0
	ads = 0.0
	_shots_in_burst = 0
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
	Sfx.play(self, d["sfx"], -6.0)
	flash.light_energy = 10.0
	flash_mesh.visible = true
	flash_mesh.scale = Vector3.ONE * randf_range(0.7, 1.3)
	flash_mesh.rotation.z = randf() * TAU
	# recoil climbs while holding the trigger, drifts sideways, less when aiming
	_shots_in_burst += 1
	_burst_t = 0.25
	var climb := minf(1.0 + _shots_in_burst * 0.12, 2.2)
	var aim_f := 1.0 - ads * 0.45
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

func _blood(pos: Vector3, dir: Vector3) -> void:
	var p := _blood_pool[_blood_next]
	_blood_next = (_blood_next + 1) % _blood_pool.size()
	p.global_position = pos
	(p.process_material as ParticleProcessMaterial).direction = dir
	p.restart()
	p.emitting = true

func _prepare_blood_pool() -> void:
	var mat := ParticleProcessMaterial.new()
	mat.spread = 40.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	mat.color = Color(0.35, 0.02, 0.02)
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.02, 0.02)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mm
	for i in 16:
		var p := GPUParticles3D.new()
		p.process_material = mat.duplicate()
		p.draw_pass_1 = mesh
		p.amount = 14
		p.lifetime = 0.6
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-4, -5, -4), Vector3(8, 10, 8))
		get_parent().add_child(p)
		_blood_pool.append(p)

func _process(delta: float) -> void:
	if not player or not player.active:
		return
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
	var applied_pitch := kick_pitch * minf(1.0, delta * rec)
	var applied_yaw := kick_yaw * minf(1.0, delta * rec)
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
	var base_pos: Vector3 = (d["pos"] as Vector3).lerp(d["ads"], ads)
	var sway_amp := 1.0 - ads * 0.8
	n.position = base_pos + Vector3(sin(sway_t * 5.0) * (0.008 if moving else 0.002) * sway_amp, absf(sin(sway_t * 5.0)) * (0.01 if moving else 0.003) * sway_amp + (-0.12 if s["reloading"] > 0.0 else 0.0), recoil * float(d["kick_back"]))
	n.rotation.x = -recoil * 0.3 + (-0.4 if s["reloading"] > 0.0 else 0.0)
	n.rotation.z = recoil * 0.05 * (1.0 if _shots_in_burst % 2 == 0 else -1.0)
	flash.light_energy *= exp(-36.0 * delta)
	if flash.light_energy < 0.2:
		flash.light_energy = 0.0
		flash_mesh.visible = false
