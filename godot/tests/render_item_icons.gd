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
	# Only the weapons that have no icon yet. A full run would re-render every existing icon,
	# mushrooms and fireworks included, and overwrite artwork nobody asked to change.
	if "--weapons-only" in OS.get_cmdline_user_args():
		catalogue = {}
		for id in Weapons.ORDER:
			# Constants only: run with --script there are no autoloads, so touching a Weapons
			# function would drag NetSession into the compile and fail the whole run.
			if Weapons.DEFS[id].get("melee", false): continue
			if ResourceLoader.exists("res://assets/ui/items/%s.png" % id) and "--force" not in OS.get_cmdline_user_args(): continue
			catalogue[id] = Weapons.DEFS[id].model
	if "--missing-only" not in OS.get_cmdline_user_args() and "--weapons-only" not in OS.get_cmdline_user_args():
		catalogue.firework_rocket = "firework_rocket"
		catalogue.firework_cracker = "firework_cracker"
	if "--batteries-only" in OS.get_cmdline_user_args(): catalogue = {"firework_battery_40": "firework_battery_40", "firework_battery_90": "firework_battery_90"}
	if "--gold-mushroom-only" in OS.get_cmdline_user_args(): catalogue = {"goldroehrling": ""}
	# "--only=a,b": just those ids (their models come from the full catalogue above)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			var only := {}
			for id in arg.get_slice("=", 1).split(","):
				if catalogue.has(id): only[id] = catalogue[id]
			catalogue = only
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
		elif id == "goldroehrling":
			object = Inventory.Mushrooms.model(id)
			holder.add_child(object)
		else:
			# A missing GLB must not take the whole run down with it.
			var model_path := "res://assets/models/%s.glb" % catalogue[id]
			if not ResourceLoader.exists(model_path):
				if Inventory.Mushrooms.DEFS.has(id):
					object = Inventory.Mushrooms.model(id)   # procedural stand-in, like in the world
				else:
					push_warning("icon: missing model " + model_path)
					holder.queue_free()
					continue
			else:
				object = load(model_path).instantiate()
			holder.add_child(object)
		var bounds := Barricade._bounds(object)
		var scale_factor := 2.0 / maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)
		object.scale *= scale_factor
		object.position = -bounds.get_center() * scale_factor
		if id in ["firework_rocket", "firework_cracker"]: holder.rotation.z = -0.6
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
