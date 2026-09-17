extends SceneTree

var game: Node
var started_at := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 120000:
		quit(1)
	return false

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1920, 1080)
	root.position = Vector2i.ZERO
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready:
		await process_frame
	await shot("menu")
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.player.global_position = Map.ground_pos(-1, 13) + Vector3.UP * 0.3
	game.player.rotation.y = 0.0
	game.player.pitch = -0.07
	game.player.head.rotation.x = -0.07
	for id in Weapons.ORDER:
		game.weapons.unlock(id)
		game.weapons.set_weapon(id)
		await create_timer(0.2).timeout
		print("WEAPON_BOUNDS ", id, " ", game.weapons.cur().bounds, " GRIP ", game.weapons.cur().hands.trigger_grip)
		await shot(id)
		Input.action_press("aim")
		await create_timer(0.5).timeout
		await shot(id + "-ads")
		Input.action_release("aim")
	game.weapons.cur().ammo = 1
	game.weapons.reload()
	await create_timer(0.6).timeout
	await shot("reload")
	game._pause()
	await shot("pause")
	print("VISUAL_DONE")
	quit()

func shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/viewmodel")
	DirAccess.make_dir_recursive_absolute(folder)
	var result := root.get_texture().get_image().save_png(folder.path_join(name + ".png"))
	if result != OK:
		push_error("Unable to save visual capture: " + folder)
		quit(1)
