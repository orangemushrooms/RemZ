# Windowed look at the 26 Sep 2026 batch: the new zombies in a row on the wet plaza, a storm flash at
# dusk, the blood moon, fog banks over the meadow, a crawling titan throwing a tree, a deployed sandbag
# line with an acid pool. Saves artifacts/batch26/*.png.
#   Godot.exe --path godot --resolution 1600x900 --script res://tests/run.gd -- --suite=batch26_visual --no-intro --no-music
extends SceneTree

var game: Node
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
	print("BATCH26_SHOT ", name, " ", image.get_size())
	check(image.get_size().x > 0, "Saved " + name)

func freeze(z: Zombie) -> void:
	z.set_physics_process(false)
	if z.anim:
		z.anim.play("idle" if z.anim.has_animation("idle") else "walk")
		z.anim.seek(0.3, true)
		z.anim.pause()

func clear_zombies() -> void:
	for z in game.zombies_root.get_children():
		if z is Zombie:
			game.zombies_root.remove_child(z)
			z.queue_free()
	game._alive_count = 0

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.day_night.set_process(false)
	dir = ProjectSettings.globalize_path("res://../artifacts/batch26/")
	DirAccess.make_dir_recursive_absolute(dir)
	var player: Player = game.player
	player.set_physics_process(false)
	var weather: Weather = game.weather
	# ---- the line-up on the wet plaza
	game.day_night.set_time_hours(15.0)
	weather.force("rain")
	weather.intensity = 1.0
	weather.wetness = 1.0
	var kinds := ["zombie_dog", "zombie_stag", "spitter", "screamer", "stalker", "shambler"]
	var x := -7.0
	for kind in kinds:
		var armored := 1 if kind == "shambler" else -1
		game.spawn_zombie(kind, Vector2(Map.FIRE.x + x, Map.FIRE.y - 9.0), 1.0, "", 0.0, armored)
		x += 2.8
	await physics_frame
	for z in game.zombies_root.get_children():
		if z is Zombie:
			freeze(z)
			z.rotation.y = PI   # face south, towards the camera
			if z.net_kind == "stalker":
				z.cloak = 1.0
				for m in z._materials: m.albedo_color.a = 1.0
	player.flashlight.visible = false
	look(player, Map.ground_pos(Map.FIRE.x, Map.FIRE.y - 9.0) + Vector3.UP * 1.0, Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 3.0) + Vector3.UP * 0.05)
	await shot("lineup_rain", 40)
	# the stalker alone: hidden, then in the flashlight
	for z in game.zombies_root.get_children():
		if z is Zombie and z.net_kind == "stalker":
			z.cloak = 0.07
			for m in z._materials: m.albedo_color.a = 0.07
	game.day_night.set_time_hours(21.0)
	weather.force("clear")
	weather.intensity = 0.0
	await shot("stalker_hidden_night", 30)
	player.flashlight.visible = true
	for z in game.zombies_root.get_children():
		if z is Zombie and z.net_kind == "stalker":
			z.cloak = 1.0
			for m in z._materials: m.albedo_color.a = 1.0
	await shot("stalker_lit_night", 30)
	# ---- storm at dusk with a flash
	game.day_night.set_time_hours(19.5)
	weather.force("storm")
	weather.intensity = 1.0
	weather.wetness = 1.0
	await shot("storm_dusk", 40)
	weather._next_bolt = 0.0
	weather._process(0.02)
	await shot("storm_flash", 2)
	for i in 120: await process_frame
	# ---- blood moon
	weather.force("clear")
	weather.intensity = 0.0
	game.day_night.night_index = DayNightCycle.BLOOD_MOON_EVERY
	game.day_night.set_time_hours(22.0)
	check(game.day_night.blood_moon(), "The blood moon is up for the shot")
	player.flashlight.visible = false
	look(player, Map.ground_pos(Map.FIRE.x, Map.FIRE.y - 9.0) + Vector3.UP * 6.0, Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 3.0) + Vector3.UP * 0.05)
	await shot("blood_moon", 40)
	game.day_night.night_index = 0
	# ---- fog banks over the meadow at seven
	clear_zombies()
	game.day_night.set_time_hours(7.0)
	weather.force("fog")
	weather.intensity = 1.0
	weather.wetness = 0.0
	look(player, Map.ground_pos(10, 126) + Vector3.UP * 2.0, Map.ground_pos(7, 70) + Vector3.UP * 0.05)
	await shot("fog_meadow", 60)
	# ---- the crawling titan and its tree
	weather.force("clear")
	weather.intensity = 0.0
	game.day_night.set_time_hours(16.0)
	game.waves.wave = 6
	game.spawn_zombie("titan", Vector2(10, 126), 1.0, "east")
	var titan: Titan = null
	for z in game.zombies_root.get_children():
		if z is Titan: titan = z
	if titan:
		titan.set_physics_process(false)
		titan.hp = titan.max_hp * 0.3
		titan.damage(1.0, Vector3(1, 0, 0))
		look(player, titan.global_position + Vector3.UP * 6.0, Map.ground_pos(34, 104) + Vector3.UP * 0.05)
		await shot("titan_crawl", 40)
		var tree := ThrownTree.new()
		game.add_child(tree)
		tree.setup(titan.global_position + Vector3.UP * 14.0, player.global_position + Vector3(6, 0, 0), 3.0, titan, true)
		await shot("titan_tree", 45)
	clear_zombies()
	# ---- the sandbag line behind a breached gate, an acid pool eating it
	var gate: Barricade = game.barricades[1]
	var line: SandbagLine = game.sandbags[1]
	gate.build()
	gate.damage(1e6)
	var inward: Vector2 = (Vector2(line.center.x, line.center.z) - Vector2(gate.center.x, gate.center.z)).normalized()
	var pool := AcidPool.new()
	game.add_child(pool)
	pool.global_position = line.attack_point(gate.center) - Vector3(inward.x, 0, inward.y) * 1.5 + Vector3.UP * 0.04
	pool.setup(Zombie.TYPES.spitter.ranged, true)
	var stand: Vector2 = Vector2(line.center.x, line.center.z) + inward * 7.0
	look(player, line.center + Vector3.UP * 0.6, Map.ground_pos(stand.x, stand.y) + Vector3.UP * 0.05)
	await shot("sandbags_acid", 40)
	print("BATCH26_VISUAL_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
