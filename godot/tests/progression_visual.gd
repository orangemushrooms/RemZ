extends SceneTree

var game: Node
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000: quit(1)
	return false

func capture(label: String) -> void:
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/progression/" + label + ".png"))
	print("CAPTURE ", label)

func visit(id: String, distance := 3.0) -> void:
	var npc: WorldNpc = game.progression.npcs[id]
	game.player.global_position = npc.global_position + Vector3(1.0, 0.1, distance)
	game.player.camera.look_at(npc.global_position + Vector3.UP * 1.2)
	await physics_frame
	await physics_frame

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.hide()
	game.player.score = 2000
	game.day_night.clock_seconds = 12 * 3600
	game.day_night.advance(1)
	game.day_night.set_process(false)
	if "--icons-only" in OS.get_cmdline_user_args():
		for id in Progression.NPCS:
			await visit(id)
			game.progression.interact(id)
			game.progression.page = "Training" if id == "mechanic" else "Trade"
			game.progression._render()
			await capture("icons-" + id)
			if id == "mechanic":
				game.defences.create_tower(Map.ground_pos(60, 117), 1)
				game.progression.page = "Towers"
				game.progression._render()
				await capture("icons-towers")
			game.progression.close()
		for id in Weapons.ORDER: game.weapons.unlock(id)
		game.inventory.mushrooms = {"steinpilz": 3, "fliegenpilz": 2}
		game.inventory.open()
		await capture("icons-inventory-weapons")
		game.inventory.grid.get_parent().scroll_vertical = 10000
		await capture("icons-inventory-supplies")
		game.inventory.close()
		game.barricade_menu.open(game.barricades[0])
		await capture("icons-barricade")
		game.barricade_menu.close()
		print("ICONS_VISUAL_DONE")
		quit()
		return
	if "--vendor-location" in OS.get_cmdline_user_args():
		game.player.global_position = Map.ground_pos(-3, -1) + Vector3.UP * 0.2
		game.player.camera.look_at(Map.ground_pos(4, -13) + Vector3.UP * 1.0)
		await capture("vendor-campsite-position")
		var destination := Map.ground_pos(4, -14)
		var route := NavigationServer3D.map_get_path(game.nav_region.get_navigation_map(), game.player.global_position, destination, true)
		var reachable := route.size() > 1 and route[-1].distance_to(destination) < 1.0
		await visit("camp", 2.0)
		var can_trade: bool = game.progression.close_enough(game.player, "camp")
		print("VENDOR_LOCATION reachable=", reachable, " can_trade=", can_trade)
		quit(0 if reachable and can_trade else 1)
		return
	if "--inventory-only" in OS.get_cmdline_user_args():
		for id in Weapons.ORDER: game.weapons.unlock(id)
		game.inventory.open()
		await capture("inventory-nine-weapons")
		print("INVENTORY_VISUAL_DONE")
		quit()
		return
	for id in Progression.NPCS:
		await visit(id)
		await capture("npc-" + id)
		game.progression.interact(id)
		game.progression.page = "Quests" if id == "mechanic" else "Trade"
		game.progression._render()
		await capture("shop-" + id)
		game.progression.close()
	game.player.global_position = Map.ground_pos(60, 117) + Vector3.UP * 0.1
	game.player.camera.look_at(Map.ground_pos(60, 112))
	game.defences.placing = true
	game.defences.build_yaw = -0.5
	await capture("tower-preview")
	game.defences.cancel_placement()
	game.player.camera.look_at(Map.ground_pos(60, 95) + Vector3.UP * 2)
	for id in ["marksman", "lmg", "breacher", "titanbreaker"]:
		game.weapons.unlock(id)
		game.weapons.set_weapon(id)
		game.weapons.update_hud()
		await capture("weapon-" + id)
	for finish in ["forest", "bronze", "bone"]:
		game.weapons.apply_skin("titanbreaker", finish)
		await capture("skin-" + finish)
	game.weapons.set_process(true)
	for id in ["marksman", "lmg", "breacher", "titanbreaker"]:
		game.weapons.set_weapon(id)
		Input.action_press("aim")
		await create_timer(0.6).timeout
		await capture("ads-" + id)
		Input.action_release("aim")
	for id in Weapons.ORDER: game.weapons.unlock(id)
	game.inventory.open()
	await capture("inventory-nine-weapons")
	game.inventory.close()
	print("PROGRESSION_VISUAL_DONE")
	quit()
