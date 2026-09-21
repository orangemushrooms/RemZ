extends SceneTree

var game: Node

func _initialize() -> void: call_deferred("run")

func capture(id: String) -> void:
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/model-audit/world-" + id + ".png"))

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	game.day_night.set_process(false)
	game.day_night.set_time_hours(12)
	game.weapons.viewmodel.hide()
	game.hud.hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.make_current()
	var key: ForestKey = game.forest_keys.spawned[0]
	camera.position = key.global_position + Vector3(0.7, 1.1, 0.8)
	camera.look_at(key.interaction_point())
	game.player.global_position = camera.position
	await capture("key")
	var trough: Node3D = game.get_node("ForestPondTrough")
	camera.position = trough.to_global(Vector3(3, 2, 3))
	camera.look_at(trough.to_global(Vector3(0, 0.7, 0)))
	game.player.global_position = camera.position
	await capture("pond")
	var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(50, 112), 1, 0, false, "standard")
	camera.position = tower.global_position + Vector3(3, 4, -4)
	camera.look_at(tower.global_position + Vector3.UP * 2.6)
	game.player.global_position = camera.position
	await capture("standard")
	game.player.global_position = tower.global_position + Vector3(0, 0, 3)
	game.defences.mount(game.player, tower.tower_id)
	game.player.camera.make_current()
	game.player.camera.rotation = Vector3.ZERO
	await capture("standard-operated")
	game.defences.release_tower(tower)
	tower.label.hide()
	game.weapons.viewmodel.hide()
	for layer: CanvasLayer in game.find_children("*", "CanvasLayer", true, false): layer.hide()
	camera.make_current()
	var owl = load("res://scripts/field_bird.gd").new()
	owl.owl = true
	owl.process_mode = Node.PROCESS_MODE_DISABLED
	game.add_child(owl)
	owl.visible = true
	owl.position = Map.ground_pos(48, 112) + Vector3.UP * 3.5
	owl.flap_power = 1.0
	for phase in [0.25, 0.75]:
		owl.flap_phase = phase
		owl._advance_flap(0.0)
		owl._pose_raven()
		camera.position = owl.position + Vector3(0.7, 0.7, -1.4)
		camera.look_at(owl.position + Vector3.UP * 0.3)
		game.player.global_position = camera.position
		await capture("owl-" + str(phase))
	print("MISSING_WORLD_VISUALS_DONE")
	quit()
