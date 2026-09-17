extends SceneTree

# Paired, stationary A/B samples: only the sky and distance-fog settings change.
# Run with --smoke-test --atmosphere-benchmark for timings as well as screenshots.
const VIEWS := [
	["wiese_ost", Vector2(70, 52), -PI * 0.5, 0.055],
	["alpen_suedwest", Vector2(95, 88), 2.45, 0.055],
	["waldweg", Vector2(-15, -30), 0.35, 0.02],
]
var game: Node
var world_environment: WorldEnvironment
var alpine: Environment
var baseline: Environment
var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()
var folder: String
var reports: Array = []

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("ATMOSPHERE_TIMEOUT")
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
	if DisplayServer.get_name() == "headless":
		push_error("Atmosphere comparisons require a rendered window.")
		quit(1)
		return
	folder = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/atmosphere")
	DirAccess.make_dir_recursive_absolute(folder)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	# Do not let a visual test award achievements or write the player's progress.
	if game.achievements:
		game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
		game.achievements.hide()
	while not game.navigation_ready:
		await process_frame
	game._flags.append("--no-intro")
	game._on_start()
	game.waves.set_process(false)
	game.day_night.set_process(false)
	game.day_night.set_time_hours(12.0)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.weapons.set_process(false)
	for node in game.get_children():
		if node is WorldEnvironment:
			world_environment = node
	alpine = game.settings.env
	baseline = _baseline(alpine)
	check(alpine.sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL, "Sky radiance uses bounded incremental updates for time of day")
	check(alpine.sky.sky_material is ShaderMaterial, "Alpine panorama is integrated in the existing sky")
	check(AlpineAtmosphere.PANORAMA.get_width() == 4096, "Horizon texture has 4K resolution")
	check(alpine.fog_density > baseline.fog_density and alpine.fog_height_density == baseline.fog_height_density, "More distance haze without extra height-fog work")
	for quality in 3:
		game.settings.profile = quality
		game.settings.apply()
		check(alpine.sky == world_environment.environment.sky and is_equal_approx(alpine.fog_density, 0.0032), "Graphics profile %d retains the Alpine atmosphere" % quality)
		check(alpine.volumetric_fog_enabled == (quality > 0), "Profile %d retains its existing volumetric budget" % quality)
	game.settings.profile = 0
	game.settings.apply()
	baseline.volumetric_fog_enabled = alpine.volumetric_fog_enabled
	baseline.ssao_enabled = alpine.ssao_enabled
	baseline.ssil_enabled = alpine.ssil_enabled
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	# Freeze all gameplay, weather particles and HUD while both variants render.
	paused = true
	game.hud.hide()
	game.weapons.viewmodel.hide()
	game.weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var benchmark := "--atmosphere-benchmark" in OS.get_cmdline_user_args()
	for view in VIEWS:
		game.player.global_position = Map.ground_pos(view[1].x, view[1].y) + Vector3.UP * 0.1
		game.player.rotation.y = view[2]
		game.player.pitch = view[3]
		game.player.head.rotation.x = view[3]
		# Warm both sky radiance maps and shaders before measuring either variant.
		world_environment.environment = baseline
		await create_timer(1.2, true).timeout
		await screenshot(view[0] + "-before")
		world_environment.environment = alpine
		await create_timer(1.2, true).timeout
		await screenshot(view[0] + "-after")
		if benchmark:
			# ABBA order reduces bias from warming, clock drift and concurrent work.
			for variant in ["before", "after", "after", "before"]:
				world_environment.environment = baseline if variant == "before" else alpine
				await create_timer(0.6, true).timeout
				reports.append(await measure(view[0], variant))
	# Check the uncompressed seam and lighting at the remaining cardinal directions.
	world_environment.environment = alpine
	game.player.global_position = Map.ground_pos(115, 50) + Vector3.UP * 0.1
	for i in 4:
		game.player.rotation.y = i * PI * 0.5
		game.player.head.rotation.x = 0.1
		await screenshot("horizon-" + str(i))
	game.settings.profile = 2
	game.settings.apply()
	await create_timer(1.0, true).timeout
	await screenshot("high-quality")
	var result := {"checks": checks, "failures": failures, "gpu": RenderingServer.get_video_adapter_name(), "window": str(root.size), "render_scale": 0.85, "comparison_quality": 0, "samples": reports, "note": "Frozen identical views, ABBA order; concurrent editor/game workloads were left running. Screenshots and warm-up excluded. No absolute 100-FPS guarantee."}
	var file := FileAccess.open(folder.path_join("comparison.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("ATMOSPHERE_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func measure(view_name: String, variant: String) -> Dictionary:
	var frame_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var calls: Array[float] = []
	var primitives: Array[float] = []
	var begin := Time.get_ticks_usec()
	var previous := begin
	while Time.get_ticks_usec() - begin < 2200000:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - previous) / 1000.0)
		previous = now
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var result := {"view": view_name, "variant": variant, "frames": frame_ms.size(), "median_frame_ms": median(frame_ms), "median_gpu_ms": median(gpu_ms), "median_draw_calls": median(calls), "median_primitives": median(primitives)}
	print("ATMOSPHERE_SAMPLE ", JSON.stringify(result))
	return result

func median(values: Array[float]) -> float:
	values.sort()
	return values[values.size() / 2] if not values.is_empty() else 0.0

func screenshot(label: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "Saved " + label)

func _baseline(source: Environment) -> Environment:
	var env: Environment = source.duplicate()
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color(0.55, 0.65, 0.8)
	material.sky_horizon_color = Color(0.95, 0.88, 0.75)
	material.sky_curve = 0.12
	material.ground_bottom_color = Color(0.3, 0.28, 0.22)
	material.ground_horizon_color = Color(0.8, 0.7, 0.55)
	material.sun_angle_max = 30.0
	material.sun_curve = 0.08
	sky.sky_material = material
	env.sky = sky
	env.fog_light_color = Color(0.5, 0.52, 0.5)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.6
	return env
