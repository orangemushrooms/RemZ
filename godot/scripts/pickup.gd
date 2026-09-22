# Small drop left behind by a killed zombie: an ammunition pack or a grenade. Bobs and glows, is collected by
# walking through it, and fades away after a while so the field never fills up.
class_name Pickup
extends Area3D

const LIFETIME := 45.0
const CASH_BUNDLE := 100
const MAX_CASH_DROPS := 128

var kind := "ammo"      # "ammo" | "grenade" | "medkit"
var _t := 0.0
var _mesh: Node3D
var _light: OmniLight3D
var _taken := false
var _retry_t := 0.0
var amount := 0
var owner_peer := 0
var toss_velocity := Vector3.ZERO

static func throw_cash(player: Player) -> String:
	if NetSession.is_client(): return ""
	var game := player.get_tree().current_scene
	if not game.started or game.over or not player.alive or not player.active or player.get_tree().paused: return ""
	if player.cash_cooldown > 0.0: return ""
	if player.score <= 0: return "Keine Rem Dollars zum Abwerfen."
	if player.get_tree().get_nodes_in_group("cash_drops").size() >= MAX_CASH_DROPS: return "Sammelt zuerst die Geldbündel am Boden auf."
	var drop := Pickup.new()
	drop.amount = mini(CASH_BUNDLE, player.score)
	drop.owner_peer = player.peer_id
	drop.setup("cash")
	game.add_child(drop)
	drop.global_position = player.global_position + Vector3.UP * 0.9
	drop.toss_velocity = -player.global_basis.z * 5.0 + Vector3.UP * 3.0
	player.add_score(-drop.amount)
	player.cash_cooldown = 0.35
	return "%d R abgeworfen" % drop.amount

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
		"cash":
			add_to_group("cash_drops")
			if not WorldModels.attach(_mesh, "cash_bundle", Vector3.ZERO, 0.30, 0):
				_box(Vector3(0.30, 0.09, 0.16), Vector3(0, 0.05, 0), Color(0.35, 0.55, 0.24))
				_box(Vector3(0.06, 0.10, 0.17), Vector3(0, 0.05, 0), Color(0.85, 0.79, 0.55))
			var label := Label3D.new()
			label.text = "%d R" % amount
			label.position.y = 0.48
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 40
			label.pixel_size = 0.004
			_mesh.add_child(label)
			color = Color(0.6, 1.0, 0.3)
		"ammo":
			if not _model("ammo_pack", 0.24):
				_box(Vector3(0.36, 0.2, 0.24), Vector3(0, 0.1, 0), Color(0.3, 0.34, 0.22))
				_box(Vector3(0.38, 0.03, 0.26), Vector3(0, 0.21, 0), Color(0.22, 0.25, 0.16))
				_box(Vector3(0.1, 0.02, 0.27), Vector3(0, 0.225, 0), Color(0.85, 0.7, 0.3))
			color = Color(1.0, 0.8, 0.35)
		"grenade":
			_model("grenade", 0.25)
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
	if kind != "cash" and _t > LIFETIME - 5.0:
		_mesh.visible = fmod(_t, 0.4) < 0.25
	if kind != "cash" and _t > LIFETIME:
		queue_free()

func _physics_process(delta: float) -> void:
	if _taken or NetSession.is_client(): return
	if kind == "cash" and not toss_velocity.is_zero_approx():
		toss_velocity.y -= 9.8 * delta
		var target := global_position + toss_velocity * delta
		var query := PhysicsRayQueryParameters3D.create(global_position, target, 1 | 8)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): global_position = target
		else:
			global_position = hit.position + hit.normal * 0.06
			toss_velocity = Vector3.ZERO if hit.normal.y > 0.5 else Vector3.DOWN * 0.1
	_retry_t -= delta
	if _retry_t > 0.0: return
	_retry_t = 0.25
	for body in get_overlapping_bodies():
		_on_body(body)
		if _taken: break

func can_collect(player: Player, weapons: Weapons) -> bool:
	if _taken or not player.alive: return false
	match kind:
		"cash":
			if amount <= 0 or _t < (2.0 if player.peer_id == owner_peer else 0.35): return false
			var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.8, global_position + Vector3.UP * 0.1, 1 | 8, [player.get_rid()])
			return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		"ammo": return weapons.has_ammo_space(weapons.ammo_weapon())
		"grenade": return weapons.grenades < weapons.grenades_max
		_: return player.hp < player.max_hp

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
	if not can_collect(body, weapons): return
	var hud: Hud = scene.hud
	_taken = true
	match kind:
		"cash":
			body.add_score(amount)
			hud.message("+%d R aufgenommen" % amount, 1.4)
		"ammo":
			var id: String = weapons.ammo_weapon()
			var mag := int(weapons.DEFS[id]["mag"])
			weapons.add_ammo(id, mag)
			hud.message("Munition: +%d %s" % [mag, weapons.DEFS[id]["name"]], 1.4)
		"grenade":
			weapons.grenades = mini(weapons.grenades_max, weapons.grenades + 1)
			weapons.update_hud()
			hud.message("+1 Granate", 1.4)
		_:
			var p: Player = body
			var heal := minf(30.0, p.max_hp - p.hp)
			p.hp += heal
			hud.set_health(p.hp)
			hud.message("Verbandspäckli: +%d Leben" % int(heal), 1.4)
	Sfx.play(scene, "pickup", -8.0)
	if kind != "cash" and "achievements" in scene and scene.achievements:
		scene.achievements.event("drops")
	queue_free()
