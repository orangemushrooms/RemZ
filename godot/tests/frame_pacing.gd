# Rendered event/soak benchmark: include first-use frames, not just warmed averages.
# --suite=frame_pacing --smoke-test --no-intro --no-music --pacing-report=before
extends SceneTree

var game: Node3D
var reports: Array = []
var samples: Array[float] = []
var collecting := false
var previous := 0
var firing := false
var began := Time.get_ticks_msec()
var report_name := "current"
var action_ms := 0.0
var death_score_us := 0

func _initialize() -> void: call_deferred("run")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if collecting and previous > 0: samples.append((now - previous) / 1000.0)
	previous = now
	if firing:
		game.weapons.cur().ammo = 1000
		game.weapons.try_fire()
	if Time.get_ticks_msec() - began > 300000:
		push_error("FRAME_PACING_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	seed(4242)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pacing-report="): report_name = arg.get_slice("=", 1).validate_filename()
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
	game.player.max_hp = 1000000
	game.player.hp = 1000000
	game.player.score = 1000000
	game.hut.hp = 1000000
	game.player.global_position = Map.ground_pos(0, 85) + Vector3.UP * 0.2
	game.player.camera.look_at(Map.ground_pos(0, 110) + Vector3.UP)
	await create_timer(2.0).timeout
	await measure("first_surface_steps", 2.0, func():
		for surface in ["grass", "leaves", "gravel", "wood", "corn"]:
			Sfx.footstep(game.player, surface, -40.0))
	await measure("first_bullet_mark", 2.0, func():
		var point := Map.ground_pos(0, 88)
		preload("res://scripts/bullet_impacts.gd").show(game, point, Vector3.UP))
	for i in 72:
		game.spawn_zombie(["shambler", "runner", "soldier", "nurse", "brute"][i % 5], Vector2(-28 + (i % 20) * 3, 108 + (i / 20) * 3), 1.0)
		await process_frame
	for z in game.zombies_root.get_children(): z.hp = 1000000.0
	await measure("moving_horde_72", 5.0)
	for i in 5:
		await measure("first_tower_" + DefenceTower.TYPES[i], 2.0, func():
			var tower = game.defences.create_tower(Map.ground_pos(-13 + i * 5, 94), 1, 0, false, DefenceTower.TYPES[i])
			tower.rotation.y = PI
			tower.hp = 1000000.0)
	game.weapons.unlock("lmg")
	game.weapons.set_weapon("lmg")
	firing = true
	await measure("combat_72_five_towers", 12.0)
	for mode in ["fire", "frost"]:
		await measure("first_" + mode, 6.0, func():
			var data: Dictionary = game.progression.rare_market.data(1)
			data.ammo[mode] = 10000
			data.mode = mode
			for z in game.zombies_root.get_children().slice(0, 12):
				game.progression.rare_market.hit(z, mode, 1, "lmg"))
	firing = false
	await measure("build_perimeter_in_combat", 8.0, func():
		for bar in game.barricades:
			bar.level = 1
			bar.hp = bar.max_hp()
			bar.rebuild())
	await measure("destroy_perimeter_in_combat", 8.0, func():
		for bar in game.barricades: bar.damage(1000000.0))
	await measure("mass_deaths", 3.0, func():
		for z in game.zombies_root.get_children():
			if z is Zombie and z.alive:
				z._on_kill = _profile_score
				z.die(Vector3.ZERO))
	await measure("corpse_cleanup", 3.0, func(): game.waves.trim_corpses())
	if "--pacing-extended" in OS.get_cmdline_user_args(): await extended()
	save_report(true)
	print("FRAME_PACING_DONE stages=", reports.size())
	quit(0)

func extended() -> void:
	for id: String in Weapons.DEFS:
		await measure("weapon_" + id, 1.5, func():
			game.weapons.unlock(id)
			game.weapons.set_weapon(id)
			game.weapons.cur().cooldown = 0
			game.weapons.try_fire())
	game.weapons.set_weapon("lmg")
	await measure("first_grenade", 5.0, func():
		game.weapons.grenades = 3
		game.weapons.throw_grenade())
	await measure("first_titan", 4.0, func(): game.spawn_zombie("titan", Vector2(0, 120), 1.0))
	for zombie in game.zombies_root.get_children():
		if zombie is Titan:
			await measure("titan_strike", 4.0, func(): zombie.begin_strike(game.player.global_position))
			zombie.die(Vector3.ZERO)
	for id in ["fw_ruby", "fw_gold", "fw_cracker"]:
		await measure("first_" + id, 5.0, func():
			var effect = Fireworks.make_effect(id)
			effect.configure(id, game.player.global_position + Vector3(0, 0, 8), game.player.global_position + Vector3(0, 0, 12), 17, 0.0)
			game.add_child(effect))
	for view in [["clearing", Vector2(-1, 13), 0.0], ["hut", Vector2(-15, -7), -PI / 2.0 - 0.35],
		["junction", Vector2(7, 58), 0.0], ["forest_road", Vector2(96, 33), PI / 2.0 + 0.25], ["sennhof", Vector2(122, -20), PI]]:
		await measure("view_" + view[0], 5.0, func():
			game.player.global_position = Map.ground_pos(view[1].x, view[1].y) + Vector3.UP * 0.3
			game.player.rotation.y = view[2]
			game.player.head.rotation.x = 0.0)

func _profile_score(zombie: Zombie) -> void:
	var start := Time.get_ticks_usec()
	game._zombie_killed(zombie)
	death_score_us += Time.get_ticks_usec() - start

func measure(label: String, seconds: float, action := Callable()) -> void:
	await process_frame
	samples.clear()
	previous = Time.get_ticks_usec()
	collecting = true
	var start := Time.get_ticks_usec()
	if action.is_valid(): action.call()
	action_ms = (Time.get_ticks_usec() - start) / 1000.0
	await create_timer(seconds).timeout
	collecting = false
	var total := 0.0
	var over_33 := 0
	var over_50 := 0
	for value in samples:
		total += value
		if value > 1000.0 / 30.0: over_33 += 1
		if value > 50.0: over_50 += 1
	samples.sort()
	var report := {"stage": label, "frames": samples.size(), "average_fps": samples.size() * 1000.0 / total,
		"p95_ms": samples[int(samples.size() * 0.95)], "p99_ms": samples[int(samples.size() * 0.99)], "max_ms": samples.back(),
		"over_33ms": over_33, "over_50ms": over_50, "action_ms": action_ms, "alive": game.alive_zombies(), "nodes": get_node_count()}
	if label == "mass_deaths": report.score_cpu_ms = death_score_us / 1000.0
	reports.append(report)
	save_report()
	print("FRAME_PACING_STAGE ", JSON.stringify(report))

func save_report(complete := false) -> void:
	var report := {"complete": complete, "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"rendered": DisplayServer.get_name() != "headless", "profile": game.settings.profile,
		"resolution": str(root.size), "scale": root.scaling_3d_scale,
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, "stages": reports}
	var output := FileAccess.open("res://../logs/frame-pacing-%s.json" % report_name, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
