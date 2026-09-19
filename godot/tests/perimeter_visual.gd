# Screenshots of the palisade ring: the east gate from outside with a built barricade, the north gate from
# the plaza, the west wall from inside and the Wiesentor from the fork -> shots/perimeter_*.png. Run:
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=perimeter_visual --no-intro
extends SceneTree

var game: Node
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 180000:
		print("PERIMETER_VISUAL timeout")
		quit(1)
	return false

func capture(file: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../shots/" + file + ".png"))
	print("PERIMETER_SHOT ", file)

func view(point: Vector2, target: Vector3) -> void:
	game.player.global_position = Map.ground_pos(point.x, point.y) + Vector3(0, 0.2, 0)
	game.player.camera.look_at(target)

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
		game.day_night.clock_seconds = 17 * 3600 + 30 * 60
		game.day_night.advance(1)
		game.day_night.set_process(false)
	game.hud.message("", 0.0)
	for bar in game.barricades:
		bar.build()
	var ring: Perimeter = game.perimeter
	print("PERIMETER_INFO wall=%.0f m logs=%d gates=%d" % [ring.length, ring.log_count, ring.gate_edge.count(true)])
	for i in 4:
		game.spawn_zombie("shambler", Vector2(38 + i * 1.4, 56 + i * 0.6), 1.0, "north")
		var z: Zombie = game.zombies_root.get_children().back()
		z.set_physics_process(false)
		z.agent.avoidance_enabled = false
		z.rotation.y = PI * 0.5
	await create_timer(1.5).timeout
	view(Vector2(44, 51), Map.ground_pos(28, 55) + Vector3.UP * 1.4)
	await capture("perimeter_gate_east")
	view(Vector2(-3, -14), Map.ground_pos(-15, -30) + Vector3.UP * 1.6)
	await capture("perimeter_north_gate")
	view(Vector2(-20, 14), Map.ground_pos(-30, 38) + Vector3.UP * 1.6)
	await capture("perimeter_west_wall")
	view(Vector2(6, 56), Map.ground_pos(7.5, 66) + Vector3.UP * 1.4)
	await capture("perimeter_wiesentor")
	print("PERIMETER_VISUAL_DONE")
	quit(0)
