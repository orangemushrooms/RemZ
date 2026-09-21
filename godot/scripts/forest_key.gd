class_name ForestKey
extends Node3D

var taken := false
var key_id := ""
var manager: ForestKeys
var pickup_visual: Node3D

func _ready() -> void:
	# A physical key on a low cut stump: readable without a permanent beacon.
	var bark := Foliage.pbr("ph_bark_beech2", 1.0, Color(0.55, 0.45, 0.32))
	bark.roughness = 1.0
	var cut := StandardMaterial3D.new()
	cut.albedo_color = Color(0.44, 0.34, 0.21)
	cut.roughness = 0.95
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.76, 0.55, 0.20)
	brass.metallic = 0.8
	brass.roughness = 0.3
	var tag := StandardMaterial3D.new()
	tag.albedo_color = Color(0.55, 0.11, 0.07) if key_id == "waldhuette" else Color(0.08, 0.30, 0.37)
	var stump := CylinderMesh.new()
	stump.top_radius = 0.27
	stump.bottom_radius = 0.34
	stump.height = 0.78
	stump.radial_segments = 12
	var imported_stump := WorldModels.attach(self, "stump", Vector3.ZERO, 0.53)
	if not imported_stump: _mesh(stump, bark, Vector3(0, 0.13, 0))
	var top := CylinderMesh.new()
	top.top_radius = 0.255
	top.bottom_radius = 0.255
	top.height = 0.012
	top.radial_segments = 16
	if not imported_stump: _mesh(top, cut, Vector3(0, 0.526, 0))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.28
	cylinder.height = 0.52
	collider.shape = cylinder
	collider.position.y = 0.26
	body.add_child(collider)
	add_child(body)
	pickup_visual = Node3D.new()
	add_child(pickup_visual)
	if WorldModels.attach(pickup_visual, "forest_key", Vector3(0, 0.54, 0), 0.25, 0): return
	var ring := TorusMesh.new()
	ring.inner_radius = 0.040
	ring.outer_radius = 0.058
	ring.rings = 16
	ring.ring_segments = 8
	_mesh(ring, brass, Vector3(-0.08, 0.548, 0))
	_box(Vector3(0.16, 0.017, 0.021), Vector3(0.046, 0.548, 0), brass)
	for x: float in [0.085, 0.12]:
		_box(Vector3(0.018, 0.017, 0.047), Vector3(x, 0.548, 0.015), brass)
	_box(Vector3(0.12, 0.012, 0.07), Vector3(-0.09, 0.542, -0.085), tag)

func _mesh(mesh: Mesh, mat: Material, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	instance.add_to_group("render_dynamic")
	if pickup_visual:
		pickup_visual.add_child(instance)
	else:
		add_child(instance)

func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(box, mat, at)

func interaction_point() -> Vector3:
	return global_position + Vector3(0, 0.55, 0)

func can_interact(player: Node3D) -> bool:
	if taken or player.camera.global_position.distance_to(interaction_point()) > 2.4:
		return false
	var ray := PhysicsRayQueryParameters3D.create(player.camera.global_position, interaction_point(), 1 | 8, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func prompt_text() -> String:
	return "[E] Schlüssel nehmen · %s" % ForestKeys.KEYS[key_id]

func take(weapons, _hud) -> void:
	if NetSession.enabled:
		NetSession.command("interact", [str(get_meta("coop_id", ""))])
		return
	if not weapons.player.active or not weapons.player.alive or not can_interact(weapons.player):
		return
	manager.collect(self)
