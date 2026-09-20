extends SceneTree

var game: Node
var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()
var folder := ProjectSettings.globalize_path("res://../artifacts/campsite-pickups/")

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("CAMPSITE_PICKUPS_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func frames(count: int = 3) -> void:
	for i in count:
		await physics_frame
		await process_frame

func shot(name: String) -> void:
	if "--render-campsite" not in OS.get_cmdline_user_args():
		return
	game.hud.msg_label.text = ""
	game.hud._msg_timer = 0.0
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + name + ".png")

func view(at: Vector2, target: Vector2, lift: float = 1.0) -> void:
	game.player.global_position = Map.ground_pos(at.x, at.y) + Vector3.UP * 0.15
	game.player.camera.look_at(Map.ground_pos(target.x, target.y) + Vector3.UP * lift)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	if game.achievements:
		game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
		game.achievements.hide()
		game.achievements = null
	while not game.navigation_ready:
		await process_frame
	game._flags.append("--no-intro")
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.day_night.set_process(false)
	game.day_night.set_time_hours(10.0)
	if "--render-campsite" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	await frames()
	print("CAMPSITE_COVER ", Map.cover(Map.FIRE.x, Map.FIRE.y), " fountain=", game.get_node("CabinFountain").global_position)
	view(Vector2(-7, -15), Vector2(6, -1), 1.0)
	await shot("01-fire-clearing")
	view(Vector2(7, -3), Vector2(-5, -12), 0.6)
	await shot("02-forest-floor")
	var fountain := Vector2(Map.FOUNTAIN.x, Map.FOUNTAIN.y)
	view(fountain + Vector2(-4, 5), (fountain + Map.FIRE) * 0.5, 0.8)
	await shot("03-fountain-beside-cabin")
	view(fountain + Vector2(-2.3, 1.7), fountain, 0.7)
	await shot("04-fountain-close")
	# Regression: shared imported pickup meshes must remain owned by their Loot node.
	var selected := {}
	var mushrooms := 0
	var owned_visuals := 0
	for loot in game.loots:
		if loot is Loot and loot.kind == "mushroom":
			mushrooms += 1
			var meshes: Array = loot.find_children("*", "MeshInstance3D", true, false)
			if not meshes.is_empty():
				owned_visuals += 1
			if not selected.has(loot.id):
				selected[loot.id] = loot
	check(mushrooms > 0 and owned_visuals == mushrooms, "Every mushroom still owns its visible model after map optimization")
	check(selected.size() == Inventory.MUSHROOMS.size(), "All mushroom varieties are available for collection")
	check(game.render_stats.removed_render_nodes > 0, "Static scenery continues to use render batches")
	for kind: String in selected:
		var mushroom: Loot = selected[kind]
		var meshes: Array = mushroom.find_children("*", "MeshInstance3D", true, false)
		var point := mushroom.global_position
		game.player.global_position = point + Vector3(0, 0.2, 1.3)
		game.player.camera.look_at(point + Vector3.UP * 0.15)
		await shot("05-" + kind + "-before")
		var before: int = game.inventory.mushrooms[kind]
		mushroom.take(game.weapons, game.hud)
		check(mushroom.taken and not mushroom.visible, "%s disappears in the same frame as collection" % kind)
		var all_hidden := true
		for mesh: MeshInstance3D in meshes:
			all_hidden = all_hidden and not mesh.is_visible_in_tree()
		check(all_hidden, "%s leaves no visible cap or stem" % kind)
		mushroom.take(game.weapons, game.hud)
		check(game.inventory.mushrooms[kind] == before + 1, "%s is added to inventory exactly once" % kind)
		await frames()
		check(not is_instance_valid(mushroom), "%s pickup node is removed" % kind)
		var all_freed := true
		for mesh in meshes:
			all_freed = all_freed and not is_instance_valid(mesh)
		check(all_freed, "%s model is removed with its pickup" % kind)
		await shot("06-" + kind + "-after")
	var other_visible := 0
	for loot in game.loots:
		if is_instance_valid(loot) and loot is Loot and loot.kind == "mushroom" and loot.visible and not loot.taken:
			other_visible += 1
	check(other_visible == mushrooms - selected.size(), "Collecting mushrooms leaves the other mushrooms intact")
	print("CAMPSITE_PICKUPS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
