# Reproducible rendered 300-enemy stress test. No graphics settings are reduced.
# --suite=horde_performance --smoke-test --no-intro --no-music --horde-report=before
extends SceneTree

class MeasuredTower extends DefenceTower:
	var tick_us := 0
	var visibility_us := 0
	var visibility_calls := 0
	var fire_us := 0
	var max_tick_us := 0
	func _physics_process(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._physics_process(delta)
		var elapsed := Time.get_ticks_usec() - start
		tick_us += elapsed
		max_tick_us = maxi(max_tick_us, elapsed)
	func can_see(enemy: Zombie) -> bool:
		var start := Time.get_ticks_usec()
		var result := super.can_see(enemy)
		visibility_us += Time.get_ticks_usec() - start
		visibility_calls += 1
		return result
	func fire_at(aim: Vector3) -> void:
		var start := Time.get_ticks_usec()
		super.fire_at(aim)
		fire_us += Time.get_ticks_usec() - start

var game: Node
var began := Time.get_ticks_msec()
var collecting := false
var previous := 0
var samples: Array[float] = []
var physics_samples: Array[float] = []
var process_samples: Array[float] = []
var reports: Array = []
var report_name := "current"
var spawn_times: Array[float] = []
var spawn_frames: Array[float] = []
var combat := false

func _initialize() -> void: call_deferred("run")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if collecting and previous > 0:
		samples.append((now - previous) / 1000.0)
		physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	previous = now
	if combat and game:
		game.weapons.cur().ammo = 1000
		game.weapons.try_fire()
	if Time.get_ticks_msec() - began > 300000:
		push_error("HORDE_PERFORMANCE_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	seed(4242)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--horde-report="): report_name = argument.get_slice("=", 1).validate_filename()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.weapons.set_process(false)
	game.player.max_hp = 1000000
	game.player.hp = 1000000
	game.hut.hp = 1000000
	game.day_night.set_time_hours(17.5)
	game.day_night.set_process(false)
	game.player.global_position = Map.ground_pos(0, 85) + Vector3.UP * 0.2
	game.player.camera.look_at(Map.ground_pos(0, 115) + Vector3.UP)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for population in [0, 72, 150, 300]:
		spawn_times.clear()
		spawn_frames.clear()
		while game.alive_zombies() < population:
			var i: int = game.alive_zombies()
			var start := Time.get_ticks_usec()
			game.spawn_zombie(["shambler", "runner", "soldier", "nurse", "brute"][i % 5], Vector2(-28 + (i % 20) * 3, 108 + (i / 20) * 3), 1.0)
			spawn_times.append((Time.get_ticks_usec() - start) / 1000.0)
			await process_frame
			spawn_frames.append((Time.get_ticks_usec() - start) / 1000.0)
		await measure("live_%d" % population)
	if "--horde-combat" in OS.get_cmdline_user_args():
		for z in game.zombies_root.get_children():
			if z is Zombie: z.hp = 1000000.0
		for i in 6:
			var tower := MeasuredTower.new()
			tower.game = game
			tower.tower_id = game.defences.next_id
			game.defences.next_id += 1
			tower.kind = DefenceTower.TYPES[i % 5]
			tower.position = Map.ground_pos(-13 + i * 5, 94)
			game.add_child(tower)
			game.defences.towers[tower.tower_id] = tower
			tower.rotation.y = PI
			tower.hp = 1000000.0
		game.weapons.unlock("lmg")
		game.weapons.set_weapon("lmg")
		game.weapons.set_process(true)
		combat = true
		await measure("combat_300_six_towers", 12.0)
		combat = false
		if "--horde-late-wave" in OS.get_cmdline_user_args():
			# A 300-enemy wave uses the unchanged active cap, leaving corpses and
			# loot behind. Keep all 228 dead models; do not hide graphics to pass.
			var remaining_deaths := maxi(0, game.alive_zombies() - 72)
			for z in game.zombies_root.get_children():
				if not is_instance_valid(z) or not z is Zombie or not z.alive or remaining_deaths <= 0: continue
				z.die(Vector3.ZERO)
				remaining_deaths -= 1
				if remaining_deaths % 6 == 0: await process_frame
			await create_timer(8.0).timeout
			combat = true
			await measure("late_wave_72_alive_228_dead_six_towers", 12.0)
			combat = false
	if "--horde-diagnose" in OS.get_cmdline_user_args():
		for z in game.zombies_root.get_children():
			if not z is Zombie: continue
			z.set_physics_process(false)
			z.agent.avoidance_enabled = false
		await measure("diagnostic_no_ai")
		for z in game.zombies_root.get_children():
			if not z is Zombie: continue
			if z.anim: z.anim.pause()
		await measure("diagnostic_no_animation")
	var report := save_report(true)
	print("HORDE_PERFORMANCE_DONE ", JSON.stringify(report))
	quit(0)

func save_report(complete := false) -> Dictionary:
	var report := {"complete": complete, "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "rendered": DisplayServer.get_name() != "headless",
		"resolution": str(root.size), "profile": game.settings.profile, "scale": root.scaling_3d_scale, "scenes": reports}
	var folder := ProjectSettings.globalize_path("res://../logs")
	var output := FileAccess.open(folder.path_join("horde-performance-%s.json" % report_name), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	return report

func measure(label: String, duration := 5.0) -> void:
	await create_timer(2.0).timeout
	for tower in get_nodes_in_group("defence_towers"):
		if tower is MeasuredTower:
			tower.tick_us = 0
			tower.visibility_us = 0
			tower.visibility_calls = 0
			tower.fire_us = 0
			tower.max_tick_us = 0
	samples.clear()
	physics_samples.clear()
	process_samples.clear()
	collecting = true
	await create_timer(duration).timeout
	collecting = false
	var total := 0.0
	for value in samples: total += value
	samples.sort()
	physics_samples.sort()
	process_samples.sort()
	spawn_times.sort()
	spawn_frames.sort()
	var report := {"stage": label, "alive": game.alive_zombies(), "frames": samples.size(), "average_fps": samples.size() * 1000.0 / total,
		"p95_ms": samples[int(samples.size() * 0.95)], "p99_ms": samples[int(samples.size() * 0.99)], "max_ms": samples.back(),
		"physics_p95_ms": physics_samples[int(physics_samples.size() * 0.95)], "process_p95_ms": process_samples[int(process_samples.size() * 0.95)],
		"spawn_p95_ms": spawn_times[int(spawn_times.size() * 0.95)] if not spawn_times.is_empty() else 0.0,
		"spawn_max_ms": spawn_times.back() if not spawn_times.is_empty() else 0.0,
		"spawn_frame_p95_ms": spawn_frames[int(spawn_frames.size() * 0.95)] if not spawn_frames.is_empty() else 0.0,
		"spawn_frame_max_ms": spawn_frames.back() if not spawn_frames.is_empty() else 0.0,
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "nodes": get_node_count()}
	var tower_reports: Array = []
	for tower in get_nodes_in_group("defence_towers"):
		if tower is MeasuredTower:
			tower_reports.append({"kind": tower.kind, "tick_ms_per_second": tower.tick_us / total, "visibility_ms_per_second": tower.visibility_us / total,
				"visibility_calls": tower.visibility_calls, "fire_ms_per_second": tower.fire_us / total, "max_tick_ms": tower.max_tick_us / 1000.0, "shots": tower.shots})
	if not tower_reports.is_empty(): report.towers = tower_reports
	report.meets_60fps_p95 = float(report.p95_ms) <= 1000.0 / 60.0
	reports.append(report)
	save_report()
	print("HORDE_PERFORMANCE_STAGE ", JSON.stringify(report))
	if "--horde-capture" in OS.get_cmdline_user_args() and "300" in label and DisplayServer.get_name() != "headless":
		var folder := ProjectSettings.globalize_path("res://../artifacts/horde")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder.path_join(report_name + "-" + label + ".png"))
