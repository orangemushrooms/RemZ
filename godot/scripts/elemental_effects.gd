extends RefCounted

const SHADER = preload("res://shaders/elemental_particle.gdshader")

static func particles(mode: String, radius: float, height: float, burst := false) -> CPUParticles3D:
	var effect := CPUParticles3D.new()
	var frost := mode == "frost"
	effect.emitting = false
	effect.amount = 22 if burst else 32
	effect.lifetime = 0.45 if burst else 0.85
	effect.one_shot = burst
	effect.explosiveness = 1.0 if burst else 0.0
	effect.local_coords = false
	effect.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	effect.emission_box_extents = Vector3(radius, height * 0.35, radius)
	if not burst:
		# Emit around the skin rather than inside the opaque body mesh.
		effect.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		var points := PackedVector3Array()
		for level in 4:
			for i in 12:
				var angle := TAU * i / 12.0
				points.append(Vector3(cos(angle) * (radius + 0.2), height * (float(level) / 3.0 - 0.5) * 0.7, sin(angle) * (radius + 0.2)))
		effect.emission_points = points
	effect.direction = Vector3.UP
	effect.spread = 160 if burst else (65 if frost else 20)
	effect.initial_velocity_min = 0.8 if burst else 0.25
	effect.initial_velocity_max = 3.0 if burst else (0.8 if frost else 1.8)
	effect.gravity = Vector3(0, -0.5 if frost else 0.6, 0)
	effect.scale_amount_min = 0.12 if frost else 0.22
	effect.scale_amount_max = (0.32 if frost else 0.55) * maxf(1.0, height * 0.55)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.85))
	gradient.set_color(1, Color(1, 1, 1, 0))
	effect.color_ramp = gradient
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1 if frost else 1.8)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("frost", frost)
	mesh.material = material
	effect.mesh = mesh
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return effect

static func burst(parent: Node, position: Vector3, mode: String, direction := Vector3.UP) -> void:
	if mode not in ["fire", "frost"]: return
	# Bound transient emitters even under sustained automatic fire and shotgun pellets.
	if parent.get_tree().get_nodes_in_group("elemental_burst").size() >= 48: return
	var effect := particles(mode, 0.06, 0.1, true)
	effect.add_to_group("elemental_burst")
	parent.add_child(effect)
	effect.global_position = position
	effect.direction = direction
	effect.emitting = true
	parent.get_tree().create_timer(0.8, false).timeout.connect(effect.queue_free)

static func shot(parent: Node, origin: Vector3, end: Vector3, mode: String, impact: bool) -> void:
	if mode not in ["fire", "frost"]: return
	if parent.get_tree().get_nodes_in_group("elemental_tracer").size() >= 48: return
	var distance := origin.distance_to(end)
	if distance < 0.01: return
	var tracer := MeshInstance3D.new()
	tracer.add_to_group("elemental_tracer")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.025
	mesh.height = distance
	mesh.radial_segments = 6
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.3, 0.8, 1, 0.8) if mode == "frost" else Color(1, 0.3, 0.025, 0.8)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.0
	tracer.material_override = material
	parent.add_child(tracer)
	tracer.global_position = (origin + end) * 0.5
	var direction := (end - origin).normalized()
	tracer.quaternion = Quaternion(Vector3.UP, direction)
	var tween := tracer.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(tracer.queue_free)
	burst(parent, origin, mode, direction)
	if impact: burst(parent, end, mode)
