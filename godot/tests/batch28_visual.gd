# Windowed look at the second feedback round of 26 Sep 2026 (solo, so the bar's pause path runs too):
# the stag and the dog running across the meadow seen from the side, the thrown green conifer in flight
# and on the ground, the liberty caps around the party site, the bar menu with an order placed while the
# game is paused, and the party's own fireworks over the dance floor. Saves artifacts/batch28/*.png.
#   Godot.exe --path godot --resolution 1600x900 --script res://tests/run.gd -- --suite=batch28_visual --no-intro --no-music
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
	print("BATCH28_SHOT ", name, " ", image.get_size())
	check(image.get_size().x > 0, "Saved " + name)

func wait_seconds(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0

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
	game.day_night.set_time_hours(15.0)
	dir = ProjectSettings.globalize_path("res://../artifacts/batch28/")
	DirAccess.make_dir_recursive_absolute(dir)
	var player: Player = game.player
	player.flashlight.visible = false
	# ---- the beasts running, seen from the side: the target walks away so they keep moving
	for kind in ["zombie_stag", "zombie_dog"]:
		player.set_physics_process(false)
		player.global_position = Map.ground_pos(64, 120) + Vector3.UP * 0.3
		game.spawn_zombie(kind, Vector2(20, 120), 1.0)
		var beast: ZombieBeast = null
		for z in game.zombies_root.get_children():
			if z is ZombieBeast: beast = z
		await wait_seconds(2.2)
		var at: Vector3 = beast.global_position
		# the camera 7 m to the side, eye low, so hooves and grass line are in the picture
		var side := Vector3(0, 0, 7.0)
		player.global_position = Map.ground_pos(at.x, at.z + 7.0) + Vector3.UP * 0.05
		look(player, at + Vector3.UP * 0.6, player.global_position)
		player.head.position.y = 0.7
		await shot(kind.trim_prefix("zombie_") + "_running", 3)
		var mesh: MeshInstance3D = beast.model.find_children("*", "MeshInstance3D", true, false)[0]
		var aabb := mesh.get_aabb()
		var low := INF
		for k in 8: low = minf(low, (mesh.global_transform * aabb.get_endpoint(k)).y)
		check(low - beast.global_position.y > -0.12, "%s: lowest point %.2f m relative to its feet" % [kind, low - beast.global_position.y])
		player.head.position.y = Player.EYE
		clear_zombies()
		await process_frame
	# ---- the thrown green conifer
	player.global_position = Map.ground_pos(34, 104) + Vector3.UP * 0.05
	var tree := ThrownTree.new()
	game.add_child(tree)
	tree.setup(Map.ground_pos(10, 126) + Vector3.UP * 16.0, Map.ground_pos(26, 112), 3.0, null, true)
	await wait_seconds(1.3)
	look(player, tree.global_position, player.global_position)
	await shot("tree_flight", 2)
	await wait_seconds(2.2)
	look(player, tree.global_position + Vector3.UP * 1.5, Map.ground_pos(tree.global_position.x + 12.0, tree.global_position.z + 10.0) + Vector3.UP * 0.05)
	await shot("tree_landed", 10)
	tree.queue_free()
	# ---- liberty caps around the party site, by day
	var caps: Array[Vector3] = []
	for item in game.loots:
		if item is Loot and item.id == "kahlkopf" and Vector2(item.global_position.x, item.global_position.z).distance_to(SecretNight.SITE) < 40.0: caps.append(item.global_position)
	check(caps.size() >= 15, "%d liberty caps around the party" % caps.size())
	if not caps.is_empty():
		var cap: Vector3 = caps[0]
		look(player, cap, Map.ground_pos(cap.x + 2.2, cap.z + 2.2) + Vector3.UP * 0.05)
		await shot("liberty_caps", 20)
	# ---- the party: the bar menu, an order while paused, the fireworks
	var night: SecretNight = game.secret_night
	night.begin()
	night.step = SecretNight.DANCE_STEP
	player.global_position = Map.ground_pos(SecretNight.BAR.x, SecretNight.BAR.y + 2.5) + Vector3.UP * 0.3
	look(player, Map.ground_pos(SecretNight.BAR.x, SecretNight.BAR.y) + Vector3.UP * 1.2, player.global_position)
	for i in 20: await process_frame
	check(Lang.text(game.hud.prompt_label.text).contains("Bar"), "At the bar the prompt offers drinks (%s)" % Lang.text(game.hud.prompt_label.text))
	player.score = 300
	night.bar.open()
	check(paused and night.bar.is_open, "Solo: the bar pauses the game like a shop")
	await shot("bar_menu", 6)
	var button: Button = night.bar.list.get_child(0)
	button.pressed.emit()
	for i in 30: await process_frame
	check(player.score == 270 and player.mushroom_effects.has("goa_sunrise"), "A click on the Goa Sunrise buys it while paused (%d R)" % player.score)
	await shot("bar_after_order", 6)
	night.bar.close()
	check(not paused and player.active, "Closing the bar resumes the game")
	night.show_t = 0.0
	# from the dance floor, facing away from the stage, up into the sky where the salvos burst
	look(player, Map.ground_pos(-108, -150) + Vector3.UP * 40.0, Map.ground_pos(-108, -190) + Vector3.UP * 0.05)
	await wait_seconds(6.0)
	check(night.show_rockets >= 2, "The party launches its own fireworks (%d)" % night.show_rockets)
	await shot("party_fireworks", 2)
	await wait_seconds(1.5)
	await shot("party_fireworks_2", 2)
	print("BATCH28_VISUAL_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
