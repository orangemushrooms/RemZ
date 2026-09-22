extends Node3D

const Shell = preload("res://scripts/firework_effect.gd")
var kind := "fw_battery_40"
var origin := Vector3.ZERO
var landing := Vector3.ZERO
var random_seed := 1
var age := 0.0
var next_shot := 0
var body: Node3D
var fuse: GPUParticles3D
var fuse_voice: AudioStreamPlayer3D
var launch_height := 0.4

static func model(id: String, held := false) -> Node3D:
	var spec: Dictionary = Fireworks.DEFS[id]
	var prop := WorldModels.create(spec.model, 0.3 if held else float(spec.width), 0)
	return prop if prop else Node3D.new()

func configure(id: String, start: Vector3, end: Vector3, seed_value: int, elapsed: float, _path := PackedVector3Array()) -> void:
	kind = id
	origin = start
	landing = end
	random_seed = seed_value
	age = elapsed

func state() -> Array:
	return [kind, origin, landing, random_seed, age, PackedVector3Array()]

func shot_time(index: int) -> float:
	var spec: Dictionary = Fireworks.DEFS[kind]
	var count := int(spec.shots)
	var finale := 8 if count < 40 else 16
	var regular := count - finale
	var units := float(regular) + float(finale - 1) * 0.45
	return 1.2 + float(spec.duration) * (float(index) if index < regular else regular + (index - regular) * 0.45) / units

func _ready() -> void:
	global_position = origin
	body = model(kind)
	add_child(body)
	# The opened carton includes an upright lid above its tube deck.
	launch_height = maxf(0.15, Barricade._bounds(body).size.y * (0.52 if kind == "fw_battery_40" else 0.96))
	fuse = Shell.particles(Color(1, 0.58, 0.12), 16, 0.25, 0.025, 0.7, Vector3.DOWN, false)
	add_child(fuse)
	fuse.position = Vector3(float(Fireworks.DEFS[kind].width) * 0.45, 0.12, 0)
	if age < 1.2:
		fuse_voice = AudioStreamPlayer3D.new()
		fuse_voice.stream = preload("res://assets/audio/fireworks/fuse.wav")
		fuse_voice.volume_db = -15
		fuse_voice.max_distance = 22
		add_child(fuse_voice)
		fuse_voice.play()
	_tick()

func _process(delta: float) -> void:
	age += delta
	_tick()
	if age > 1.2 + float(Fireworks.DEFS[kind].duration) + 10.0: queue_free()

func _tick() -> void:
	var count := int(Fireworks.DEFS[kind].shots)
	if age >= 1.2 and is_instance_valid(fuse_voice): fuse_voice.stop()
	fuse.emitting = age < 1.2 + float(Fireworks.DEFS[kind].duration)
	while next_shot < count and shot_time(next_shot) <= age:
		var elapsed := age - shot_time(next_shot)
		# Restore only still-visible shells for late joiners; never replay old salvos.
		if elapsed < 9.7:
			var shell = Shell.new()
			var styles := ["fw_ruby", "fw_aurora", "fw_gold"]
			var style: String = "fw_gold" if next_shot >= count - 5 else styles[(next_shot + random_seed) % styles.size()]
			var offset := Vector3(float(next_shot % 6) / 5.0 - 0.5, 0.32, float((next_shot / 6) % 3) * 0.08 - 0.08) * float(Fireworks.DEFS[kind].width)
			offset.y = launch_height
			shell.shell_mode = true
			shell.shell_drift = Vector3((float(next_shot % 5) - 2.0) * 3.0, 0, sin(float(next_shot) * 2.4) * 3.0)
			shell.configure(style, origin + offset, origin, (random_seed + next_shot * 7919) & 0x7fffffff, elapsed)
			shell.burst_at = 2.2
			add_child(shell)
		next_shot += 1
