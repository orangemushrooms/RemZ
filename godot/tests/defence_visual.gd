extends SceneTree

var game: Node
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: quit(1)
	return false

func capture(file: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/defence/" + file + ".png"))

func view(point: Vector2, target: Vector3) -> void:
	game.player.global_position = Map.ground_pos(point.x, point.y)
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
	game.achievements.hide()
	game.day_night.clock_seconds = 15 * 3600
	game.day_night.advance(1)
	game.day_night.set_process(false)
	game.player.score = 750
	var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(14, 63), 1)
	game.barricades[1].build()
	game.spawn_zombie("titan", Vector2(13, 93), 1, "east")
	var titan: Titan = game.zombies_root.get_children().back()
	titan.set_physics_process(false)
	titan.agent.avoidance_enabled = false
	titan.rotation.y = PI
	game.hud.message("", 0.0)
	for i in 5:
		game.spawn_zombie("shambler", Vector2(4 + i * 1.8, 72 + i * 1.4), 1, "east")
		var zombie: Zombie = game.zombies_root.get_children().back()
		zombie.set_physics_process(false)
		zombie.agent.avoidance_enabled = false
		zombie.rotation.y = PI
	view(Vector2(8, 52), titan.global_position + Vector3.UP * 4)
	await create_timer(1.0).timeout
	await capture("01-defended-entrance")
	view(Vector2(18, 69), tower.global_position + Vector3.UP * 2)
	await capture("02-tower")
	game.player.global_position = tower.global_position + Vector3(3, 0, 0)
	game.defences.open(tower)
	await capture("03-tower-menu")
	game.defences.close()
	view(Vector2(15, 67), Map.ground_pos(18, 73))
	game.defences.placing = true
	game.hud.set_prompt("")
	await capture("04-placement")
	game.defences.cancel_placement()
	view(Vector2(13, 64), titan.global_position + Vector3.UP * titan.height * 0.48)
	titan.begin_strike(Map.ground_pos(13, 88))
	titan.anim.seek(0.4, true)
	await capture("05-titan")
	root.size = Vector2i(1280, 720)
	game.defences.open(tower)
	await capture("06-menu-1280")
	print("DEFENCE_VISUAL_DONE 6")
	quit()
