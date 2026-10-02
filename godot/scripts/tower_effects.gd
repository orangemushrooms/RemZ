# Cosmetic emitters only. World-space particles keep travelling when the turret turns.
extends Node3D

const PARTICLE = preload("res://shaders/tower_particle.gdshader")
var kind := "standard"
var jet: CPUParticles3D
var puff: CPUParticles3D
var flare: CPUParticles3D
var cases: CPUParticles3D
var remaining := 0.0
var stream: MeshInstance3D
var _stream_material: ShaderMaterial
var _flow_age := 0.0
var _flow_distance := 14.0
var _flow_strength := 0.0

static func cloud(mode: int, amount: int, lifetime: float, size: Vector2, burst: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.one_shot = burst
	p.explosiveness = 1.0 if burst else 0.0
	p.randomness = 0.28
	p.direction = Vector3(0, 0, -1)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.045
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE
	mat.set_shader_parameter("mode", mode)
	quad.material = mat
	p.mesh = quad
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.15, 0.65, 1])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 0.8, 0.65, 0.65), Color(0.4, 0.25, 0.2, 0)])
	p.color_ramp = gradient
	var growth := Curve.new()
	growth.add_point(Vector2(0, 0.3))
	growth.add_point(Vector2(0.3, 0.7))
	growth.add_point(Vector2(1, 1))
	p.scale_amount_curve = growth
	return p

var ring: MeshInstance3D
var _ring_age := 10.0
var _ring_radius := 12.0

func _ready() -> void:
	if kind in ["flame", "frost"]:
		# Crossed, subdivided ribbons form a continuous turbulent jet. Sparse wisps break up its tip.
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for plane in 3:
			var side := Vector3(cos(plane * PI / 3), sin(plane * PI / 3), 0) * 0.5
			for i in 40:
				var a := float(i) / 40
				var b := float(i + 1) / 40
				for uv in [Vector2(0,a),Vector2(1,a),Vector2(1,b),Vector2(0,a),Vector2(1,b),Vector2(0,b)]:
					mesh.surface_set_uv(uv)
					mesh.surface_add_vertex(side * (uv.x * 2 - 1) + Vector3(0, 0, -uv.y))
		mesh.surface_end()
		_stream_material = ShaderMaterial.new()
		_stream_material.shader = preload("res://shaders/tower_frost_jet.gdshader") if kind == "frost" else preload("res://shaders/tower_flame_jet.gdshader")
		stream = MeshInstance3D.new()
		stream.mesh = mesh
		stream.material_override = _stream_material
		stream.custom_aabb = AABB(Vector3(-4,-4,-40), Vector3(8,8,41))
		stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stream.hide()
		add_child(stream)
		jet = cloud(3 if kind == "frost" else 0, 40, 0.5, Vector2(0.5, 0.9), false)
		jet.spread = 11
		jet.initial_velocity_min = 26
		jet.initial_velocity_max = 28
		jet.gravity = Vector3(0, 0.9, 0) if kind == "flame" else Vector3(0, -1.2, 0)
		jet.scale_amount_min = 0.18
		jet.scale_amount_max = 0.35
		jet.color = Color(1, 0.7, 0.5, 0.3) if kind == "flame" else Color(0.75, 0.9, 1.0, 0.35)
		add_child(jet)
	if kind == "supply":
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 8
		ring = MeshInstance3D.new()
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.45, 1.0, 0.55, 0.6)
		ring.material_override = mat
		ring.top_level = true
		ring.visible = false
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	flare = cloud(2, 5 if kind not in ["mortar", "rocket"] else 12, 0.055 if kind not in ["mortar", "rocket"] else 0.14, Vector2(0.5, 0.5), true)
	flare.spread = 12
	flare.initial_velocity_min = 2
	flare.initial_velocity_max = 7
	flare.gravity = Vector3.ZERO
	add_child(flare)
	puff = cloud(1, 7 if kind not in ["mortar", "rocket"] else 20, 0.65 if kind != "rocket" else 1.4, Vector2(0.6, 0.6) if kind != "rocket" else Vector2(1.1, 1.1), true)
	puff.spread = 24
	puff.initial_velocity_min = 0.6
	puff.initial_velocity_max = 2.0
	puff.gravity = Vector3(0, 0.6, 0)
	puff.color = Color(0.27, 0.28, 0.27, 0.24)
	if kind in ["standard", "mg42"]:
		puff.one_shot = false
		puff.explosiveness = 0
		puff.amount = 12
	add_child(puff)
	if kind in ["standard", "mg42", "sniper"]:
		cases = CPUParticles3D.new()
		cases.emitting = false
		cases.one_shot = false
		cases.explosiveness = 0
		cases.amount = 8 if kind == "mg42" else 3
		cases.lifetime = 0.6
		cases.local_coords = false
		cases.position = Vector3(0.24, -0.06, 1.05)
		cases.direction = Vector3(1, 0.3, 0.2)
		cases.spread = 12
		cases.initial_velocity_min = 1.5
		cases.initial_velocity_max = 2.7
		cases.angular_velocity_min = 120
		cases.angular_velocity_max = 360
		cases.gravity = Vector3(0, -9.8, 0)
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.009
		mesh.bottom_radius = 0.009
		mesh.height = 0.055
		mesh.radial_segments = 6
		mesh.material = DefenceTower.material(Color(0.58, 0.38, 0.13), 0.7)
		cases.mesh = mesh
		add_child(cases)

func fire(distance: float) -> void:
	if remaining <= 0: _flow_age = 0
	remaining = 0.26 if kind == "standard" else 0.20
	if jet:
		_flow_distance = distance
		# Clip the jet's travel to the actual hit/range, including upgrades.
		jet.lifetime = clampf(distance / 28.0, 0.04, 1.8)
		remaining = 0.20
		jet.emitting = true
	elif kind not in ["tesla", "graviton", "searchlight", "siren", "supply"]:
		flare.restart()
		flare.emitting = true
		if puff.one_shot: puff.restart()
		puff.emitting = true
	if cases:
		cases.emitting = true

# The supply post's tick: a ring that runs out to the post's reach and fades.
func pulse(reach: float) -> void:
	if not ring: return
	_ring_age = 0.0
	_ring_radius = reach
	ring.global_position = global_position
	ring.visible = true

func _process(delta: float) -> void:
	remaining = maxf(0, remaining - delta)
	if ring and ring.visible:
		_ring_age += delta
		var t := _ring_age / 0.9
		if t >= 1.0: ring.visible = false
		else:
			ring.scale = Vector3.ONE * maxf(0.05, _ring_radius * t)
			(ring.material_override as StandardMaterial3D).albedo_color.a = 0.6 * (1.0 - t)
	if stream:
		_flow_age += delta
		_flow_strength = move_toward(_flow_strength, 1.0 if remaining > 0 else 0.0, delta * 9)
		stream.visible = _flow_strength > 0.01
		_stream_material.set_shader_parameter("strength", _flow_strength)
		_stream_material.set_shader_parameter("jet_length", minf(_flow_distance, _flow_age * 28))
	if jet: jet.emitting = remaining > 0
	if cases: cases.emitting = remaining > 0
	if puff and not puff.one_shot: puff.emitting = remaining > 0

static func explosion(parent: Node3D, at: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = at
	for smoke in [false, true]:
		var p := cloud(1 if smoke else 0, 36 if smoke else 18, 1.5 if smoke else 0.28, Vector2(2.6, 2.6), true)
		p.direction = Vector3.UP
		p.spread = 75
		p.initial_velocity_min = 2 if smoke else 5
		p.initial_velocity_max = 6 if smoke else 12
		p.gravity = Vector3(0, 1 if smoke else -3, 0)
		if smoke: p.color = Color(0.22, 0.20, 0.17, 0.65)
		root.add_child(p)
		p.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.51, 0.18)
	light.light_energy = 5
	light.omni_range = 9
	root.add_child(light)
	root.create_tween().tween_property(light, "light_energy", 0.0, 0.22)
	root.get_tree().create_timer(2.0, false).timeout.connect(root.queue_free)
