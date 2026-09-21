extends SceneTree

const Assets = preload("res://tests/missing_models.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var directory := ProjectSettings.globalize_path("res://../artifacts/model-audit/")
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.055, 0.065, 0.08)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	environment.environment.ambient_light_energy = 0.7
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	for rotation in [Vector3(-35, -25, 0), Vector3(-15, 140, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = rotation
		light.light_energy = 1.6
		world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.65
	world.add_child(camera)
	camera.make_current()
	var names: Array = Assets.NEW_MODELS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="): names = Array(arg.trim_prefix("--models=").split(","))
	for id in names:
		var model := WorldModels.create(id)
		if not model:
			push_error("Missing model for rendering: " + id)
			quit(1)
			return
		world.add_child(model)
		var bounds := Barricade._bounds(model)
		var factor := 2.0 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		model.scale *= factor
		model.position = -bounds.get_center() * factor
		camera.position = Vector3(1.2, 0.8, -4) if id == "owl_real" else Vector3(3, 2, 5)
		if id == "tower_standard": camera.position = Vector3(4, 1.5, -2)
		camera.look_at(Vector3.ZERO)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(directory + id + ".png")
		model.free()
	print("MISSING_VISUALS_DONE")
	quit()
