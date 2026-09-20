extends SceneTree

var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: quit(1)
	return false

func capture(name: String) -> void:
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/titan-horror/" + name + ".png"))

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.hide()
	game.player.global_position = Map.ground_pos(13, 64)
	game.day_night.clock_seconds = 19.5 * 3600
	game.day_night.advance(1)
	game.day_night.set_process(false)
	game.spawn_zombie("titan", Vector2(13, 106), 1, "east")
	var titan: Titan = game.zombies_root.get_children().back()
	titan.set_physics_process(false)
	titan.agent.avoidance_enabled = false
	game.player.camera.look_at(titan.global_position + Vector3.UP * titan.height * 0.48)
	await capture("titan-dusk")
	game._pause()
	game.hud.show_tab("settings")
	await capture("settings-1280")
	print("TITAN_VISUAL_DONE 2")
	quit()
