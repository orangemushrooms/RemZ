# Frame-rate cost of a big horde: 60 common zombies in front of the player, sampled with everything on, with
# zombie shadows off, with the animations paused and with the simulation (navigation, avoidance, movement)
# running. Prints HORDE_BENCH lines. Run:
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=horde_bench --no-intro
extends SceneTree

var game: Node
var began := Time.get_ticks_msec()
var frames := 0

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	frames += 1
	if Time.get_ticks_msec() - began > 240000:
		print("HORDE_BENCH timeout")
		quit(1)
	return false

func sample(label: String) -> float:
	for i in 20: await process_frame
	frames = 0
	var t0 := Time.get_ticks_msec()
	await create_timer(2.5).timeout
	var fps := frames * 1000.0 / maxf(1.0, Time.get_ticks_msec() - t0)
	print("HORDE_BENCH %-28s %.1f FPS" % [label, fps])
	return fps

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	if "achievements" in game and game.achievements: game.achievements.hide()
	if "day_night" in game and game.day_night:
		game.day_night.clock_seconds = 17 * 3600 + 40 * 60
		game.day_night.advance(1)
		game.day_night.set_process(false)
	game.hud.message("", 0.0)
	game.player.global_position = Map.ground_pos(8, 40) + Vector3(0, 0.2, 0)
	game.player.camera.look_at(Map.ground_pos(8, 62) + Vector3.UP * 1.0)
	await sample("empty meadow")
	var zombies: Array = []
	for i in 60:
		game.spawn_zombie(["shambler", "shambler", "runner", "soldier"][i % 4], Vector2(-2 + (i % 10) * 2.2, 52 + (i / 10) * 2.5), 1, "east")
		var z: Zombie = game.zombies_root.get_children().back()
		z.set_physics_process(false)
		z.agent.avoidance_enabled = false
		z.rotation.y = PI
		zombies.append(z)
	await sample("60 zombies, frozen")
	for z in zombies:
		for m in z.model.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await sample("60 zombies, no shadows")
	for z in zombies:
		if z.anim: z.anim.pause()
	await sample("60 zombies, anims paused")
	for z in zombies:
		if z.anim: z.anim.play()
		z.set_physics_process(true)
		z.agent.avoidance_enabled = true
	await sample("60 zombies, simulated")
	print("HORDE_BENCH_DONE")
	quit(0)
