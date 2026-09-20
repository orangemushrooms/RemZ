extends Node3D

const STAR_SHADER = preload("res://scripts/firework_stars.gdshader")
const ROCKET_MODEL = preload("res://assets/models/firework_rocket.glb")
const CRACKER_MODEL = preload("res://assets/models/firework_cracker.glb")
const AUDIO := "res://assets/audio/fireworks/"
var kind := "fw_ruby"
var origin := Vector3.ZERO
var landing := Vector3.ZERO
var flight_path := PackedVector3Array()
var random_seed := 1
var age := 0.0
var burst_at := 3.6
var rocket := true
var body: Node3D
var sparks: GPUParticles3D
var trail: GPUParticles3D
var fuse_sound: AudioStreamPlayer3D
var light: OmniLight3D
var star_material: ShaderMaterial
var launched := false
var burst := false

static func model(is_rocket: bool) -> Node3D:
	return (ROCKET_MODEL if is_rocket else CRACKER_MODEL).instantiate()

func configure(id: String, start: Vector3, end: Vector3, seed_value: int, elapsed: float, path := PackedVector3Array()) -> void:
	kind = id
	origin = start
	landing = end
	random_seed = seed_value
	age = elapsed
	flight_path = path
	rocket = id != "fw_cracker"
	burst_at = 3.6 if rocket else 2.4

func state() -> Array:
	return [kind, origin, landing, random_seed, age, flight_path]

func _ready() -> void:
	global_position = origin
	body = model(rocket)
	add_child(body)
	sparks = particles(Color(1, 0.6, 0.12), 24, 0.28, 0.04, 1.6, Vector3(0, -2, 0), false)
	add_child(sparks)
	sparks.position.y = 0.3 if rocket else 0.15
	sparks.emitting = age < (1.2 if rocket else burst_at)
	trail = particles(Color(1, 0.55, 0.12), 100, 0.65, 0.12, 1.4, Vector3(0, -3, 0), false)
	add_child(trail)
	trail.position.y = 0.27 if rocket else 0.0
	trail.emitting = false
	if age < (1.2 if rocket else burst_at):
		fuse_sound = sound("fuse", -15, 22)
		if fuse_sound.stream is AudioStreamWAV: (fuse_sound.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_tick()

func _process(delta: float) -> void:
	age += delta
	_tick()
	if age > burst_at + 7.5: queue_free()

func _tick() -> void:
	if rocket:
		var ascent := clampf((age - 1.2) / 2.4, 0, 1)
		global_position = origin + Vector3.UP * 34.0 * pow(ascent, 1.45)
		if age >= 1.2 and not launched:
			launched = true
			sparks.emitting = false
			if is_instance_valid(fuse_sound): fuse_sound.stop()
			trail.emitting = age < burst_at
			if age < 1.55: sound("launch", -6, 100)
	else:
		if flight_path.size() > 1:
			var index := minf(age / 0.05, flight_path.size() - 1)
			var base := floori(index)
			global_position = flight_path[base].lerp(flight_path[mini(base + 1, flight_path.size() - 1)], index - base)
		else: global_position = landing
		body.rotation = Vector3(age * 5, 0.3, age * 7) if age < (flight_path.size() - 1) * 0.05 else Vector3(0, 0.3, PI * 0.5)
		sparks.position = body.transform * Vector3(0, 0.15, 0)
	if age >= burst_at and not burst: _burst(age - burst_at < 0.4)
	if burst:
		if star_material: star_material.set_shader_parameter("age", age - burst_at)
		if is_instance_valid(light): light.light_energy = 9.0 * exp(-(age - burst_at) * 7)

func _burst(with_sound: bool) -> void:
	burst = true
	body.hide()
	sparks.emitting = false
	trail.emitting = false
	if is_instance_valid(fuse_sound): fuse_sound.stop()
	_stars()
	if age - burst_at < 0.5:
		var smoke := particles(Color(0.3, 0.32, 0.36, 0.22), 22 if rocket else 35, 4.5, 2.0 if rocket else 0.55, 2.8 if rocket else 1.1, Vector3(0.5, 0.35, 0.2), true)
		add_child(smoke)
		smoke.emitting = true
	light = OmniLight3D.new()
	light.light_color = Color(1, 0.64, 0.24) if kind in ["fw_gold", "fw_cracker"] else (Color(1, 0.15, 0.2) if kind == "fw_ruby" else Color(0.28, 1, 0.65))
	light.omni_range = 25 if rocket else 9
	light.shadow_enabled = false
	add_child(light)
	var scene := get_tree().current_scene
	if scene and "cornfield" in scene and scene.cornfield: scene.cornfield.scare(global_position)
	if with_sound:
		var camera := get_viewport().get_camera_3d()
		var distance := global_position.distance_to(camera.global_position) if camera else 0.0
		var delay := clampf(distance / 343.0, 0, 1.5)
		get_tree().create_timer(delay, false).timeout.connect(func():
			if is_instance_valid(self): sound("burst" if rocket else "cracker", 0 if rocket else -3, 220 if rocket else 100))
		if kind == "fw_gold":
			get_tree().create_timer(delay + 0.65, false).timeout.connect(func():
				if is_instance_valid(self): sound("crackle", -9, 160))

func _stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var count := 320 if kind == "fw_gold" else (230 if rocket else 65)
	var tails := 7 if kind == "fw_gold" else (5 if rocket else 2)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	star_material = ShaderMaterial.new()
	star_material.shader = STAR_SHADER
	star_material.set_shader_parameter("fall", 1.45 if kind == "fw_gold" else (2.0 if rocket else 3.6))
	star_material.set_shader_parameter("star_size", 0.22 if rocket else 0.045)
	star_material.set_shader_parameter("tail_length", 1.0 if kind == "fw_gold" else 0.42)
	star_material.set_shader_parameter("tail_step", (1.0 if kind == "fw_gold" else 0.42) / maxf(1, tails - 1))
	mesh.material = star_material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count * tails
	mm.custom_aabb = AABB(Vector3(-65, -100, -65), Vector3(130, 165, 130))
	for i in count:
		# Fibonacci sphere avoids clumps and gives a full, even chrysanthemum.
		var y := 1.0 - 2.0 * (float(i) + 0.5) / count
		var angle := i * 2.399963 + rng.randf_range(-0.03, 0.03)
		var radius := sqrt(1.0 - y * y)
		var direction := Vector3(cos(angle) * radius, y, sin(angle) * radius)
		if not rocket: direction.y = absf(direction.y)
		var velocity := direction * rng.randf_range(11, 14) * (1.0 if rocket else 0.27)
		var color := Color(1, 0.075, 0.12)
		if kind == "fw_gold" or not rocket: color = Color(1, rng.randf_range(0.5, 0.8), 0.12)
		elif kind == "fw_aurora":
			color = Color(0.15, 1, 0.48) if i % 3 else Color(0.65, 0.22, 1)
			if i % 5 == 0:
				velocity = Vector3(cos(angle), sin(angle), 0.12 * sin(angle * 2)) * 17
				color = Color(0.6, 0.35, 1)
		elif i % 4 == 0:
			color = Color(0.78, 0.86, 1)
			velocity *= 0.58
		var lifetime := rng.randf_range(3.8, 5.1) if kind == "fw_gold" else rng.randf_range(2.0, 3.3)
		if not rocket: lifetime = rng.randf_range(0.3, 0.75)
		for tail in tails:
			var n := i * tails + tail
			mm.set_instance_transform(n, Transform3D.IDENTITY)
			mm.set_instance_custom_data(n, Color(velocity.x, velocity.y, velocity.z, lifetime))
			mm.set_instance_color(n, Color(color.r, color.g, color.b, float(tail) / maxf(1, tails - 1)))
	var draw := MultiMeshInstance3D.new()
	draw.multimesh = mm
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(draw)

static func particles(color: Color, amount: int, life: float, size: float, speed: float, gravity: Vector3, smoke: bool) -> GPUParticles3D:
	var result := GPUParticles3D.new()
	result.emitting = false
	result.local_coords = false
	result.amount = amount
	result.lifetime = life
	result.one_shot = smoke
	result.explosiveness = 0.85 if smoke else 0.0
	result.visibility_aabb = AABB(Vector3(-20, -40, -20), Vector3(40, 80, 40))
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.DOWN if not smoke else Vector3.UP
	material.spread = 70 if not smoke else 180
	material.initial_velocity_min = speed * 0.4
	material.initial_velocity_max = speed
	material.gravity = gravity
	material.scale_min = size * 0.4
	material.scale_max = size
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color.r, color.g, color.b, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	material.color_ramp = ramp
	result.process_material = material
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var visual := StandardMaterial3D.new()
	visual.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if smoke else BaseMaterial3D.BLEND_MODE_ADD
	visual.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	visual.vertex_color_use_as_albedo = true
	visual.albedo_texture = Foliage._soft_dot()
	quad.material = visual
	result.draw_pass_1 = quad
	return result

func sound(stem: String, volume: float, distance: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	# numbered variants (burst_1..4, cracker_1..4) are picked at random; single files keep their plain stem
	var variants: Array = []
	for ext: String in [".wav", ".mp3", ".ogg"]:
		for i in range(1, 6):
			if ResourceLoader.exists(AUDIO + "%s_%d%s" % [stem, i, ext]): variants.append(AUDIO + "%s_%d%s" % [stem, i, ext])
		if variants.is_empty() and ResourceLoader.exists(AUDIO + stem + ext): variants.append(AUDIO + stem + ext)
	voice.stream = load(variants[randi() % variants.size()]) if not variants.is_empty() else null
	voice.volume_db = volume
	voice.unit_size = 12
	voice.max_distance = distance
	voice.attenuation_filter_cutoff_hz = 9500
	add_child(voice)
	voice.play()
	voice.finished.connect(voice.queue_free)
	return voice
