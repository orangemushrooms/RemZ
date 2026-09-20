extends Node3D

const COLORS := [Color("66864b"), Color("497e9c"), Color("a9783f"), Color("865c94")]
const UNIFORM := Color("56634d")
var actor: Player
var body: Node3D
var label: Label3D
var left_leg: Node3D
var right_leg: Node3D
var gun: Node3D
var flash: OmniLight3D
var weapon := ""
var cycle := 0.0
var flash_t := 0.0
var tint := Color.WHITE
var step_distance := 0.0

func setup(p: Player, display_name: String, index: int) -> void:
	actor = p
	tint = COLORS[posmod(index, COLORS.size())]
	body = Node3D.new()
	add_child(body)
	_rounded(body, Vector3(0.43, 0.62, 0.30), Vector3(0, 1.23, 0), UNIFORM)
	_piece(body, Vector3(0.34, 0.36, 0.08), Vector3(0, 1.24, -0.15), Color("303b2f"))
	for x in [-0.095, 0.095]:
		_piece(body, Vector3(0.15, 0.17, 0.045), Vector3(x, 1.19, -0.21), UNIFORM.darkened(0.25))
	_piece(body, Vector3(0.37, 0.06, 0.28), Vector3(0, 0.98, 0), Color("292e26"))
	_piece(body, Vector3(0.07, 0.065, 0.02), Vector3(0, 0.98, -0.15), Color("646950"))
	_piece(body, Vector3(0.32, 0.30, 0.18), Vector3(0, 1.27, 0.18), Color("3d4737"))
	_rounded(body, Vector3(0.14, 0.17, 0.14), Vector3(0, 1.49, 0), Color("b89a79"))
	_rounded(body, Vector3(0.25, 0.30, 0.25), Vector3(0, 1.66, 0), Color("b89a79"))
	_rounded(body, Vector3(0.29, 0.16, 0.29), Vector3(0, 1.79, -0.015), UNIFORM.darkened(0.25))
	_piece(body, Vector3(0.23, 0.035, 0.12), Vector3(0, 1.76, -0.16), UNIFORM.darkened(0.25))
	_piece(body, Vector3(0.11, 0.035, 0.015), Vector3(0, 1.79, -0.153), tint)
	_piece(body, Vector3(0.22, 0.07, 0.02), Vector3(0, 1.69, -0.126), Color("202725"))
	_rounded(body, Vector3(0.19, 0.11, 0.13), Vector3(0, 1.59, -0.084), Color("3f473b"))
	left_leg = _leg(-0.11)
	right_leg = _leg(0.11)
	# The bent arms meet the pistol grip and fore-end.
	_limb(Vector3(0.23, 1.44, 0), Vector3(0.29, 1.14, -0.09), UNIFORM)
	_limb(Vector3(0.29, 1.14, -0.09), Vector3(0.14, 1.27, -0.30), UNIFORM)
	_limb(Vector3(-0.23, 1.44, 0), Vector3(-0.20, 1.13, -0.22), UNIFORM)
	_limb(Vector3(-0.20, 1.13, -0.22), Vector3(0.03, 1.28, -0.53), UNIFORM)
	_piece(body, Vector3(0.015, 0.085, 0.11), Vector3(0.335, 1.35, -0.04), tint)
	for pnt in [Vector3(0.14, 1.27, -0.30), Vector3(0.03, 1.28, -0.53)]:
		_piece(body, Vector3(0.10, 0.10, 0.14), pnt, Color("242925"))
	label = Label3D.new()
	label.text = display_name
	label.font_size = 32
	label.pixel_size = 0.004
	label.position.y = 2.12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = tint.lightened(0.4)
	label.visibility_range_end = 45.0
	add_child(label)
	flash = OmniLight3D.new()
	flash.position = Vector3(0.1, 1.35, -0.85)
	flash.light_color = Color(1, 0.65, 0.25)
	flash.omni_range = 3.0
	flash.shadow_enabled = false
	flash.visible = false
	body.add_child(flash)
	set_weapon("pistol")
	add_to_group("render_dynamic")

func _piece(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _rounded(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := _piece(parent, Vector3.ONE, at, color)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh.mesh = sphere
	mesh.scale = size
	return mesh

func _limb(a: Vector3, b: Vector3, color: Color) -> void:
	var mesh := _rounded(body, Vector3(0.16, a.distance_to(b) + 0.10, 0.16), (a+b)*0.5, color)
	mesh.quaternion = Quaternion(Vector3.UP, (b-a).normalized())

func _leg(side: float) -> Node3D:
	var leg := Node3D.new()
	leg.position = Vector3(side, 0.97, 0)
	body.add_child(leg)
	_rounded(leg, Vector3(0.19, 0.49, 0.24), Vector3(0, -0.24, 0), UNIFORM.darkened(0.2))
	_rounded(leg, Vector3(0.17, 0.39, 0.20), Vector3(0, -0.59, 0), UNIFORM.darkened(0.2))
	_piece(leg, Vector3(0.14, 0.14, 0.055), Vector3(0, -0.43, -0.11), Color("3b4334"))
	_rounded(leg, Vector3(0.17, 0.20, 0.29), Vector3(0, -0.83, -0.045), Color("282c25"))
	_piece(leg, Vector3(0.16, 0.035, 0.25), Vector3(0, -0.945, -0.045), Color("23271f"))
	return leg

func set_weapon(id: String) -> void:
	if id == weapon or not Weapons.DEFS.has(id): return
	weapon = id
	_skin = "__unset"
	if gun: gun.queue_free()
	gun = Node3D.new()
	body.add_child(gun)
	var packed: PackedScene = load("res://assets/models/%s.glb" % Weapons.DEFS[id].model)
	var model: Node3D = packed.instantiate()
	gun.add_child(model)
	model.rotation.y = -PI / 2.0
	Weapons._fit_height(model, float(Weapons.DEFS[id].height) * 1.35)
	model.position -= ViewmodelHands.weapon_bounds(gun).get_center()
	gun.position = Vector3(0.10, 1.34, -0.43)

func shot(id: String) -> void:
	set_weapon(id)
	flash_t = 0.065
	flash.visible = true
	flash.light_energy = 2.5
	Sfx.play_at(self, Weapons.DEFS[id].sfx, global_position + Vector3.UP * 1.3, float(Weapons.DEFS[id].get("sfx_db", -8.0)), float(Weapons.DEFS[id].get("sfx_pitch", 1.0)))

func _process(delta: float) -> void:
	if not is_instance_valid(actor): return
	var speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	if actor.alive and speed > 0.5:
		step_distance += speed * delta
		if step_distance > 2.1:
			step_distance = 0.0
			Sfx.play_at(self, "step_leaves", actor.global_position + Vector3.UP * 0.1, -17.0)
	cycle += delta * minf(speed * 2.4, 17.0)
	var stride := minf(speed / 5.0, 1.0) * 0.55 if actor.alive else 0.0
	left_leg.rotation.x = sin(cycle) * stride
	right_leg.rotation.x = -sin(cycle) * stride
	body.rotation.z = lerp_angle(body.rotation.z, 0.0 if actor.alive else PI * 0.5, minf(1.0, delta * 8))
	body.position.y = 0.0 if actor.alive else 0.1
	flash_t = maxf(0.0, flash_t-delta)
	flash.visible = flash_t > 0.0
	gun.rotation.x = actor.pitch * 0.65
	label.text = "%s\n%d / %d" % [NetSession.roster.get(actor.peer_id, "Spieler"), maxi(0, ceili(actor.hp)), int(actor.max_hp)] if actor.alive else "%s\nWiederbeleben [E]" % NetSession.roster.get(actor.peer_id, "Spieler")

var _skin := "__unset"

func set_skin(finish: String) -> void:
	if not gun or _skin == finish: return
	_skin = finish
	WeaponSkins.apply(gun, finish)
