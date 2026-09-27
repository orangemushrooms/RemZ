extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1600, 900)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.018, 0.025, 0.032)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.7, 0.9)
	environment.environment.ambient_light_energy = 0.6
	environment.environment.glow_enabled = true
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -20, 0)
	sun.light_energy = 0.5
	world.add_child(sun)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(100, 100)
	DefenceTower.piece(world, floor_mesh, Vector3.ZERO, DefenceTower.material(Color(0.12, 0.17, 0.12)))
	for i in 3:
		var drop := Pickup.new()
		drop.item_id = ["cryo_smg", "titanbreaker", "hawk"][i]
		drop.setup("relic" if i == 2 else "weapon")
		world.add_child(drop)
		drop.position = Vector3((i - 1) * 4.0, 0.08, 0)
		drop.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.position = Vector3(8, 5, 12)
	camera.look_at(Vector3(0, 3.0, 0))
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/titan-loot-beacons.png"))
	camera.position = Vector3(6, 2.4, 6)
	camera.look_at(Vector3(0, 0.6, 0))
	sun.light_energy = 1.8
	environment.environment.ambient_light_energy = 0.85
	environment.environment.background_color = Color(0.25, 0.34, 0.42)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/titan-loot-beacons-near.png"))
	print("LOOT_BEACON_VISUAL_DONE")
	quit()
