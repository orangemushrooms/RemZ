extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(960, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.19, 0.22, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.75
	world.environment = env
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -40, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.near = 0.01
	stage.add_child(camera)
	var label := Label.new()
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 28)
	root.add_child(label)
	var folder := ProjectSettings.globalize_path("res://../artifacts/grips/")
	DirAccess.make_dir_recursive_absolute(folder)
	for id in Weapons.ORDER:
		if Weapons.is_melee(id): continue
		var holder := Node3D.new()
		stage.add_child(holder)
		var model: Node3D = load("res://assets/models/%s.glb" % Weapons.DEFS[id].model).instantiate()
		holder.add_child(model)
		Weapons._fit_height(model, Weapons.DEFS[id].height)
		model.rotation.y = -PI / 2
		var bounds := ViewmodelHands.weapon_bounds(holder)
		var hands := ViewmodelHands.build(id, bounds)
		holder.add_child(hands)
		var glove: Node3D = hands.get_node("TriggerHand/Glove")
		var skeleton: Skeleton3D = glove.find_child("Skeleton3D", true, false)
		var target: Vector3 = hands.get_node("TriggerHand").get_meta("trigger_target")
		print("INDEX ", id, " target=", target, " tip=", glove.transform * skeleton.get_bone_global_pose(skeleton.find_bone("finger_index_r_end")).origin)
		print("GRIP ",id," bounds=",bounds," trigger=",hands.trigger_grip," support=",hands.support_grip)
		for view in ["side", "hip", "ads"]:
			label.text = id + " / " + view
			holder.position = Vector3.ZERO
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 70
			camera.position = Vector3.ZERO
			camera.rotation = Vector3.ZERO
			if view == "side":
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = maxf(bounds.size.z + 0.2, 0.65)
				camera.position = Vector3(1, 0.06, 0)
				camera.look_at(Vector3(0, -0.04, 0))
			elif view == "hip": holder.position = Weapons.DEFS[id].pos
			else:
				holder.position = Weapons.DEFS[id].ads
				holder.position.y = -bounds.end.y - 0.008
				holder.position.z = minf(holder.position.z, -bounds.end.z - 0.18)
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + id + "-" + view + ".png")
		holder.free()
	print("GRIP_GALLERY_DONE")
	quit()
