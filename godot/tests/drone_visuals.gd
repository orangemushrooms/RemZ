extends SceneTree
var game: Node
func _initialize() -> void: call_deferred("run")
func capture(file: String, settle_seconds := 0.5) -> void:
	game.hud.msg_label.text = ""
	if settle_seconds > 0: await create_timer(settle_seconds).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../logs/drone-"+file+".png"))
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	game.day_night.set_time_hours(12)
	game.day_night.set_process(false)
	game.drones.set_process(false)
	game.defences.set_process(false)
	Lang.current = "de"
	TranslationServer.set_locale("de")
	game.forest_keys.owned.waldhuette = true
	game.waves.wave = 15
	game.weapons.viewmodel.hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	var s: DroneSystem = game.drones
	camera.global_position = s.station.to_global(Vector3(0,1.5,2.3))
	camera.look_at(s.station.to_global(Vector3(0,1.0,0)))
	camera.make_current()
	await capture("station")
	game.player.global_position = s.station.to_global(Vector3(0,0,1.5))
	game.player.rotation.y = s.station.rotation.y
	s.open()
	await capture("menu")
	s.close()
	for kind in AttackDrone.SPECS:
		var drone: AttackDrone = s.create_drone(s.next_id,kind,game.player.peer_id,Map.ground_pos(60,112)+Vector3.UP*2)
		s.next_id += 1
		drone.set_physics_process(false)
		camera.global_position = drone.global_position+Vector3(1.7,1.2,-2.6)
		camera.look_at(drone.global_position)
		camera.make_current()
		await capture("detail-"+kind)
		game.player.controlling_drone = drone.drone_id
		s._sync_view()
		s._process(0.01)
		drone.cooldown = 0
		drone.shoot()
		await capture("flight-"+kind)
		drone.cooldown = 0
		drone.shoot()
		await capture("firing-"+kind,0)
		s.finish(drone.drone_id,false)
	print("DRONE_VISUALS_DONE")
	quit()
