# Fast visual inspection of the shipped Meshy geometry and authored rig.
extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 1100)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.045, 0.055)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.66, 0.75)
	environment.environment.ambient_light_energy = 0.65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.7
	light.shadow_enabled = true
	scene.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 135, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.68, 0.79, 1.0)
	scene.add_child(fill)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = 46
	camera.position = Vector3(0, 10, 31)
	camera.look_at(Vector3(0, 8, 0))
	camera.current = true
	var plane := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60, 60)
	floor_mesh.material = DefenceTower.material(Color(0.11, 0.12, 0.09))
	plane.mesh = floor_mesh
	scene.add_child(plane)
	var animations: Array[AnimationPlayer] = []
	var models: Array[Node3D] = []
	for i in 2:
		var source := "zombie_earthworm" if i == 0 else "zombie_earthworm_ancient"
		var model: Node3D = load("res://assets/models/%s.glb" % source).instantiate()
		scene.add_child(model)
		models.append(model)
		model.scale = Vector3.ONE * (14.0 if i == 0 else 19.0) / 1.7
		model.position = Vector3(-7 if i == 0 else 7, -14.0 * 0.12 if i == 0 else -19.0 * 0.24, 0)
		var animation := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		animation.play("walk")
		animation.seek(0.8, true)
		animation.pause()
		animations.append(animation)
	for frame in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/earthworm-models.png"))
	for animation in animations:
		animation.play("attack")
		animation.seek(2.5, true)
		animation.pause()
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/earthworm-models-attack.png"))
	for animation in animations:
		animation.play("walk")
		animation.seek(0.8, true)
		animation.pause()
	for i in models.size():
		models[1 - i].hide()
		models[i].show()
		var model_height := 14.0 if i == 0 else 19.0
		var focus := models[i].position + Vector3(0, model_height * 0.83, 0.6)
		camera.position = focus + Vector3(3.0, 0.1, 8.5) * model_height / 14.0
		camera.look_at(focus)
		for frame in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/earthworm-closeup-%d.png" % i))
	print("EARTHWORM_GALLERY_DONE")
	quit()
