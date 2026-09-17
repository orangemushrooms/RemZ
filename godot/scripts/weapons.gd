# Pistol and shotgun: view models under the camera, hitscan against zombies, muzzle flash.
class_name Weapons
extends Node3D

const DEFS := {
	"pistol": { "name": "Pistole", "model": "pistol", "height": 0.15, "mag": 12, "reserve": 72, "damage": 34.0, "rate": 0.22, "reload": 1.1, "pellets": 1, "spread": 0.012, "range": 60.0, "kick": 0.05, "sfx": "pistol", "pos": Vector3(0.24, -0.2, -0.5) },
	"shotgun": { "name": "Schrotflinte", "model": "rifle", "height": 0.2, "mag": 6, "reserve": 24, "damage": 22.0, "rate": 0.85, "reload": 2.0, "pellets": 8, "spread": 0.07, "range": 28.0, "kick": 0.16, "sfx": "shotgun", "pos": Vector3(0.22, -0.24, -0.6) },
}

var player: Player
var hud: Hud
var camera: Camera3D
var state := {}
var current := "pistol"
var unlocked := { "pistol": true, "shotgun": false }
var recoil := 0.0
var sway_t := 0.0
var flash: OmniLight3D
var zombies_root: Node3D

func setup(p: Player, h: Hud, zr: Node3D) -> void:
	player = p
	hud = h
	camera = p.camera
	zombies_root = zr
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		var holder := Node3D.new()
		holder.position = d["pos"]
		var scene = load("res://assets/models/%s.glb" % d["model"])
		if scene:
			var model: Node3D = scene.instantiate()
			# Meshy weapons come in side view along X: turn the barrel to face forward (-Z)
			model.rotation.y = -PI / 2.0
			var inner := Node3D.new()
			inner.add_child(model)
			holder.add_child(inner)
			_fit_height(model, d["height"])
			for m in model.find_children("*", "MeshInstance3D", true, false):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.visible = false
		camera.add_child(holder)
		state[id] = { "def": d, "ammo": d["mag"], "reserve": d["reserve"], "node": holder, "cooldown": 0.0, "reloading": 0.0 }
	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.45)
	flash.light_energy = 0.0
	flash.omni_range = 10.0
	flash.position = Vector3(0.2, -0.15, -0.9)
	camera.add_child(flash)
	set_weapon("pistol")

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
	if not unlocked.get(id, false):
		hud.message("Schrotflinte ab Welle 3", 1.2)
		return
	for s in state.values():
		s["node"].visible = false
	current = id
	cur()["node"].visible = true
	cur()["reloading"] = 0.0
	update_hud()

func unlock(id: String) -> void:
	unlocked[id] = true

func add_ammo(id: String, n: int) -> void:
	state[id]["reserve"] += n
	update_hud()

func update_hud() -> void:
	var s := cur()
	hud.set_ammo(s["ammo"], s["reserve"], s["def"]["name"])

func reload() -> void:
	var s := cur()
	if s["reloading"] > 0.0 or s["ammo"] == s["def"]["mag"] or s["reserve"] <= 0:
		return
	s["reloading"] = s["def"]["reload"]
	Sfx.play(self, "reload", -8.0)

func try_fire() -> void:
	if not player.active or not player.alive:
		return
	var s := cur()
	if s["cooldown"] > 0.0 or s["reloading"] > 0.0:
		return
	if s["ammo"] <= 0:
		Sfx.play(self, "empty", -10.0)
		reload()
		return
	var d: Dictionary = s["def"]
	s["ammo"] -= 1
	s["cooldown"] = d["rate"]
	recoil = 1.0
	Sfx.play(self, d["sfx"], -4.0)
	flash.light_energy = 8.0
	var origin := camera.global_position
	var base := -camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	for i in int(d["pellets"]):
		var dir: Vector3 = (base + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * float(d["spread"])).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * float(d["range"]), 1 | 2 | 8)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit and hit.collider is Zombie:
			var z: Zombie = hit.collider
			var headshot: bool = hit.position.y > z.global_position.y + z.height * 0.78
			z.damage(float(d["damage"]) * (2.2 if headshot else 1.0), dir)
			_blood(hit.position, dir)
	update_hud()

func _blood(pos: Vector3, dir: Vector3) -> void:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = dir
	mat.spread = 40.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	mat.color = Color(0.35, 0.02, 0.02)
	p.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.02, 0.02)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mm
	p.draw_pass_1 = mesh
	p.amount = 12
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 1.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _process(delta: float) -> void:
	if not player or not player.active:
		return
	var s := cur()
	var d: Dictionary = s["def"]
	s["cooldown"] = maxf(0.0, s["cooldown"] - delta)
	if s["reloading"] > 0.0:
		s["reloading"] -= delta
		if s["reloading"] <= 0.0:
			var need: int = d["mag"] - s["ammo"]
			var take: int = mini(need, s["reserve"])
			s["ammo"] += take
			s["reserve"] -= take
			s["reloading"] = 0.0
			update_hud()
	if Input.is_action_just_pressed("fire"):
		try_fire()
	if Input.is_action_just_pressed("reload"):
		reload()
	if Input.is_action_just_pressed("weapon_1"):
		set_weapon("pistol")
	if Input.is_action_just_pressed("weapon_2"):
		set_weapon("shotgun")
	recoil = maxf(0.0, recoil - delta * 7.0)
	sway_t += delta
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	var n: Node3D = s["node"]
	var pos: Vector3 = d["pos"]
	n.position = pos + Vector3(sin(sway_t * 5.0) * (0.008 if moving else 0.002), absf(sin(sway_t * 5.0)) * (0.01 if moving else 0.003) + (-0.12 if s["reloading"] > 0.0 else 0.0), recoil * float(d["kick"]))
	n.rotation.x = -recoil * 0.35 + (-0.4 if s["reloading"] > 0.0 else 0.0)
	flash.light_energy *= 0.6
	if flash.light_energy < 0.1:
		flash.light_energy = 0.0
