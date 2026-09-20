extends SceneTree

var failures := 0
var checks := 0
var started_at := Time.get_ticks_msec()
var game: Node

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 120000:
		push_error("SMOKE_TIMEOUT")
		quit(1)
	return false

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func run() -> void:
	seed(4242)
	game = load("res://scenes/main.tscn").instantiate()
	if game.get_script() == null:
		push_error("SMOKE_ABORT: main scene script failed to load")
		quit(1)
		return
	root.add_child(game)
	current_scene = game
	check(paused and not game.player.active, "Start screen pauses the simulation")
	while not game.navigation_ready:
		await process_frame
	check(game.nav_region.navigation_mesh.get_polygon_count() > 0, "Navigation bake produces walkable polygons")
	game._on_start()
	game.waves.set_process(false)
	await physics_frame
	await physics_frame
	check(not paused and game.player.active, "Start enables gameplay after navigation is ready")
	check(game.render_stats.removed_render_nodes > 0, "Static map meshes are batched")
	check(get_nodes_in_group("render_grass").size() > 1, "Grass has independently culled cells")
	for quality in 3:
		game.settings.profile = quality
		game.settings.apply()
		check(game.settings.env.ssil_enabled == (quality == 2), "Graphics profile %d applies" % quality)
	game.settings.profile = 0
	game.settings.apply()
	var weapon: Weapons = game.weapons
	check(weapon.viewmodel.camera.get_world_3d() != game.player.camera.get_world_3d(), "Nearby world geometry cannot occlude first-person hands")
	check(is_equal_approx(weapon.viewmodel.viewport.scaling_3d_scale, 1.0), "Viewmodel retains full resolution with the performance graphics profile")
	check(game.hud.minimap.TITLE == "Remetschwil Sennhof", "Minimap has the requested title")
	var north: Vector2 = game.hud.minimap.map_position(Vector3(0, 0, -10))
	var south: Vector2 = game.hud.minimap.map_position(Vector3(0, 0, 10))
	check(north.y < south.y and is_equal_approx(north.x, south.x), "Minimap keeps north up and distances undistorted")
	for id in Weapons.ORDER:
		var hands: ViewmodelHands = weapon.state[id].hands
		check(hands.get_child_count() == 2 and hands.support != null, "%s has both fitted hands" % id)
		check(weapon.state[id].aim_position.z + weapon.state[id].bounds.end.z <= -0.1799, "%s stays ahead of the camera when aiming" % id)
	weapon.set_process(false)
	var ammo_before: int = weapon.cur().ammo
	weapon.try_fire()
	check(weapon.cur().ammo == ammo_before - 1, "A shot consumes exactly one round")
	check(weapon.flash_mesh.visible and weapon.flash_mesh.get_world_3d() == weapon.viewmodel.camera.get_world_3d() and (weapon.flash_mesh.layers & weapon.viewmodel.camera.cull_mask) != 0, "Muzzle flash is visible to the first-person camera when firing")
	weapon.try_fire()
	check(weapon.cur().ammo == ammo_before - 1, "Cooldown prevents an immediate second shot")
	weapon.cur().ammo = 2
	weapon.cur().reserve = 3
	weapon.reload()
	var reload_time: float = weapon.cur().reloading
	weapon.set_weapon("pistol")
	check(weapon.cur().reloading == reload_time, "Selecting the current gun does not cancel reload")
	weapon._process(2.0)
	check(weapon.cur().ammo == 5 and weapon.cur().reserve == 0, "Reload conserves ammunition")
	weapon.reload()
	check(weapon.cur().reloading == 0.0, "No reload without reserve ammunition")
	weapon.unlock("smg")
	for fps in [30, 60, 144]:
		weapon.set_weapon("smg")
		weapon.cur().ammo = 100
		weapon.cur().cooldown = 0.0
		Input.action_press("fire")
		for frame in fps * 2:
			weapon._process(1.0 / fps)
		Input.action_release("fire")
		var shots: int = 100 - weapon.cur().ammo
		check(shots >= 26 and shots <= 28, "Automatic fire cadence is stable at %d FPS (%d shots)" % [fps, shots])
	weapon.set_weapon("pistol")
	var bar: Barricade = game.barricades[0]
	game.player.add_score(200)
	bar.interact(game.player)
	await process_frame
	check(bar.level == 1 and not bar.body.get_child(0).disabled, "Built barricade has active collision")
	var visual_id: int = bar.visual.get_child(0).get_instance_id()
	bar.damage(10.0)
	check(bar.visual.get_child(0).get_instance_id() == visual_id, "Barricade damage reuses existing models")
	bar.repair()
	check(bar.hp == bar.max_hp() and bar.visual.get_child(0).get_instance_id() == visual_id, "Repair restores health without rebuilding models")
	bar.damage(10000.0)
	await process_frame
	check(bar.level == 0 and bar.body.get_child(0).disabled, "Destroyed barricade releases collision")
	game.spawn_zombie("shambler", Map.PLAYER_START + Vector2(12, 0), 1.0)
	var zombie: Zombie = game.zombies_root.get_child(0)
	check(game.alive_zombies() == 1, "Spawn updates enemy count")
	var player_position: Vector3 = game.player.global_position
	game.player.set_physics_process(false)
	zombie.set_physics_process(false)
	zombie.agent.avoidance_enabled = false
	zombie.global_position = Vector3(0, 40, 0)
	game.player.global_position = Vector3(0, 40, -1.2)
	check(zombie._can_hit(null), "Enemy can hit a nearby unobstructed player")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	collision.shape = box
	wall.add_child(collision)
	game.add_child(wall)
	wall.global_position = Vector3(0, 41, -0.6)
	await physics_frame
	await physics_frame
	check(not zombie._can_hit(null), "Walls block enemy melee damage")
	wall.queue_free()
	game.player.global_position = player_position
	game.player.set_physics_process(true)
	zombie.damage(10000.0, Vector3.FORWARD)
	zombie.damage(10000.0, Vector3.FORWARD)
	check(game.alive_zombies() == 0, "A kill is counted exactly once")
	game.waves.phase = "spawning"
	game.waves.wave = 3
	game.waves.queue.clear()
	game.waves._process(0.01)
	check(game.waves.completed == 3 and game.waves.phase == "idle", "Cleared wave awards completion and enters intermission")
	weapon.throw_grenade()
	var grenade: Grenade
	for child in game.get_children():
		if child is Grenade:
			grenade = child
	check(grenade != null, "Grenade throw creates a live grenade")
	game._pause()
	var fuse: float = grenade._t
	var grenade_pos := grenade.global_position
	await create_timer(0.15, true).timeout
	check(paused and grenade._t == fuse and grenade.global_position == grenade_pos, "Pause freezes grenade fuse and physics")
	game._on_start()
	await create_timer(0.1).timeout
	check(grenade._t > fuse, "Resume continues grenade simulation")
	game.skills.open()
	check(not paused and game.player.active and not game.progression.is_open, "Remote skill menu no longer grants purchases")
	game.skills.close()
	check(not paused and game.player.active, "Closing skills resumes combat")
	grenade.queue_free()
	game.player.hp = game.player.max_hp
	game.player.damage(10000.0)
	check(game.over and paused and not game.player.alive, "Death freezes gameplay and shows restart")
	game._on_start()
	await scene_changed
	game = current_scene
	while not game.navigation_ready:
		await process_frame
	check(game.player.hp == 100.0 and game.waves.completed == 0 and game.alive_zombies() == 0, "Restart resets health, waves and enemies")
	check(not paused and game.started and game.player.active, "Restart goes straight into the next round")
	print("SMOKE_DONE checks=%d failures=%d" % [checks, failures])
	paused = false
	quit(0 if failures == 0 else 1)
