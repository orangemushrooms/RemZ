extends SceneTree
class Corpse extends Zombie:
	func _ready() -> void: pass

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func run() -> void:
	var waves := Waves.new()
	for n in [1, 2, 3, 4, 7]: check(waves.regular_count(n) == 10 + n * 5, "Early ordinary wave %d keeps original size" % n)
	check(waves.regular_count(12) < roundi(70 * Waves.army_multiplier(12)), "Worm introduction replaces part of the horde budget")
	for n in range(8, 51):
		var plan := waves.plan(n)
		check(plan.size() == waves.preview_count(n), "Wave %d preview matches actual encounter plan" % n)
	check(Waves.army_multiplier(100) == 2.5, "Multiplier stays bounded in very late waves")
	waves.wave = 22
	waves._frame_time = 1.0 / 60
	check(waves.active_limit() == 72 and is_equal_approx(waves.spawn_interval(), 0.22), "Army reinforcements accelerate with a bounded live population")
	waves._frame_time = 1.0 / 40
	check(waves.active_limit() == 56, "Moderate frame pressure lowers reinforcement ceiling")
	waves._frame_time = 1.0 / 25
	check(waves.active_limit() == 40 and waves.spawn_interval() > 0.22, "Heavy frame pressure also slows spawning")
	waves.free()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	# Lightweight corpses exercise the real cleanup, including externally parented decals.
	var pools: Array[Decal] = []
	for i in 40:
		var corpse := Corpse.new()
		corpse.set_physics_process(false)
		corpse.alive = false
		corpse.dead_t = i
		game.zombies_root.add_child(corpse)
		corpse._pool = Decal.new()
		game.add_child(corpse._pool)
		pools.append(corpse._pool)
	var living := Corpse.new()
	living.set_physics_process(false)
	game.zombies_root.add_child(living)
	game.waves.trim_corpses()
	await process_frame
	check(game.zombies_root.get_child_count() == 25 and is_instance_valid(living), "Corpse cleanup bounds dead actors without removing living enemies")
	var remaining := 0
	for pool in pools:
		if is_instance_valid(pool): remaining += 1
	check(remaining == 24, "Corpse cleanup also removes external blood decals")
	if "--army-benchmark" in OS.get_cmdline_user_args():
		for z in game.zombies_root.get_children():
			if is_instance_valid(z._pool): z._pool.queue_free()
			z.queue_free()
		await process_frame
		game.player.global_position = Map.ground_pos(0, 100)
		game.player.camera.look_at(Map.ground_pos(0, 75) + Vector3.UP)
		game.player.hp = 10000
		game.player.max_hp = 10000
		for i in Waves.MAX_ACTIVE:
			game.spawn_zombie(["shambler", "runner", "soldier", "nurse", "brute"][i % 5], Vector2(-12 + (i % 12) * 2, 65 + (i / 12) * 2), 1.6, "east")
			await process_frame
		check(game.alive_zombies() == Waves.MAX_ACTIVE, "Rendered benchmark reaches full live-enemy budget")
		await create_timer(3).timeout
		var samples: Array[float] = []
		var began := Time.get_ticks_usec()
		var previous_tick := began
		while Time.get_ticks_usec() - began < 6000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - previous_tick) / 1000.0)
			previous_tick = now
		var average := float(Time.get_ticks_usec() - began) / 1000.0 / samples.size()
		samples.sort()
		print("ARMY_BENCHMARK enemies=%d avg_fps=%.1f p95_ms=%.2f max_ms=%.2f" % [game.alive_zombies(), 1000.0 / average, samples[int(samples.size() * 0.95)], samples.back()])
	print("ARMY_WAVES_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
