# Diagnostic only: attribute CPU work without changing production quality.
extends SceneTree
class ProfiledZombie extends Zombie:
	var tick_us := 0
	var move_us := 0
	var decision_us := 0
	var ticks := 0
	func _physics_process(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._physics_process(delta)
		tick_us += Time.get_ticks_usec() - start
		ticks += 1
	func _on_velocity_computed(safe: Vector3) -> void:
		var start := Time.get_ticks_usec()
		super._on_velocity_computed(safe)
		move_us += Time.get_ticks_usec() - start
	func _choose_defence(p: Vector3, priority: bool) -> Node3D:
		var start := Time.get_ticks_usec()
		var result := super._choose_defence(p, priority)
		decision_us += Time.get_ticks_usec() - start
		return result
var game: Node
var zombies: Array[ProfiledZombie] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	# Prevent catch-up spirals during diagnosis; these are CPU timings, not an FPS claim.
	Engine.max_physics_steps_per_frame = 1
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.player.global_position = Map.ground_pos(0, 85)
	game.player.camera.look_at(Map.ground_pos(0, 115) + Vector3.UP)
	game.player.max_hp = 1000000
	game.player.hp = 1000000
	for i in 300:
		var z := ProfiledZombie.new()
		z.setup(["shambler", "runner", "soldier", "nurse", "brute"][i % 5], game.player, game.barricades, 1.0, Callable())
		game.zombies_root.add_child(z)
		z.global_position = Map.ground_pos(-28 + (i % 20) * 3, 108 + (i / 20) * 3)
		zombies.append(z)
		if "--thread-models" in OS.get_cmdline_user_args():
			z.model.process_thread_group = Node.PROCESS_THREAD_GROUP_SUB_THREAD
			z.model.process_thread_group_order = -1
	if "--dense-combat" in OS.get_cmdline_user_args():
		for z in zombies: z.hp = 1000000
		for i in 6:
			var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(-13 + i * 5, 94), 1, 0, false, DefenceTower.TYPES[i % 5])
			tower.rotation.y = PI
			tower.hp = 1000000
		await create_timer(25.0).timeout
	await measure("complete")
	for z in zombies: z.collision_mask = 1 | 8 | 16
	await measure("no_body_contacts")
	for z in zombies: z.collision_mask = 1
	await measure("world_only_contacts")
	for z in zombies: z.collision_mask = 0
	await measure("no_contacts")
	for z in zombies:
		z.collision_mask = 1 | 2 | 8 | 16
		z.set_physics_process(false)
		z.agent.avoidance_enabled = false
	await measure("animation_only")
	for z in zombies:
		for area in z._hitboxes: area.get_parent().queue_free()
		z._hitboxes.clear()
	await measure("animation_without_attachments")
	print("HORDE_CPU_DONE")
	quit(0)
func measure(label: String) -> void:
	await create_timer(1).timeout
	for z in zombies:
		z.tick_us = 0
		z.move_us = 0
		z.decision_us = 0
		z.ticks = 0
	var frame_count := 0
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 3000000:
		await process_frame
		frame_count += 1
	var ticks := 0
	var time := Vector3.ZERO
	for z in zombies:
		ticks += z.ticks
		time += Vector3(z.tick_us, z.move_us, z.decision_us)
	print("HORDE_CPU ",label," frame_ms=",float(Time.get_ticks_usec()-start)/1000.0/frame_count," per_physics_tick_ms=",time / maxf(1,ticks/300.0) / 1000.0," calls=",ticks," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000," process_ms=",Performance.get_monitor(Performance.TIME_PROCESS)*1000)
