extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.11, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5, 4.5, 7)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.current = true
	var ground := PlaneMesh.new()
	ground.size = Vector2(35, 35)
	DefenceTower.piece(world, ground, Vector3.ZERO, DefenceTower.material(Color(0.21, 0.23, 0.19)))
	var models: Array[Node3D] = []
	var animations: Array[AnimationPlayer] = []
	for id in ["deer", "stag", "zombie_stag"]:
		var model: Node3D = load("res://assets/models/%s_animated.glb" % id).instantiate()
		world.add_child(model)
		Weapons._fit_height(model, 1.9)
		model.position = Vector3((models.size() - 1) * 2.6, 0.95, 0)
		model.rotation.y = -PI * 0.5
		models.append(model)
		var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		animations.append(anim)
		var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
		if not anim or not rig or rig.get_bone_count() != 15:
			push_error("Invalid quadruped rig")
			quit(1)
			return
	for clip in ["idle", "walk", "run", "graze"]:
		for phase in [0.0, 0.25, 0.5, 0.75]:
			for anim in animations:
				anim.play(clip, 0)
				anim.seek(anim.get_animation(clip).length * phase, true)
				anim.pause()
			for frame in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/quadruped-%s-%d.png" % [clip, int(phase * 100)]))
	print("QUADRUPED_VISUAL_DONE")
	quit()
