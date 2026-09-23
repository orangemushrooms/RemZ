# Headless checks for hits at long range and the per-surface footsteps:
#   Godot.exe --headless --path godot --script res://tests/range_steps.gd -- --smoke-test --no-intro --no-music
# Also writes the procedural step textures to ../artifacts/footsteps/*.wav for offline inspection.
extends SceneTree

var checks := 0
var failures := 0
var game: Node

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	if game.achievements:
		game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
		game.achievements = null
	while not game.navigation_ready:
		await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var player: Player = game.player
	var weapons: Weapons = game.weapons
	weapons.spread_mul = 0.0
	for id in ["pistol", "smg", "shotgun"]:
		weapons.unlock(id)
	# ---- long-range hits on the open meadow (no trees between)
	for spec in [[Vector2(-40, 110), Vector2(20, 110), "pistol", 60.0], [Vector2(-60, 115), Vector2(120, 115), "pistol", 180.0], [Vector2(-60, 115), Vector2(120, 115), "smg", 180.0], [Vector2(-60, 115), Vector2(100, 115), "shotgun", 160.0]]:
		var from: Vector2 = spec[0]
		var at: Vector2 = spec[1]
		var wid: String = spec[2]
		weapons.set_weapon(wid)
		game.spawn_zombie("shambler", at, 1.0)
		await physics_frame
		var z: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
		z.set_physics_process(false)
		z.agent.avoidance_enabled = false
		z.global_position = Map.ground_pos(at.x, at.y)
		player.global_position = Map.ground_pos(from.x, from.y) + Vector3.UP * 0.2
		player.pitch = 0.0
		await physics_frame
		await physics_frame
		var target := z.global_position + Vector3.UP * z.height * 0.5
		player.look_at(Vector3(target.x, player.global_position.y, target.z), Vector3.UP, true)
		player.camera.look_at(target)
		var hp0 := z.hp
		var dist := player.camera.global_position.distance_to(target)
		# Aim.spread keeps a minimum cone (maxf(0.25, precision) plus a hip term), so a single
		# shot at this range is a dice roll by design. Fire aimed bursts instead: the point here
		# is that "range" only starts the damage falloff and never shortens the 600 m hit ray.
		weapons.ads = 1.0
		for _shot in 8:
			weapons._aim_kick = Vector2.ZERO
			weapons._bloom = 0.0
			weapons.cur().cooldown = 0.0
			weapons.cur().ammo = 30
			weapons.try_fire()
			if z.hp < hp0: break
		weapons.ads = 0.0
		check(z.hp < hp0, "%s hits a zombie at %.0f m (hp %.0f -> %.0f)" % [wid, dist, hp0, z.hp])
		z.queue_free()
		await physics_frame
	# ---- footsteps: buses, textures, surface classification
	Sfx.footstep(player, "grass", -14.0, 1.0)
	Sfx.footstep(player, "leaves", -14.0, 1.0)
	Sfx.footstep(player, "gravel", -14.0, 1.0)
	Sfx.footstep(player, "wood", -14.0, 1.0)
	Sfx.footstep(player, "hard", -14.0, 1.0)
	Sfx.footstep(player, "corn", -14.0, 1.0)
	for bus in ["StepGrass", "StepSoft", "StepGravel", "StepWood", "StepCorn"]:
		var idx := AudioServer.get_bus_index(bus)
		check(idx >= 0 and AudioServer.get_bus_effect(idx, 0) is AudioEffectLowPassFilter, "%s bus exists with a low-pass filter" % bus)
	var cut_soft: float = (AudioServer.get_bus_effect(AudioServer.get_bus_index("StepSoft"), 0) as AudioEffectLowPassFilter).cutoff_hz
	var cut_gravel: float = (AudioServer.get_bus_effect(AudioServer.get_bus_index("StepGravel"), 0) as AudioEffectLowPassFilter).cutoff_hz
	check(cut_soft < cut_gravel, "Forest floor is duller than gravel (%.0f Hz < %.0f Hz)" % [cut_soft, cut_gravel])
	for pair in [[Vector2(120, 0), "hard"], [Vector2(70, 41), "gravel"], [Vector2(7, -7), "gravel"], [Vector2(60, 80), "grass"], [Vector2(-40, -40), "leaves"]]:
		player.global_position = Map.ground_pos(pair[0].x, pair[0].y) + Vector3.UP * 0.2
		var surface := player._surface_step()
		check(surface == pair[1], "Surface at %s is %s (got %s)" % [pair[0], pair[1], surface])
	var hut: Dictionary = Map.BUILDINGS["waldhuette"]
	player.global_position = Map.ground_pos(hut.pos.x, hut.pos.y) + Vector3.UP * 0.2
	check(player._surface_step() == "hard", "Garage floor is hard")
	player.global_position = Map.ground_pos(hut.pos.x, hut.pos.y) + Vector3.UP * 2.9
	check(player._surface_step() == "wood", "Upper hut room is wood")
	# ---- maize: steps and the brush loop only inside standing corn
	var field = game.cornfield
	var stalk := Vector2.ZERO
	for sample in 6000:
		var probe: Vector2 = field.field_to_world(Vector2(6.0 + (sample % 130), 2.0 + float((sample / 130) % 48)))
		if field.in_corn(probe):
			stalk = probe
			break
	check(stalk != Vector2.ZERO, "Found standing maize to walk into")
	player.global_position = Map.ground_pos(stalk.x, stalk.y) + Vector3.UP * 0.2
	check(player._surface_step() == "corn", "Standing maize sounds like corn, not meadow")
	var passage: Vector2 = field.field_to_world(field.ORIGIN + (Vector2(field.passages.keys()[0]) + Vector2.ONE * 0.5) * field.CELL)
	check(not field.in_corn(passage), "A cleared maze passage stays silent")
	check(field.rustle != null and field.rustle.playing and field.rustle.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Leaf brush loop runs and loops seamlessly")
	field.rustle.volume_db = -60.0
	player.velocity = Vector3(3.5, 0, 0)
	for i in 30: field._update_rustle(0.05)
	var moving_db: float = field.rustle.volume_db
	check(moving_db > -35.0, "Walking through the maize raises the leaf brush (%.1f dB)" % moving_db)
	player.velocity = Vector3.ZERO
	for i in 40: field._update_rustle(0.05)
	check(field.rustle.volume_db < moving_db - 10.0, "Standing still in the field goes quiet again (%.1f dB)" % field.rustle.volume_db)
	# ---- dump textures
	var dir := ProjectSettings.globalize_path("res://") + "../artifacts/footsteps/"
	DirAccess.make_dir_recursive_absolute(dir)
	for surface in ["grass", "leaves", "gravel", "wood", "corn"]:
		var st: AudioStreamWAV = Sfx._step_texture(surface, 0)
		if st:
			st.save_to_wav(dir + "texture_%s.wav" % surface)
	Sfx.corn_bed().save_to_wav(dir + "corn_bed.wav")
	print("RANGE_STEPS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
