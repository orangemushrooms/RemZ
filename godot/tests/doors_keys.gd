extends SceneTree

var game: Node
var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()
var folder := ProjectSettings.globalize_path("res://../artifacts/doors-keys/")

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("DOORS_KEYS_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func frames(count: int = 3) -> void:
	for i in count:
		await physics_frame
		await process_frame

func shot(name: String) -> void:
	if "--render-doors" not in OS.get_cmdline_user_args():
		return
	game.hud._msg_timer = 0.0
	game.hud.msg_label.text = ""
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + name + ".png")

func stand(at: Vector3, target: Vector3) -> void:
	game.player.global_position = at
	game.player.velocity = Vector3.ZERO
	game.player.camera.look_at(target)

func doorway_hit(door: Door) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(door.to_global(Vector3(-0.8, 1.0, 0)), door.to_global(Vector3(0.8, 1.0, 0)), 1 | 8, [game.player.get_rid()])
	return game.get_world_3d().direct_space_state.intersect_ray(ray)

func press_interact() -> void:
	# Exercise the same nearest-pickup selection and E handler as actual gameplay.
	Input.action_press("interact")
	game._process(0.0)
	Input.action_release("interact")
	await frames()

func close_range_cycle(door: Door, side: float) -> void:
	var description := "%s from %s at 0.5 m" % [door.label, "local -x" if side < 0.0 else "local +x"]
	stand(door.to_global(Vector3(side * 0.5, 0.1, 0)), door.interaction_point())
	await frames()
	check(door.can_interact(game.player), description + " has an interaction prompt")
	await press_interact()
	check(door.is_open, description + " opens using the gameplay E handler")
	if not door.is_open:
		return
	await create_timer(1.0).timeout
	await frames()
	var away := true
	for i in door.leaves.size():
		var middle: Vector3 = door.leaves[i][0].transform * door._offsets[i].origin
		away = away and middle.x * side < -0.3
	check(away and not door.moving and doorway_hit(door).is_empty(), description + " swings away and clears the doorway")
	await shot("07-near-" + door.key_id + "-" + str(door.width) + "-" + str(side))
	await press_interact()
	check(not door.is_open, description + " also closes without stepping back")
	await create_timer(1.0).timeout
	await frames()
	var hit := doorway_hit(door)
	check(not door.is_open and not door.moving and not hit.is_empty() and hit.collider == door.body, description + " restores closed collision")

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
	if "--render-doors" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	await frames()
	var keys: ForestKeys = game.forest_keys
	var doors := get_nodes_in_group("hut_doors")
	check(keys.spawned.size() == 2 and keys.owned.is_empty(), "New game has two uncollected forest keys")
	check(doors.size() == 3, "Garage, upstairs cabin and wood store have real doors")
	var locations: Dictionary = {}
	for seed_value in [1, 2, 3, 17, 999, 4242, 123456, 876543]:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var points := keys.choose_spawn_points(random)
		check(points.size() == 2, "Reachable pair of keys for seed %d" % seed_value)
		if points.size() == 2:
			check(keys.valid_forest_point(Vector2(points[0].x, points[0].z)) and points[0].distance_to(points[1]) >= 30, "Forest location and separation for seed %d" % seed_value)
			locations[str(points[0])] = true
	check(locations.size() >= 6, "Different seeds produce genuinely different search locations")
	for door: Door in doors:
		stand(door.to_global(Vector3(-2.2 if door.width > 1.4 else 2.0, 0.1, 0)), door.interaction_point())
		await frames()
		check(door.is_locked() and not door.take(game.weapons, game.hud) and not door.is_open, "%s cannot open without its key" % door.label)
		var hit := doorway_hit(door)
		check(not hit.is_empty() and hit.collider == door.body, "%s physically blocks its aperture" % door.label)
	await shot("01-locked")
	for key: ForestKey in keys.spawned:
		stand(key.global_position + Vector3(0, 0.1, 20), key.interaction_point())
		keys._process(1.0)
		check(not keys.hint.visible, "No long-distance key beacon")
		key.take(game.weapons, game.hud)
		check(not key.taken, "Cannot collect a key remotely")
		stand(key.global_position + Vector3(0, 0.1, 7), key.interaction_point())
		keys._process(1.0)
		check(keys.hint.visible and keys.hint.target == key, "Proximity reveals the nearest key and arrow")
		await shot("02-discovery-" + key.key_id)
		game.player.camera.rotate_y(PI)
		keys.hint.update_target(key, game.player)
		check(not keys.hint.on_screen and keys.hint.marker.is_finite(), "Arrow remains valid for a key behind the player")
		await shot("03-behind-" + key.key_id)
		stand(key.global_position + Vector3(0, 0.05, 1.1), key.interaction_point())
		await frames()
		# Occluded pickups cannot be taken through a wall.
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3, 3, 0.1)
		shape.shape = box
		wall.add_child(shape)
		game.add_child(wall)
		wall.global_position = key.global_position + Vector3(0, 1, 0.5)
		await frames()
		key.take(game.weapons, game.hud)
		check(not key.taken, "Pickup respects walls")
		wall.queue_free()
		await frames()
		await shot("04-key-" + key.key_id)
		key.take(game.weapons, game.hud)
		check(key.taken and keys.has_key(key.key_id) and not key.pickup_visual.visible and key.visible, "E collects the key while leaving its stump in the world")
		for door: Door in doors:
			check(door.is_locked() == not keys.has_key(door.key_id), "Each door requires the key for its own building")
		check(not keys.hint.visible, "Collected key removes proximity hint immediately")
		var count := keys.owned.size()
		key.take(game.weapons, game.hud)
		check(keys.owned.size() == count, "A key cannot be collected twice")
	for door: Door in doors:
		for side: float in [-1.0, 1.0]:
			await close_range_cycle(door, side)
	# A real actor behind the door must still prevent opening towards it.
	var store: Door = doors.back()
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	var blocker_shape := CollisionShape3D.new()
	var blocker_capsule := CapsuleShape3D.new()
	blocker_capsule.radius = 0.4
	blocker_capsule.height = 1.8
	blocker_shape.shape = blocker_capsule
	blocker_shape.position.y = 0.9
	blocker.add_child(blocker_shape)
	game.add_child(blocker)
	stand(store.to_global(Vector3(-0.5, 0.1, 0)), store.interaction_point())
	blocker.global_position = store.to_global(Vector3(0.7, 0.1, 0))
	await frames()
	check(not store.take(game.weapons, game.hud) and not store.is_open, "An actor on the opening side still blocks the wood-store gate")
	blocker.queue_free()
	await frames()
	for door: Door in doors:
		stand(door.to_global(Vector3(-2.2 if door.width > 1.4 else 2.0, 0.1, 0)), door.interaction_point())
		await frames()
		check(door.can_interact(game.player), "%s can be reached from outside" % door.label)
		check(door.take(game.weapons, game.hud), "%s opens with its matching key" % door.label)
		await create_timer(1.0).timeout
		await frames()
		check(door.is_open and not door.moving and not door.taken and doorway_hit(door).is_empty(), "%s opens a real traversable gap" % door.label)
		var entry := door.to_global(Vector3(-0.8, 0.06, 0))
		entry.y = maxf(entry.y, Map.ground_height(entry.x, entry.z) + 0.06)
		var motion := door.global_basis * Vector3(1.6, 0, 0)
		check(not game.player.test_move(Transform3D(game.player.global_basis, entry), motion), "%s fits the full player capsule" % door.label)
		await shot("05-open-" + door.label)
		check(door.take(game.weapons, game.hud), "%s closes again using E" % door.label)
		await create_timer(1.0).timeout
		await frames()
		check(not door.is_open and not doorway_hit(door).is_empty(), "%s restores collision after closing" % door.label)
		# Pause must freeze an in-progress opening animation.
		door.take(game.weapons, game.hud)
		await frames(5)
		paused = true
		var angle: float = door.leaves[0][0].rotation.y
		await create_timer(0.25, true).timeout
		check(is_equal_approx(angle, door.leaves[0][0].rotation.y), "%s animation respects pause" % door.label)
		paused = false
		await create_timer(1.0).timeout
		# Entering the sweep while it closes reopens it instead of trapping actors.
		door.take(game.weapons, game.hud)
		stand(door.to_global(Vector3(0, 0.1, 0)), door.to_global(Vector3(2, 1, 0)))
		await frames()
		await create_timer(1.0).timeout
		check(door.is_open, "%s reverses when an actor enters the closing door" % door.label)
		stand(door.to_global(Vector3(2.0, 0.1, 0)), door.interaction_point())
		await frames()
		door._set_open(false)
		await create_timer(1.0).timeout
		check(door.crosses(door.to_global(Vector3(-3, 0, 0)), door.to_global(Vector3(3, 0, 0))), "%s is recognized as a defence by enemies" % door.label)
		if door.label == "Garagentor":
			var enemy := Zombie.new()
			enemy.setup("shambler", game.player, [], 1.0, Callable())
			game.zombies_root.add_child(enemy)
			enemy.set_physics_process(false)
			enemy.agent.avoidance_enabled = false
			enemy.global_position = door.to_global(Vector3(-1.1, 0.1, 0))
			await frames()
			var health: float = game.player.hp
			enemy._physics_process(0.01)
			enemy._physics_process(0.4)
			check(enemy.hit_target == door and door._pressure > 0 and game.player.hp == health, "Actual enemy AI attacks the closed door before the protected player")
			enemy.queue_free()
			await frames()
		door.damage(Door.HOLD_STRENGTH)
		check(door.is_open and not door.take(game.weapons, game.hud), "%s yields to sustained attacks and prevents immediate reclosing" % door.label)
	game.waves.start(2)
	check(keys.owned.size() == 2 and keys.spawned.size() == 2, "Wave changes retain keys without respawning them")
	for id: String in game.weapons.DEFS:
		game.weapons.unlock(id)
	game.inventory.open()
	await frames()
	check(game.inventory.grid.get_child_count() == 10, "Full inventory displays both permanent keys alongside equipment")
	check(game.inventory.panel.get_viewport_rect().encloses(game.inventory.panel.get_global_rect()), "Full inventory fits the viewport")
	await shot("06-inventory")
	game.inventory.close()
	if "--restart-keys" in OS.get_cmdline_user_args():
		game.player.damage(10000.0)
		game._on_start()
		await scene_changed
		game = current_scene
		if game.achievements:
			game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
			game.achievements.hide()
			game.achievements = null
		while not game.navigation_ready:
			await process_frame
		check(game.forest_keys.owned.is_empty() and game.forest_keys.spawned.size() == 2 and paused, "Full game restart resets the key hunt and returns to the ready menu")
		for door: Door in get_nodes_in_group("hut_doors"):
			check(door.is_locked() and not door.is_open, "Full restart relocks each cabin door")
	print("DOORS_KEYS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
