extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../logs/tower-"+name+".png"))

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	game.day_night.set_time_hours(12)
	game.day_night.set_process(false)
	game.player.add_score(10000)
	for i in DefenceTower.TYPES.size():
		var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(45+i*5,112),1,0,false,DefenceTower.TYPES[i])
		tower.rotation.y = PI
	game.player.global_position = Map.ground_pos(55,129)+Vector3.UP*4
	game.player.camera.look_at(Map.ground_pos(55,112)+Vector3.UP*2.7)
	game.weapons.viewmodel.hide()
	game.defences.set_process(false)
	await capture("gallery")
	game.defences.begin_building()
	await capture("menu")
	game.defences.close()
	game.player.camera.rotation = Vector3.ZERO
	for tower: DefenceTower in game.defences.towers.values():
		game.player.global_position = tower.global_position+Vector3(0,0,3)
		game.defences.mount(game.player,tower.tower_id)
		game.defences.set_process(true)
		await capture("mounted-"+tower.kind)
		game.defences.release_tower(tower)
		game.defences.set_process(false)
		game.player.global_position = tower.global_position+Vector3(3,1.0,-4)
		game.player.camera.look_at(tower.global_position+Vector3.UP*3.2)
		await capture("detail-"+tower.kind)
		game.player.camera.rotation = Vector3.ZERO
	print("TOWER_VISUALS_DONE")
	quit()
