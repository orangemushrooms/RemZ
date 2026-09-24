extends SceneTree
var game: Node
func _initialize() -> void: call_deferred("run")
func capture(file: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../logs/roof-" + file + ".png"))
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.day_night.set_time_hours(12)
	game.day_night.set_process(false)
	game.defences.set_process(false)
	game.weapons.viewmodel.hide()
	game.player.score = 10000
	game.waves.completed = 8
	for i in 5:
		var t: DefenceTower = game.defences.create_tower(game.defences.roof_position(i),1,0,false,DefenceTower.TYPES[i])
		t.rotation.y = float(Map.BUILDINGS.waldhuette.yaw) + (PI if i >= 3 else 0.0)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.global_position = game.hut.center + Vector3(-11,13,-14)
	camera.look_at(game.hut.center + Vector3.UP * 4)
	camera.current = true
	await capture("gallery")
	game.player.global_position = game.hut.center + Vector3(-5,0,0)
	game.defences.begin_building()
	game.defences._process(0.01)
	await capture("menu")
	Lang.current = "de"
	TranslationServer.set_locale("de")
	game.defences.site_picker.select(6)
	game.defences.site_picker.item_selected.emit(6)
	game.waves.completed = 0
	game.defences._process(0.01)
	await capture("menu-locked")
	print("ROOF_VISUALS_DONE")
	quit()
