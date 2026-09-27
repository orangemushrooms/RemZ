extends RefCounted

static func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func motes(color: Color, count: int, radius: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 40
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 0.015
	p.scale_amount_max = 0.04
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = material(color)
	mesh.material.vertex_color_use_as_albedo = true
	mesh.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(color, 0), color, Color(color, 0)])
	gradient.offsets = PackedFloat32Array([0, 0.15, 1])
	p.color_ramp = gradient
	return p

static func burst(parent: Node3D, at: Vector3, color: Color, radius: float) -> void:
	# One low-poly ring and one emitter per pulse, always reclaimed after 1.6 s.
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = at + Vector3.UP * 0.15
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 6
	torus.material = material(color)
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.2, 0.6, 0.2)
	root.add_child(ring)
	var sparks := motes(color, 36, 0.6)
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	root.add_child(sparks)
	var tween := root.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 0.04, radius), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, 0.75)
	tween.chain().tween_interval(0.85)
	tween.chain().tween_callback(root.queue_free)

static func kettle(parent: Node3D, at: Vector3, on_grill := false) -> Dictionary:
	var root := Node3D.new()
	root.name = "BrewingKettle"
	root.add_to_group("render_dynamic")
	parent.add_child(root)
	root.global_position = at
	if on_grill: root.scale = Vector3.ONE * 0.55
	var rim_height := 0.46 if on_grill else 0.56
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("272d32")
	iron.metallic = 0.8
	iron.roughness = 0.4
	var bowl := SphereMesh.new()
	bowl.radius = 0.37
	bowl.height = 0.42 if on_grill else 0.6
	bowl.is_hemisphere = true
	bowl.radial_segments = 24
	bowl.rings = 12
	var body := DefenceTower.piece(root, bowl, Vector3(0, rim_height, 0), iron)
	body.rotation.z = PI
	var rim := TorusMesh.new()
	rim.inner_radius = 0.34
	rim.outer_radius = 0.39
	rim.rings = 24
	rim.ring_segments = 8
	DefenceTower.piece(root, rim, Vector3(0, rim_height, 0), iron)
	var water := CylinderMesh.new()
	water.top_radius = 0.335
	water.bottom_radius = 0.335
	water.height = 0.012
	water.radial_segments = 24
	# The hemisphere has a flat cap: place the liquid above it, inside the raised rim.
	var liquid := DefenceTower.piece(root, water, Vector3(0, rim_height + 0.007, 0), material(Color("d99442")))
	for i in 3:
		var angle := i * TAU / 3
		var leg := CylinderMesh.new()
		leg.top_radius = 0.023
		leg.bottom_radius = 0.023
		leg.height = 0.06 if on_grill else 0.45
		var foot_radius := 0.11 if on_grill else 0.27
		DefenceTower.piece(root, leg, Vector3(cos(angle) * foot_radius, leg.height * 0.5, sin(angle) * foot_radius), iron)
	var steam := motes(Color.WHITE, 18, 0.22)
	steam.mesh.material.emission_enabled = false
	steam.position.y = rim_height + 0.01
	root.add_child(steam)
	steam.emitting = false
	return {"root": root, "liquid": liquid, "steam": steam}
