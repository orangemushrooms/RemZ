extends SceneTree

var checks := 0
var failures := 0
var game: Node3D
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 150000:
		push_error("TITAN_HORROR_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.weapons.set_process(false)
	var p: Player = game.player
	p.max_hp = 200
	p.hp = 200
	p.set_physics_process(false)
	p.global_position = Map.ground_pos(20, 105)
	var original_position := p.global_position
	var original_pitch := p.pitch
	var original_fov := p.camera.fov
	for name in ["roar_1", "roar_2", "roar_3", "windup", "death", "step_1", "step_2", "slam"]:
		var stream: AudioStream = load(TitanPresence.DIR + name + ".wav")
		check(stream is AudioStreamWAV and stream.get_length() > 1.5, name + " is a dedicated, imported, non-looping sound")
		if stream is AudioStreamWAV: check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, name + " cannot loop indefinitely")
	game.spawn_zombie("titan", Vector2(20, 125), 1, "east")
	var titan: Titan = game.zombies_root.get_children().back()
	titan.set_physics_process(false)
	titan.agent.avoidance_enabled = false
	await process_frame
	var presence := game.get_node("TitanPresence") as TitanPresence
	presence.set_process(false)
	check(int(presence.received.get("arrival", 0)) == 1, "Titan emits one arrival cry after spawn")
	check(presence._pending.size() == 1 and presence._pending[0].origin.distance_to(titan.global_position) < 0.1, "Arrival uses actual field position instead of map origin")
	check(int(presence.received.get("step", 0)) == 0, "Spawn displacement cannot cause a phantom footstep")
	presence._process(0.8)
	check(presence._voices.size() == 1 and presence._voices[0].bus == "Titans", "Dedicated spatial roar uses a controlled titan mix")
	check(presence._voices[0].max_distance >= 230 and presence._voices[0].global_position.y > titan.global_position.y + 15, "Roar travels across the field from the giant's head")
	check(game.music._titan_hold > 0 and game.music._titan_duck > 0, "Nearby roar briefly makes room in the music mix")
	presence.receive("arrival", titan.global_position, titan.height, titan.appearance_seed, 1)
	check(presence.received.arrival == 1, "Repeated event serial never replays the same roar")
	var before := presence.received.duplicate()
	titan.replica = true
	titan.emit_cue("rage")
	titan.replica = false
	check(presence.received == before, "Replicas do not generate duplicate boss events")
	titan.set_process(false)
	titan.strike_phase = "walk"
	titan._last_position = titan.global_position
	for i in 20: titan._process(0.1)
	check(int(presence.received.get("step", 0)) == 0, "Stationary walk animation creates no phantom ground impacts")
	for i in 25:
		titan.global_position.z -= 0.34
		titan._process(0.1)
	check(int(presence.received.get("step", 0)) >= 1 and int(presence.received.get("step", 0)) <= 3, "Moving giant produces bounded heavy footsteps")
	titan.begin_strike(Map.ground_pos(20, 110))
	check(int(presence.received.get("windup", 0)) == 1, "Attack warning emits its own vocal cue")
	presence._process(1.0)
	var voices := 0
	for sound in presence._voices:
		if is_instance_valid(sound) and bool(sound.get_meta("voice")): voices += 1
	check(voices == 1, "Short attack grunt cannot stack over the arrival roar")
	titan.resolve_strike()
	check(int(presence.received.get("slam", 0)) == 1, "Impact emits exactly one distinct slam")
	presence._pending.clear()
	p._clear_tremor()
	presence.receive("step", p.global_position + Vector3(8, 0, 0), 27, 901, 1)
	presence._process(0.01)
	check(p._tremor == 0, "Ground vibration respects travel delay")
	presence._process(0.3)
	var near_strength := p._tremor
	check(near_strength > 0.15 and near_strength < 0.4, "Nearby step gives a subtle, finite tremor")
	p._clear_tremor()
	presence.receive("step", p.global_position + Vector3(65, 0, 0), 27, 902, 1)
	presence._process(1.0)
	check(p._tremor > 0 and p._tremor < near_strength * 0.2, "Distant footsteps are much gentler")
	p._clear_tremor()
	presence.receive("slam", p.global_position + Vector3(140, 0, 0), 27, 903, 1)
	presence._process(1.5)
	check(p._tremor == 0, "Distant audible slam does not shake the entire map")
	p.add_tremor(0.8, 1.55)
	var peak_displacement := 0.0
	for i in 150:
		p.camera.rotation.z = 0
		p._update_tremor(1.0 / 60)
		peak_displacement = maxf(peak_displacement, p.camera.position.length())
	check(peak_displacement > 0.008 and peak_displacement < 0.045, "Shake moves the view only a few centimetres")
	check(p.camera.position == Vector3.ZERO and p.camera.rotation.x == 0, "Camera settles exactly without persistent drift")
	check(p.global_position == original_position and p.pitch == original_pitch and p.camera.fov == original_fov, "Tremor does not displace player, mouse aim or FOV")
	for i in 100: p.add_tremor(0.8, 1.5)
	check(p._tremor <= 1.0, "Multiple giants cannot stack unbounded shaking")
	p._clear_tremor()
	p.active = false
	p.add_tremor(1, 1)
	check(p._tremor == 0, "Menu interaction suppresses new camera tremors")
	p.active = true
	p.alive = false
	p.add_tremor(1, 1)
	check(p._tremor == 0, "Dead player receives no new camera tremors")
	p.alive = true
	game.settings.tremor = 0
	game.settings.apply()
	p.add_tremor(1, 1)
	check(p._tremor == 0 and p.tremor_scale == 0, "Settings slider can disable the vibration")
	game.settings.tremor = 1
	game.settings.apply()
	titan.hp = titan.max_hp * 0.39
	titan._physics_process(0.1)
	titan._physics_process(0.1)
	check(int(presence.received.get("rage", 0)) == 1, "Crossing the rage threshold produces exactly one rage cry")
	titan.strike_phase = "walk"
	titan._roar_time = 0
	titan._physics_process(0.1)
	check(int(presence.received.get("roar", 0)) == 1 and titan._roar_time >= 20, "Approach cries have long quiet intervals")
	titan.die(Vector3.ZERO)
	titan.die(Vector3.ZERO)
	check(int(presence.received.get("death", 0)) == 1, "Boss death cry plays once")
	await create_timer(1.9, false).timeout
	check(int(presence.received.get("collapse", 0)) == 1, "Falling body lands with a delayed ground impact")
	game.music._process(10.0)
	game.music._process(3.0)
	check(is_equal_approx(game.music._titan_mix, 1.0), "Music recovers after the cry ends")
	print("TITAN_HORROR_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
