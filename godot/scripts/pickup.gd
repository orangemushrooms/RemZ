# Small drop left behind by a killed zombie: an ammunition pack or a grenade. Bobs and glows, is collected by
# walking through it, and fades away after a while so the field never fills up.
class_name Pickup
extends Area3D

const LIFETIME := 45.0

var kind := "ammo"      # "ammo" | "grenade" | "medkit"
var _t := 0.0
var _mesh: Node3D
var _light: OmniLight3D
var _taken := false

func setup(k: String) -> void:
	kind = k
	collision_layer = 0
	collision_mask = 4          # the player
	monitorable = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.7
	cs.shape = sph
	cs.position.y = 0.5
	add_child(cs)
	_mesh = Node3D.new()
	add_child(_mesh)
	var color := Color(0.9, 0.75, 0.3)
	match kind:
		"ammo":
			if not _model("ammo_pack", 0.24):
				_box(Vector3(0.36, 0.2, 0.24), Vector3(0, 0.1, 0), Color(0.3, 0.34, 0.22))
				_box(Vector3(0.38, 0.03, 0.26), Vector3(0, 0.21, 0), Color(0.22, 0.25, 0.16))
				_box(Vector3(0.1, 0.02, 0.27), Vector3(0, 0.225, 0), Color(0.85, 0.7, 0.3))
			color = Color(1.0, 0.8, 0.35)
		"grenade":
			var m := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.09
			s.height = 0.2
			m.mesh = s
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.25, 0.32, 0.18)
			mat.roughness = 0.6
			m.material_override = mat
			m.position.y = 0.12
			_mesh.add_child(m)
			_box(Vector3(0.05, 0.06, 0.05), Vector3(0, 0.24, 0), Color(0.5, 0.5, 0.52))
			color = Color(0.5, 1.0, 0.5)
		_:
			if not _model("medkit", 0.22):
				_box(Vector3(0.3, 0.14, 0.22), Vector3(0, 0.07, 0), Color(0.9, 0.9, 0.88))
				_box(Vector3(0.16, 0.03, 0.05), Vector3(0, 0.15, 0), Color(0.85, 0.1, 0.1))
				_box(Vector3(0.05, 0.03, 0.16), Vector3(0, 0.15, 0), Color(0.85, 0.1, 0.1))
			color = Color(1.0, 0.45, 0.4)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.1
	_light.omni_range = 2.2
	_light.shadow_enabled = false
	_light.position.y = 0.45
	add_child(_light)
	body_entered.connect(_on_body)
	add_to_group("render_dynamic")

static var _scenes := {}

# Meshy model fitted to `height`, bottom on the ground; false when the GLB is not there
func _model(name: String, height: float) -> bool:
	if not _scenes.has(name):
		var path := "res://assets/models/%s.glb" % name
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[name]
	if not scene:
		return false
	var m: Node3D = scene.instantiate()
	_mesh.add_child(m)
	Weapons._fit_height(m, height)
	m.position.y += height / 2.0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return true

func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	m.material_override = mat
	m.position = at
	_mesh.add_child(m)

func _process(delta: float) -> void:
	_t += delta
	_mesh.position.y = 0.06 + sin(_t * 2.4) * 0.04
	_mesh.rotation.y += delta * 1.2
	_light.light_energy = 0.9 + 0.35 * sin(_t * 3.1)
	if _t > LIFETIME - 5.0:
		_mesh.visible = fmod(_t, 0.4) < 0.25
	if _t > LIFETIME:
		queue_free()

func _on_body(body: Node3D) -> void:
	if NetSession.enabled:
		if body is Player and NetSession.is_host(): NetSession.world.collect_drop(self, body.peer_id)
		return
	if _taken or not body is Player:
		return
	var scene := get_tree().current_scene
	if not ("weapons" in scene) or scene.weapons == null:
		return
	var weapons: Weapons = scene.weapons
	var hud: Hud = scene.hud
	_taken = true
	match kind:
		"ammo":
			var id: String = weapons.current
			var mag := int(weapons.DEFS[id]["mag"])
			weapons.add_ammo(id, mag)
			hud.message("Munition: +%d %s" % [mag, weapons.DEFS[id]["name"]], 1.4)
		"grenade":
			weapons.grenades += 1
			weapons.update_hud()
			hud.message("+1 Granate", 1.4)
		_:
			var p: Player = body
			var heal := minf(30.0, p.max_hp - p.hp)
			p.hp += heal
			hud.set_health(p.hp)
			hud.message("Verbandspäckli: +%d Leben" % int(heal), 1.4)
	Sfx.play(scene, "pickup", -8.0)
	if "achievements" in scene and scene.achievements:
		scene.achievements.event("drops")
	queue_free()
