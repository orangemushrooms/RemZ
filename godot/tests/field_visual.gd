extends SceneTree

var game: Node3D
var frames: Array[float] = []
var collecting := false
var previous := 0
var began := Time.get_ticks_msec()
var reports: Array = []
var spikes: Array = []
var sample_seconds := 12.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--field-seconds="): sample_seconds = clampf(float(arg.get_slice("=", 1)), 5, 40)
	call_deferred("run")
func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if collecting and previous > 0:
		var ms := (now - previous) / 1000.0
		frames.append(ms)
		if ms > 35:
			var sample := {"ms": ms, "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000, "physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, "navigation_ms": Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000, "pipelines": Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), "at": Time.get_ticks_msec()}
			spikes.append(sample)
			print("FIELD_SPIKE ", JSON.stringify(sample))
	previous = now
	if Time.get_ticks_msec() - began > 240000: quit(1)
	return false
func capture(id: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/field-%s.png" % id))
func measure(id: String) -> void:
	await create_timer(3).timeout
	frames.clear()
	spikes.clear()
	collecting = true
	await create_timer(sample_seconds).timeout
	collecting = false
	var total := 0.0
	for ms in frames: total += ms
	frames.sort()
	var report := {"scene": id, "fps": frames.size() * 1000 / total, "p95_ms": frames[int(frames.size() * 0.95)], "p99_ms": frames[int(frames.size() * 0.99)], "max_ms": frames.back(), "bosses": game.alive_zombies(), "spikes": spikes.duplicate()}
	reports.append(report)
	print("FIELD_PERF ", JSON.stringify(report))
	await capture(id)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	seed(270926)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.max_hp = 1000000
	game.player.hp = 1000000
	Engine.max_fps = 0
	game.day_night.set_time_hours(17)
	game.player.global_position = Map.ground_pos(20, 112) + Vector3.UP * 0.3
	game.player.camera.look_at(Map.ground_pos(15, 83) + Vector3.UP)
	await capture("flowers")
	game.waves.wave = 19
	game.waves.completed = 19
	game.field_trials.begin(20)
	game.field_trials.countdown = 0
	while not game.field_trials.pending.is_empty(): await process_frame
	game.player.camera.look_at(Map.ground_pos(-45, 105) + Vector3.UP * 10)
	await measure("seven-bosses")
	for z in game.field_trials.enemies:
		if z is Titan:
			z.hp = z.max_hp * 0.34
			z.damage(1, Vector3.ZERO)
	await measure("crawling-bosses")
	# Inspect the complete grounded attack from a side camera with its real terrain contact.
	var titan: Titan = game.field_trials.enemies[1]
	for z in game.field_trials.enemies:
		z.set_physics_process(false)
		if z != titan: z.hide()
	titan.play("attack")
	for phase in [0.0, 0.68, 1.0]:
		titan.anim.seek(phase, true)
		titan.anim.pause()
		game.player.camera.global_position = titan.global_position + titan.global_basis * Vector3(-26, 10, 8)
		game.player.camera.look_at(titan.global_position + Vector3.UP * 6.0)
		await capture("crawl-attack-%d" % int(phase * 100))
	var report := {"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(), "resolution": str(root.size), "profile": game.settings.profile, "scale": root.scaling_3d_scale, "scenes": reports}
	FileAccess.open("res://../artifacts/field-performance.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FIELD_VISUAL_DONE")
	quit()
