extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var hunt = game.hunting
	for a in hunt.animals:
		a.set_physics_process(false)
		a.set_process(false)
	check(hunt.animals.size() > 8, "Deer, stags and birds registered")
	var deer: Deer = hunt.animals[0]
	deer.global_position = Map.ground_pos(40, 100)
	game.player.global_position = deer.global_position + Vector3(0, 0.1, 6)
	game.player.camera.look_at(deer.global_position + Vector3.UP * 0.75)
	game.weapons.ads = 1.0
	game.weapons.spread_mul = 0.0
	await physics_frame
	await physics_frame
	var hp: float = hunt.health[0]
	game.weapons.try_fire()
	check(hunt.health[0] < hp, "Actual pistol ray damages an animal")
	check(deer.state == "flee", "Wounded animal flees")
	hunt.hit(deer, 999, 1)
	check(hunt.health[0] == 0 and hunt.drops.size() == 1, "Death creates one meat drop")
	check(game.achievements.session_unlocked.has("hunter"), "First hunt unlocks Jaeger achievement")
	check(game.stats.kills == 0, "Hunting does not inflate zombie kills")
	hunt.hit(deer, 999, 1)
	check(hunt.drops.size() == 1 and game.achievements.counters.hunted == 1, "Repeated damage cannot duplicate drops or achievement progress")
	hunt.transact(game.player, "collect", 0)
	check(int(hunt.stock(1).raw_meat) == 0, "Remote pickup rejected")
	game.player.global_position = hunt.drops[0].position + Vector3(0, 0.1, 1.6)
	await physics_frame
	check(hunt.nearby_drop(game.player) == 0, "Meat can be found for E interaction")
	hunt.transact(game.player, "collect", 0)
	check(int(hunt.stock(1).raw_meat) == 4 and hunt.drops.is_empty(), "Stag yields four portions")
	hunt.transact(game.player, "collect", 0)
	check(int(hunt.stock(1).raw_meat) == 4, "Collected meat cannot be taken twice")
	hunt.transact(game.player, "cook")
	check(hunt.jobs.is_empty(), "Cooking requires proximity to the grill")
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 2.5)
	game.player.camera.look_at(Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.8)
	await physics_frame
	check(hunt.at_grill(game.player), "Existing camp grill is reachable")
	await process_frame
	Input.action_press("interact")
	game._process(0.016)
	Input.action_release("interact")
	await process_frame
	await process_frame
	check(hunt.jobs.has(1) and int(hunt.stock(1).raw_meat) == 3, "Grill reserves exactly one raw portion via E (%s)" % game.hud.prompt_label.text)
	hunt.transact(game.player, "cook")
	check(int(hunt.stock(1).raw_meat) == 3, "Repeated E cannot start overlapping cooking jobs")
	hunt._process(5.0)
	check(int(hunt.stock(1).cooked_meat) == 0, "Cooking takes time")
	hunt._process(1.1)
	check(int(hunt.stock(1).cooked_meat) == 1 and hunt.jobs.is_empty(), "Finished cooking adds a cooked portion")
	game.player.hp = game.player.max_hp
	hunt.transact(game.player, "eat")
	check(int(hunt.stock(1).cooked_meat) == 1, "Full health preserves food")
	game.player.hp -= 50
	var before: float = game.player.hp
	hunt.transact(game.player, "eat")
	check(is_equal_approx(game.player.hp, before + 35) and int(hunt.stock(1).cooked_meat) == 0, "Cooked meat heals and is consumed")
	var money: int = game.player.score
	game.player.global_position = game.progression.npcs.camp.global_position + Vector3(0, 0, 1.2)
	game.progression.transact(game.player, "camp", "sell_meat", "raw_meat")
	check(game.player.score == money + 12 and int(hunt.stock(1).raw_meat) == 2, "Vendor buys raw meat")
	hunt.stock(1).cooked_meat = 1
	game.progression.transact(game.player, "camp", "sell_meat", "cooked_meat")
	check(game.player.score == money + 32 and int(hunt.stock(1).cooked_meat) == 0, "Vendor buys cooked meat at higher price")
	game.progression.transact(game.player, "camp", "sell_meat", "cooked_meat")
	check(game.player.score == money + 32, "No sale without stock")
	var bird: Node3D = hunt.animals[8]
	bird.visible = true
	bird.global_position = Map.ground_pos(50, 100) + Vector3.UP * 4
	var area: Area3D
	for child in bird.get_children():
		if child is Area3D: area = child
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(bird.global_position + Vector3(0, 0.22, 3), bird.global_position + Vector3(0, 0.22, -3), Zombie.SHOT_MASK)
	ray.collide_with_areas = true
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == area, "Flying bird has a hittable body")
	hunt.hit(area, 99, 1)
	check(hunt.drops.has(8) and hunt.drops[8].amount == 1, "Bird drops one portion on the ground")
	var saved: Dictionary = hunt.snapshot()
	hunt.stock(1).raw_meat = 99
	hunt.drops.clear()
	hunt.apply_snapshot(saved)
	check(int(hunt.stock(1).raw_meat) == 2 and hunt.drops.has(8) and hunt.health[0] == 0, "Snapshot restores food, uncollected meat and dead animals")
	game.inventory._refresh()
	game.quickbar.bind_item(1, "cooked_meat")
	check(game.quickbar.bindings[1] == "", "Quickbar refuses food not owned")
	hunt.stock(1).cooked_meat = 1
	game.player.hp = 30
	game.quickbar.bind_item(1, "cooked_meat")
	game.quickbar.activate(1)
	check(game.player.hp == 65 and int(hunt.stock(1).cooked_meat) == 0, "Quickbar eats owned food through the normal transaction (hp=%s active=%s paused=%s placing=%s)" % [game.player.hp,game.player.active,paused,game.defences.placing])
	hunt.stock(1).cooked_meat = 1
	game.inventory.open()
	var raw_button: Button
	var cooked_button: Button
	for button in game.inventory.grid.get_children():
		if button.is_queued_for_deletion(): continue
		if button.tooltip_text.begins_with("Rohes Wildfleisch"): raw_button = button
		if button.tooltip_text.begins_with("Gegrilltes Wildfleisch"): cooked_button = button
	check(raw_button != null and cooked_button != null, "Inventory presents both foods with their own slots")
	if raw_button: raw_button.pressed.emit()
	check(int(hunt.stock(1).raw_meat) == 2, "Clicking raw meat only explains grilling")
	if cooked_button: cooked_button.pressed.emit()
	check(game.player.hp == 100 and int(hunt.stock(1).cooked_meat) == 0, "Inventory button consumes cooked food and refreshes")
	game.inventory.close()
	# Actual tower and blast paths use the same death/drop transaction.
	var target: Deer = hunt.animals[2]
	target.global_position = Map.ground_pos(55, 105)
	await physics_frame
	await physics_frame
	var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(55, 109), 1)
	hunt.health[2] = 1.0
	tower.fire_at(target.global_position + Vector3.UP * 0.7)
	check(hunt.health[2] == 0 and hunt.drops.has(2), "Turret bullet can hunt an animal")
	var blast_target: Deer = hunt.animals[3]
	blast_target.global_position = Map.ground_pos(60, 105)
	await physics_frame
	var shell = preload("res://scripts/tower_shell.gd").new()
	shell.game = game
	shell.authoritative = true
	shell.owner_peer = 1
	shell.start = blast_target.global_position + Vector3(0, 1.0, 1)
	shell.destination = shell.start
	game.add_child(shell)
	shell.global_position = shell.start
	shell.explode()
	check(hunt.health[3] == 0 and hunt.drops.has(3), "Mortar blast damages nearby wildlife")
	if "--hunting-visual" in OS.get_cmdline_user_args():
		var directory := ProjectSettings.globalize_path("res://../artifacts/hunting")
		DirAccess.make_dir_recursive_absolute(directory)
		game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 2.5)
		game.player.camera.look_at(Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.8)
		hunt.transact(game.player, "cook")
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory + "/grill.png")
		hunt.stock(1).cooked_meat = 2
		game.inventory.open()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory + "/inventory.png")
		game.inventory.close()
	print("HUNTING_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
