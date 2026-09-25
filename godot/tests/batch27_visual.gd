# Windowed look at the 26 Sep 2026 evening batch: the titan on hands and knees, the thrown forest tree in
# flight and on the ground, the stag mid-charge with its hooves on the terrain, the earthworm risen and
# striking, the Mechanic's tower page with its beacons, a drone rocket from the pilot's seat and the
# spectator view of a downed player. Saves artifacts/batch27/*.png.
#   Godot.exe --path godot --resolution 1600x900 --script res://tests/run.gd -- --suite=batch27_visual --no-intro --no-music
extends SceneTree

var game: Node
var net: Node
var dir: String
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func look(player: Player, at: Vector3, from: Vector3) -> void:
	player.global_position = from
	player.velocity = Vector3.ZERO
	var to: Vector3 = at - (from + Vector3.UP * Player.EYE)
	player.rotation.y = atan2(-to.x, -to.z)
	player.pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.4, 1.4)
	player.head.rotation.x = player.pitch

func shot(name: String, frames := 24) -> void:
	for i in frames: await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(dir + name + ".png")
	print("BATCH27_SHOT ", name, " ", image.get_size())
	check(image.get_size().x > 0, "Saved " + name)

func wait_seconds(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0

func last_zombie() -> Zombie:
	var found: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie: found = z
	return found

func clear_zombies() -> void:
	for z in game.zombies_root.get_children():
		if z is Zombie:
			game.zombies_root.remove_child(z)
			z.queue_free()
	game._alive_count = 0

func run() -> void:
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	check(net.host("Host", 24699) == OK, "The fixture hosts a round")
	net.roster[2] = "Anna"
	net.world.add_player(2)
	net._begin(net.epoch, false)
	game.waves.set_process(false)
	game.day_night.set_process(false)
	game.day_night.set_time_hours(15.0)
	dir = ProjectSettings.globalize_path("res://../artifacts/batch27/")
	DirAccess.make_dir_recursive_absolute(dir)
	var world = net.world
	var player: Player = game.player
	var anna: Player = world.actor(2)
	player.set_physics_process(false)
	player.flashlight.visible = false
	anna.global_position = Map.ground_pos(-40, 60) + Vector3.UP * 0.3   # out of every picture
	# ---- the titan on hands and knees
	game.waves.wave = 6
	check(game.spawn_zombie("titan", Vector2(10, 126), 1.0, "east"), "A titan rises on the meadow")
	var titan: Titan = last_zombie() as Titan
	if titan:
		titan.strike_phase = "walk"
		titan.play("walk")
		titan.hp = titan.max_hp * 0.34
		titan.damage(1.0, Vector3(1, 0, 0))
		var t := 0.0
		while t < 6.0 and titan.clip != "crawl":
			await process_frame
			t += root.get_process_delta_time() if root else 1.0 / 60.0
		check(titan.clip == "crawl", "The titan crawls for the picture (clip %s)" % titan.clip)
		await wait_seconds(1.5)
		look(player, titan.global_position + Vector3.UP * 5.0, Map.ground_pos(titan.global_position.x + 34.0, titan.global_position.z - 22.0) + Vector3.UP * 0.05)
		await shot("titan_crawl", 6)
		var tree := ThrownTree.new()
		game.add_child(tree)
		tree.setup(titan.global_position + Vector3.UP * 14.0, player.global_position + Vector3(8, 0, -6), 3.0, titan, true)
		await shot("titan_tree_flight", 50)
		await wait_seconds(2.5)
		look(player, tree.global_position + Vector3.UP * 2.0, Map.ground_pos(tree.global_position.x + 16.0, tree.global_position.z + 12.0) + Vector3.UP * 0.05)
		await shot("titan_tree_landed", 12)
		tree.queue_free()
	clear_zombies()
	# ---- the stag mid-charge, hooves on the terrain
	check(game.spawn_zombie("zombie_stag", Vector2(24, 118), 1.0), "A stag stands on the meadow")
	var stag: ZombieBeast = last_zombie() as ZombieBeast
	if stag:
		await physics_frame
		await physics_frame
		stag.set_physics_process(false)
		stag.global_position.y = Map.ground_height(stag.global_position.x, stag.global_position.z)
		stag.rotation.y = PI * 0.5
		stag._charge_t = 2.0
		stag._lunge = 0.2
		stag._ground_speed = 9.0
		for i in 8: stag._update_animation(0.05)
		look(player, stag.global_position + Vector3.UP * 0.8, Map.ground_pos(stag.global_position.x + 1.0, stag.global_position.z + 7.0) + Vector3.UP * 0.05)
		player.head.position.y = 0.9
		await shot("stag_charge", 12)
		player.head.position.y = Player.EYE
	clear_zombies()
	# ---- the earthworm risen and striking
	check(game.spawn_zombie("earthworm", Vector2(40, 130), 1.0, "east", 0.0), "An earthworm surfaces on the meadow")
	var worm: Earthworm = last_zombie() as Earthworm
	if worm:
		await physics_frame
		worm.set_physics_process(false)
		worm.phase_time = 0.0
		worm._advance_phase()   # emerge
		worm._advance_phase()   # exposed
		if worm.anim: worm.anim.seek(1.2, true)
		look(player, worm.global_position + Vector3.UP * 7.0, Map.ground_pos(worm.global_position.x + 26.0, worm.global_position.z + 14.0) + Vector3.UP * 0.05)
		await shot("worm_exposed", 12)
		worm._advance_phase()   # windup
		if worm.anim: worm.anim.seek(worm.anim.get_animation("attack").length * 0.5, true)
		await shot("worm_windup", 6)
	clear_zombies()
	# ---- the Mechanic's tower page with its beacons (the shop closes itself when the player walks off,
	# so the picture is taken standing at the Mechanic with the towers within the planner's reach)
	var shop: Progression = game.progression
	var mechanic: Vector3 = shop.npcs.mechanic.global_position
	player.global_position = mechanic + Vector3(0, 0.1, 2.3)
	player.score = 5000
	game.waves.completed = 8
	await physics_frame
	await physics_frame
	var kinds := ["standard", "mortar", "flame"]
	var spots := [Vector2(14, -40), Vector2(20, -34), Vector2(26, -28), Vector2(-24, -44), Vector2(-30, -38), Vector2(20, 10), Vector2(26, 4), Vector2(32, -2), Vector2(8, -46), Vector2(-14, -50)]
	var built := 0
	var centre := Vector3.ZERO
	for spot in spots:
		if built >= kinds.size(): break
		var error: String = game.defences.purchase(player, Map.ground_pos(spot.x, spot.y), 0.0, kinds[built], true)
		if error.is_empty():
			centre += Map.ground_pos(spot.x, spot.y)
			built += 1
	check(built == 3, "Three towers stand for the Mechanic (%d)" % built)
	centre /= maxf(1.0, float(built))
	for tower: DefenceTower in game.defences.towers.values(): tower.level = 1 + (tower.tower_id % 2)
	shop.interact("mechanic")
	shop.page = "Towers"
	shop._render()
	check(shop.is_open and game.defences.markers_shown, "The tower page is open with its beacons")
	look(player, centre + Vector3.UP * 6.0, player.global_position)
	await shot("mechanic_towers", 20)
	shop.close()
	await shot("tower_beacons_off", 6)
	for id in game.defences.towers.keys():
		var tower: DefenceTower = game.defences.towers[id]
		game.defences.towers.erase(id)
		tower.queue_free()
	# ---- a drone rocket from the pilot's seat
	game.waves.wave = 5
	game.forest_keys.owned.waldhuette = true
	player.global_position = game.drones.station.to_global(Vector3(0, 0, 1.6))
	check(game.drones.launch(player, "scout").is_empty() and player.controlling_drone > 0, "The pilot launches a scout")
	var drone: AttackDrone = game.drones.drones.get(player.controlling_drone)
	if drone:
		for i in 3: await process_frame
		drone.global_position = Map.ground_pos(60, 112) + Vector3.UP * 7.0
		drone.velocity = Vector3.ZERO
		for i in 4: game.spawn_zombie("shambler", Vector2(60 + i * 1.5, 92), 1.0)
		await physics_frame
		var target := Map.ground_pos(62, 92) + Vector3.UP * 1.0
		var dir3 := drone.camera.global_position.direction_to(target)
		game.drones._look_yaw = atan2(-dir3.x, -dir3.z)
		game.drones._look_pitch = atan2(dir3.y, Vector2(dir3.x, dir3.z).length())
		drone.yaw = game.drones._look_yaw
		drone.pitch = game.drones._look_pitch
		drone.update_view()
		drone.rocket_pending = true
		drone._physics_process(0.016)
		await shot("drone_rocket_flight", 10)
		await wait_seconds(1.2)
		await shot("drone_rocket_burst", 2)
		game.drones.recall(player)
	clear_zombies()
	# ---- the spectator view of a downed player
	anna.global_position = Map.ground_pos(Map.FIRE.x - 4.0, Map.FIRE.y - 6.0) + Vector3.UP * 0.3
	anna.rotation.y = 2.4
	anna.pitch = -0.05
	player.global_position = Map.ground_pos(Map.FIRE.x + 3.0, Map.FIRE.y - 2.0) + Vector3.UP * 0.3
	player.self_revives = 0
	player.go_down()
	world.tick(0.05)
	for i in 3: await process_frame
	check(world.spectator != null and world.spectator.current, "The camera watches Anna")
	await shot("spectator_view", 20)
	player.revive(60.0)
	world.tick(0.05)
	print("BATCH27_VISUAL_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
