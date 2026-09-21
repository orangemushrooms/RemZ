extends SceneTree

var game: Node
var cycle: DayNightCycle
var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()
var folder: String
var samples: Array = []

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("DAY_NIGHT_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	# The default is the continuous 15-minute day (user request); --continuous-day-night forces it, the
	# checks below derive their numbers from the clock so both policies pass.
	var clock := DayNightCycle.new()
	if "--continuous-day-night" in OS.get_cmdline_user_args():
		clock.time_scale = 96.0
		clock.reset_each_wave = false
	var continuous := not clock.reset_each_wave
	var speed := clock.time_scale
	check(is_equal_approx(clock.time_scale, DayNightCycle.DAY_SECONDS / (DayNightCycle.CONTINUOUS_DAY_MINUTES * 60.0)) or is_equal_approx(clock.time_scale, 10.0), "Selected mode has the expected time scale")
	clock.advance(3600.0 / speed)
	check(absf(clock.clock_seconds - 7.0 * 3600.0) < 0.001, "Selected mode advances exactly one game hour")
	for fps in [30, 60, 144]:
		clock.clock_seconds = DayNightCycle.MORNING_SECONDS
		for frame in fps * 6:
			clock.advance(1.0 / fps)
		check(absf(clock.clock_seconds - (6.0 * 3600.0 + 6.0 * clock.time_scale)) < 0.001, "Clock is frame-rate independent at %d FPS" % fps)
	clock.clock_seconds = 86395.0
	clock.advance(1.0)
	var wrapped := 86395.0 + clock.time_scale - 86400.0
	check(is_equal_approx(clock.clock_seconds, wrapped), "Midnight wraps without losing elapsed seconds")
	check(DayNightCycle.clock_text(0.0) == "00:00" and DayNightCycle.clock_text(86399.0) == "23:59", "Clock displays valid hours and minutes at midnight")
	clock.advance(3.0 * DayNightCycle.DAY_SECONDS / speed)
	check(absf(clock.clock_seconds - wrapped) < 0.001, "Long sessions support multiple complete days")
	clock.advance(-10.0)
	check(absf(clock.clock_seconds - wrapped) < 0.001, "Negative deltas cannot rewind the clock")
	clock.time_scale = DayNightCycle.DAY_SECONDS / (DayNightCycle.CONTINUOUS_DAY_MINUTES * 60.0)
	clock.reset_each_wave = false
	clock.set_time_hours(6.0)
	clock.advance(450.0)
	check(is_equal_approx(clock.clock_seconds, 18.0 * 3600.0), "Optional continuous 15-minute mode reaches evening after 7.5 minutes")
	clock.start_wave(2)
	check(is_equal_approx(clock.clock_seconds, 18.0 * 3600.0), "Optional continuous mode keeps its time across waves")
	clock.reset_each_wave = true
	clock.start_wave(3)
	check(is_equal_approx(clock.clock_seconds, DayNightCycle.MORNING_SECONDS), "Default wave-reset behaviour can be restored")
	clock.free()
	check(DayNightCycle.sun_direction_at(7.0).x > 0.0 and DayNightCycle.sun_direction_at(17.0).x < 0.0, "Sun rises east and sets west, matching minimap compass")
	var previous := 1.0
	var monotonic := true
	for i in 36:
		var day := DayNightCycle.daylight_at(16.5 + i * 0.1)
		monotonic = monotonic and day <= previous + 0.00001
		previous = day
	check(monotonic and previous == 0.0, "Evening darkens progressively from daylight to night")
	check(is_equal_approx(DayNightCycle.daylight_at(0), DayNightCycle.daylight_at(24)), "Lighting has no jump at midnight")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	# Isolate tests from persistent achievements/rewards, including Waves.start.
	if game.achievements:
		game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
		game.achievements.hide()
		game.achievements = null
	while not game.navigation_ready:
		await process_frame
	cycle = game.day_night
	check(cycle.clock_seconds == DayNightCycle.MORNING_SECONDS and game.hud.clock_label.text == "06:00" and game.hud.clock_rate.text == "%d× · Spielzeit" % int(speed), "Start screen is held at 06:00 and displays the selected speed")
	# The independently developed opening sequence has its own fog/overlays.
	# These checks exercise the wave gameplay after that sequence.
	game._flags.append("--no-intro")
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	cycle.set_process(false)
	cycle.set_time_hours(22.0)
	game.waves.start(1)
	check(absf(cycle.clock_seconds - (22.0 if continuous else 6.0) * 3600.0) < 0.001, "First wave follows the selected reset policy")
	cycle.set_time_hours(18.75)
	game.waves.start(2)
	check(absf(cycle.clock_seconds - (18.75 if continuous else 6.0) * 3600.0) < 0.001 and game.hud.clock_phase.text == ("Abend" if continuous else "Morgen"), "Later waves follow the selected reset policy and phase")
	cycle.set_time_hours(6.0)
	cycle._process(60.0 / speed)
	check(game.hud.clock_label.text == "06:01", "Active gameplay advances visible clock")
	# The daylight song belongs to the pause after a wave; the round itself still opens on the night loop.
	var clock_before: float = cycle.clock_seconds
	var phase_before: String = game.waves.phase
	var cleared_before: int = game.waves.completed
	game.music.play("combat")
	game.waves._complete_wave()
	check(game.music.current == "morning" and game.music._players.morning.stream.resource_path.ends_with("survived_the_night.mp3"),
		"A wave cleared in the morning switches to the daylight song")
	cycle.set_time_hours(22.0)
	game.music.play("combat")
	game.waves._complete_wave()
	check(game.music.current == "night", "A wave cleared at night keeps the night loop")
	game.waves.phase = phase_before
	game.waves.completed = cleared_before
	cycle.clock_seconds = clock_before
	var before := cycle.clock_seconds
	game._pause()
	cycle._process(60.0)
	check(cycle.clock_seconds == before, "Escape pause freezes world time")
	game._on_start()
	game.inventory.open()
	cycle._process(60.0)
	check(cycle.clock_seconds == before, "Inventory freezes world time")
	game.inventory.close()
	game.skills.open()
	cycle._process(60.0)
	check(cycle.clock_seconds == before, "Skills menu freezes world time")
	game.skills.close()
	game.barricade_menu.open()
	cycle._process(60.0)
	check(cycle.clock_seconds == before, "Barricade planner freezes world time")
	game.barricade_menu.close()
	game.over = true
	cycle._process(60.0)
	check(cycle.clock_seconds == before, "Game over freezes world time")
	game.over = false
	game.player.active = false
	cycle._process(60.0)
	check(cycle.clock_seconds == before, "Inactive player cannot advance world time")
	game.player.active = true
	cycle.set_process(true)
	await create_timer(0.2, true).timeout
	check(cycle.clock_seconds > before, "Clock advances through the actual scene process loop")
	paused = true
	before = cycle.clock_seconds
	await create_timer(0.2, true).timeout
	check(cycle.clock_seconds == before, "Scene-tree pause freezes the actual process loop")
	paused = false
	cycle.set_process(false)
	cycle.set_time_hours(12.0)
	var sun_day: float = game.settings.sun.light_energy
	var fill_day: float = game.fill_light.light_energy
	var flame_day := cycle.fire_energy_multiplier
	var lamp: Light3D = get_nodes_in_group("day_night_lamps")[0]
	var lamp_day := lamp.light_energy
	var hands_day: float = game.weapons.viewmodel._key_light.light_energy
	var lights_before := game.find_children("*", "Light3D", true, false).size()
	cycle.set_time_hours(23.0)
	check(game.settings.sun.light_energy < sun_day * 0.01 and game.fill_light.light_energy < fill_day * 0.35, "Night substantially dims sunlight and fill")
	check(cycle.fire_energy_multiplier > flame_day and lamp.light_energy > lamp_day, "Fire and fixture lights brighten at night")
	check(game.weapons.viewmodel._key_light.light_energy < hands_day * 0.4, "Hands and weapons share the darker night lighting")
	check(game.weapons.viewmodel._environment.sky.sky_material is ShaderMaterial and game.weapons.viewmodel._environment.sky.process_mode == Sky.PROCESS_MODE_QUALITY, "Weapon reflection sky stays static while its light changes")
	check(not game.player.flashlight.visible, "Time of day preserves manual flashlight control")
	check(game.find_children("*", "Light3D", true, false).size() == lights_before, "Night adds no extra lights or shadows")
	var sky: Sky = game.settings.env.sky
	check(sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL and sky.radiance_size == Sky.RADIANCE_SIZE_128, "Sky reflections use a bounded incremental bake")
	for profile in 3:
		game.settings.profile = profile
		game.settings.apply()
		check(game.settings.env.sky == sky and cycle.clock_seconds == 23.0 * 3600.0 and game.settings.sun.light_energy == 0.0, "Quality %d preserves the current night" % profile)
		check(game.settings.env.volumetric_fog_enabled == (profile > 0), "Quality %d retains its volumetric-fog budget" % profile)
	game.settings.profile = 0
	game.settings.apply()
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		await visuals()
	print("DAY_NIGHT_DONE checks=%d failures=%d rendered=%s" % [checks, failures, rendered])
	quit(0 if failures == 0 else 1)

func visuals() -> void:
	folder = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/day-night")
	DirAccess.make_dir_recursive_absolute(folder)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.weapons.set_process(false)
	game.hud.msg_label.text = ""
	game.hud.prompt_label.text = ""
	game.hud.set_wave(2, "Waldhütte Remetschwil")
	for view in [["lager", Vector2(3, 14), 0.05, -0.04], ["alpen", Vector2(95, 88), 2.45, 0.055]]:
		game.player.global_position = Map.ground_pos(view[1].x, view[1].y) + Vector3.UP * 0.1
		game.player.rotation.y = view[2]
		game.player.pitch = view[3]
		game.player.head.rotation.x = view[3]
		for hour in [6.0, 12.0, 18.5, 23.0]:
			cycle.set_time_hours(hour)
			# Even under concurrent GPU load, allow the incremental radiance bake
			# to finish before reviewing an abruptly changed test time.
			for frame in 16:
				await process_frame
			await screenshot("%s-%04d" % [view[0], int(hour * 100)])
			check(game.hud.clock_label.text == DayNightCycle.clock_text(hour * 3600), "Rendered clock agrees with %s at %.1f h" % [view[0], hour])
	game.player.global_position = Map.ground_pos(-15, -30) + Vector3.UP * 0.1
	game.player.rotation.y = 0.35
	game.player.head.rotation.x = 0.02
	game.player.flashlight.visible = true
	await create_timer(0.5, true).timeout
	await screenshot("wald-nacht-taschenlampe")
	game.player.flashlight.visible = false
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	var panel: Control = game.hud.clock_label.get_parent().get_parent().get_parent()
	var rect := panel.get_global_rect()
	var logical_size := panel.get_viewport_rect().size
	check(rect.position.x >= logical_size.x * 0.6 and rect.end.x <= logical_size.x and rect.position.y >= 0.0, "Clock fits top-right at 1280x720")
	await screenshot("uhr-1280x720")
	root.size = Vector2i(1600, 900)
	game.settings.profile = 2
	game.settings.apply()
	await create_timer(1.0, true).timeout
	await screenshot("nacht-hohe-qualitaet")
	game.settings.profile = 0
	game.settings.apply()
	if "--day-night-benchmark" in OS.get_cmdline_user_args():
		# Paired static/running clock with all other simulation frozen. Include
		# sky updates during measurement, but exclude setup/shader warm-up.
		paused = true
		game.hud.hide()
		game.weapons.viewmodel.hide()
		game.weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		for running in [false, true, true, false]:
			cycle.set_time_hours(12.0)
			await create_timer(1.0, true).timeout
			samples.append(await measure(running))
	var note := "Functional checks and visual views; no performance comparison requested."
	if not samples.is_empty():
		note = "Paired stationary forest scene: frozen vs advancing clock at 10x, all other gameplay paused; sky updates included. Concurrent editor/game left running. Not an absolute gameplay FPS guarantee."
	var report := {"checks": checks, "failures": failures, "time_scale": cycle.time_scale, "gpu": RenderingServer.get_video_adapter_name(), "samples": samples, "note": note}
	var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	check(error == OK, "Screenshot " + label)

func measure(running: bool) -> Dictionary:
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var frames: Array[float] = []
	var calls: Array[float] = []
	var begin := Time.get_ticks_usec()
	var previous := begin
	while Time.get_ticks_usec() - begin < 4500000:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := (now - previous) / 1000000.0
		previous = now
		if running:
			cycle.advance(delta)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		frames.append(delta * 1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	gpu.sort(); cpu.sort(); frames.sort(); calls.sort()
	var result := {"running": running, "frames": frames.size(), "frame_ms_median": frames[frames.size() / 2], "gpu_ms_median": gpu[gpu.size() / 2], "gpu_ms_p95": gpu[int(gpu.size() * 0.95)], "cpu_ms_median": cpu[cpu.size() / 2], "draw_calls": calls[calls.size() / 2]}
	print("DAY_NIGHT_SAMPLE ", JSON.stringify(result))
	return result
