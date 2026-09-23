extends RefCounted

const SHADER = preload("res://shaders/elemental_particle.gdshader")
static var _tracer_mesh: CylinderMesh
static var _tracer_materials: Dictionary = {}

# One material per element for every tracer. A fresh StandardMaterial3D per shot made Godot free
# and recompile its generated shader whenever the previous tracer had faded (a hitch per shot after
# any pause); the fade now runs on GeometryInstance3D.transparency instead of the material.
static func tracer_material(mode: String) -> StandardMaterial3D:
	if not _tracer_materials.has(mode):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.3, 0.8, 1, 0.8) if mode == "frost" else Color(1, 0.3, 0.025, 0.8)
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 2.0
		_tracer_materials[mode] = material
	return _tracer_materials[mode]

static func tracer_mesh() -> CylinderMesh:
	if not _tracer_mesh:
		_tracer_mesh = CylinderMesh.new()
		_tracer_mesh.top_radius = 0.012
		_tracer_mesh.bottom_radius = 0.025
		_tracer_mesh.height = 1.0
		_tracer_mesh.radial_segments = 6
	return _tracer_mesh

class Tracer extends MeshInstance3D:
	var start: Vector3
	var endpoint: Vector3
	var follow_muzzle: Callable

	func align() -> void:
		if follow_muzzle.is_valid(): start = follow_muzzle.call()
		var offset := endpoint - start
		if offset.length_squared() < 0.0001:
			hide()
			return
		global_position = (start + endpoint) * 0.5
		quaternion = Quaternion(Vector3.UP, offset.normalized())
		# Transform a shared unit mesh; changing CylinderMesh.height rebuilds
		# geometry on the rendering thread on every frame of a moving tracer.
		scale = Vector3(1, offset.length(), 1)

	func _process(_delta: float) -> void:
		align()

static func particles(mode: String, radius: float, height: float, burst := false, size := 1.0) -> CPUParticles3D:
	var effect := CPUParticles3D.new()
	var frost := mode == "frost"
	# A scaled-down burst is the puff at the barrel, half a metre from the eye: few sparks in a
	# tight cone along the bore, gone quickly and without the campfire updraft of an impact.
	var muzzle := burst and size < 1.0
	effect.emitting = false
	effect.amount = (8 if muzzle else 22) if burst else 32
	effect.lifetime = (0.22 if muzzle else 0.45) if burst else 0.85
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
	effect.spread = (26 if muzzle else 160) if burst else (65 if frost else 20)
	effect.initial_velocity_min = (0.8 if burst else 0.25) * size
	effect.initial_velocity_max = (3.0 if burst else (0.8 if frost else 1.8)) * size
	effect.gravity = Vector3.ZERO if muzzle else Vector3(0, -0.5 if frost else 0.6, 0)
	effect.scale_amount_min = (0.12 if frost else 0.22) * size
	effect.scale_amount_max = (0.32 if frost else 0.55) * maxf(1.0, height * 0.55) * size
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

static func burst(parent: Node, position: Vector3, mode: String, direction := Vector3.UP, size := 1.0) -> void:
	if mode not in ["fire", "frost"]: return
	# Bound transient emitters even under sustained automatic fire and shotgun pellets.
	if parent.get_tree().get_nodes_in_group("elemental_burst").size() >= 48: return
	var effect := particles(mode, 0.06, 0.1, true, size)
	effect.add_to_group("elemental_burst")
	parent.add_child(effect)
	effect.global_position = position
	effect.direction = direction
	effect.emitting = true
	parent.get_tree().create_timer(0.8, false).timeout.connect(effect.queue_free)

static func shot(parent: Node, origin: Vector3, end: Vector3, mode: String, impact: bool, follow_muzzle := Callable()) -> void:
	if mode not in ["fire", "frost"]: return
	if parent.get_tree().get_nodes_in_group("elemental_tracer").size() >= 48: return
	var distance := origin.distance_to(end)
	if distance < 0.01: return
	var tracer := Tracer.new()
	tracer.start = origin
	tracer.endpoint = end
	tracer.follow_muzzle = follow_muzzle
	tracer.process_priority = 10 # Align after the player's and weapon's current-frame animation.
	tracer.add_to_group("elemental_tracer")
	tracer.mesh = tracer_mesh()
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.material_override = tracer_material(mode)
	parent.add_child(tracer)
	var direction := (end - origin).normalized()
	tracer.align()
	tracer.set_process(follow_muzzle.is_valid())
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "transparency", 1.0, 0.12)
	tween.tween_callback(tracer.queue_free)
	# The muzzle sits half a metre from the eye, so impact-sized sparks would wipe out the whole
	# screen on every shot. The barrel gets a small puff, the target the full burst.
	burst(parent, origin, mode, direction, 0.22)
	if impact: burst(parent, end, mode)
