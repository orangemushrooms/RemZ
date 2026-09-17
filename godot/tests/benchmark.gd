extends SceneTree

# Rendered benchmark. Startup, navigation bake and shader warm-up are excluded.
# Run with --script res://tests/benchmark.gd -- --benchmark --quality=0
const VIEWS := [
	["Lichtung", Vector2(-1, 13), 0.0, 0.02],
	["Waldhuette", Vector2(-15, -7), -PI / 2.0 - 0.35, 0.0],
	["Weggabelung", Vector2(7, 58), 0.0, 0.03],
	["Weg_zur_Huette", Vector2(96, 33), PI / 2.0 + 0.25, 0.02],
	["Sennhofstrasse", Vector2(122, -20), PI, 0.0],
]
var game: Node
var samples: Array[float] = []
var collecting := false
var previous := 0
var reports: Array = []
var started_at := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if collecting and previous > 0:
		samples.append((now - previous) / 1000.0)
	previous = now
	if Time.get_ticks_msec() - started_at > 180000:
		push_error("BENCHMARK_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A GPU benchmark requires a rendered window; headless FPS are not valid.")
		quit(1)
		return
	seed(4242)
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1920, 1080)
	root.position = Vector2i.ZERO
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready:
		await process_frame
	game._on_start()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.weapons.set_process(false)
	game.player.max_hp = 100000.0
	game.player.hp = 100000.0
	await create_timer(3.0).timeout
	for view in VIEWS:
		await measure(view)
	game.player.global_position = Map.ground_pos(-1, 13) + Vector3.UP * 0.3
	for i in 36:
		var angle := i * TAU / 36.0
		game.spawn_zombie(["shambler", "runner", "brute", "nurse", "soldier"][i % 5], Map.FIRE + Vector2(cos(angle), sin(angle)) * 18.0, 1.0)
	await measure(["Kampf_36_Gegner", Vector2(-1, 13), 0.0, 0.02])
	for i in 12:
		var angle := i * TAU / 12.0
		game.spawn_zombie("runner", Map.FIRE + Vector2(cos(angle), sin(angle)) * 22.0, 1.0)
	await measure(["Kampf_48_Gegner", Vector2(-1, 13), 0.0, 0.02])
	var report := {
		"engine": Engine.get_version_info().string,
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": str(root.get_visible_rect().size),
		"window_pixels": str(DisplayServer.window_get_size()),
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"render_scale": root.scaling_3d_scale,
		"viewmodel_pixels": str(game.weapons.viewmodel.viewport.size),
		"quality": game.settings.profile,
		"render_stats": game.render_stats,
		"scenes": reports,
	}
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("logs")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("benchmark-quality-%d.json" % game.settings.profile)
	var output := FileAccess.open(path, FileAccess.WRITE)
	if not output:
		push_error("Unable to save benchmark report: " + path)
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t"))
	print("BENCHMARK_DONE ", JSON.stringify(report))
	quit()

func measure(view: Array) -> void:
	game.player.global_position = Map.ground_pos(view[1].x, view[1].y) + Vector3.UP * 0.3
	game.player.velocity = Vector3.ZERO
	game.player.rotation.y = view[2]
	game.player.pitch = view[3]
	game.player.head.rotation.x = view[3]
	await create_timer(2.0).timeout
	samples.clear()
	collecting = true
	await create_timer(5.0).timeout
	collecting = false
	var total := 0.0
	for value in samples:
		total += value
	samples.sort()
	var p99 := samples[mini(samples.size() - 1, ceili(samples.size() * 0.99) - 1)]
	var report := {
		"view": view[0], "frames": samples.size(),
		"average_fps": samples.size() * 1000.0 / total,
		"p99_frame_ms": p99, "p99_fps_equivalent": 1000.0 / p99,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"enemies": game.alive_zombies(),
	}
	reports.append(report)
	print("BENCHMARK_VIEW ", JSON.stringify(report))
	if "--screenshots" in OS.get_cmdline_user_args():
		var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("shots/benchmark")
		DirAccess.make_dir_recursive_absolute(folder)
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(folder.path_join(str(view[0]) + ".png"))
		if result != OK:
			push_error("Unable to save benchmark capture: " + folder)
			quit(1)
