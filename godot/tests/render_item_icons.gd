extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var directory := ProjectSettings.globalize_path("res://assets/ui/items/")
	DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 200)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	for rotation in [Vector3(-35, -25, 0), Vector3(-15, 140, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = rotation
		light.light_energy = 1.3
		world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	camera.current = true
	var catalogue := {"ammo": "ammo_pack", "medicine": "medkit", "grenade": "grenade", "steinpilz": "mushroom_cluster", "fliegenpilz": "mushroom_fly", "barricade": "barricade", "tower": ""}
	for id in Weapons.ORDER: catalogue[id] = Weapons.DEFS[id].model
	for id in Inventory.Mushrooms.DEFS:
		if not catalogue.has(id): catalogue[id] = "mushroom_" + id
	if "--missing-only" in OS.get_cmdline_user_args():
		catalogue = {"tower": "", "cash": "cash_bundle", "key": "forest_key"}
		for id in Inventory.Mushrooms.DEFS:
			if id not in ["steinpilz", "fliegenpilz"]: catalogue[id] = "mushroom_" + id
	if "--fireworks-only" in OS.get_cmdline_user_args(): catalogue = {}
	if "--missing-only" not in OS.get_cmdline_user_args():
		catalogue.firework_rocket = "firework_rocket"
		catalogue.firework_cracker = "firework_cracker"
	for id in catalogue:
		var holder := Node3D.new()
		world.add_child(holder)
		var object: Node3D
		if id == "tower":
			var tower := DefenceTower.new()
			tower.replica = true
			tower.process_mode = Node.PROCESS_MODE_DISABLED
			holder.add_child(tower)
			tower.label.hide()
			object = tower
		else:
			object = load("res://assets/models/%s.glb" % catalogue[id]).instantiate()
			holder.add_child(object)
		var bounds := Barricade._bounds(object)
		var scale_factor := 2.0 / maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)
		object.scale *= scale_factor
		object.position = -bounds.get_center() * scale_factor
		if id.begins_with("firework_"): holder.rotation.z = -0.6
		camera.position = Vector3(0.4, 0.3, 5) if id in Weapons.ORDER else Vector3(3, 2, 5)
		camera.look_at(Vector3.ZERO)
		camera.size = 2.5
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var cropped := image.get_region(image.get_used_rect())
		var fit := minf(288.0 / cropped.get_width(), 168.0 / cropped.get_height())
		cropped.resize(maxi(1, roundi(cropped.get_width() * fit)), maxi(1, roundi(cropped.get_height() * fit)), Image.INTERPOLATE_LANCZOS)
		var output := Image.create(320, 200, false, Image.FORMAT_RGBA8)
		output.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), (output.get_size() - cropped.get_size()) / 2)
		var error := output.save_png(directory + str(id) + ".png")
		if error != OK:
			quit(1)
			return
		print("ITEM_ICON ", id)
		holder.free()
	print("ITEM_ICONS_DONE")
	quit()
