# Host cost of one snapshot tick under a full horde: serialize, pack and compress run on the
# main thread ten times a second, so a slow tick shows up as a periodic hitch for everyone.
# --suite=coop_snapshot_cost --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var game: Node3D
var net: Node
var checks := 0
var failures := 0

# One tick has to stay well inside a 60 FPS frame; the horde itself still needs that frame.
const BUDGET_MS := 4.0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func measure(samples: int) -> Dictionary:
	var build_us := 0
	var pack_us := 0
	var zip_us := 0
	var worst_us := 0
	var raw_size := 0
	var packed_size := 0
	for i in samples:
		var t0 := Time.get_ticks_usec()
		var data: Dictionary = net.world.snapshot()
		var t1 := Time.get_ticks_usec()
		var raw := var_to_bytes(data)
		var t2 := Time.get_ticks_usec()
		var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
		var t3 := Time.get_ticks_usec()
		build_us += t1 - t0
		pack_us += t2 - t1
		zip_us += t3 - t2
		worst_us = maxi(worst_us, t3 - t0)
		raw_size = raw.size()
		packed_size = packed.size()
	return {
		"build_ms": build_us / 1000.0 / samples, "pack_ms": pack_us / 1000.0 / samples,
		"zip_ms": zip_us / 1000.0 / samples, "total_ms": (build_us + pack_us + zip_us) / 1000.0 / samples,
		"worst_ms": worst_us / 1000.0, "raw_kb": raw_size / 1024.0, "packed_kb": packed_size / 1024.0,
	}

func report(label: String, result: Dictionary) -> void:
	print("SNAPSHOT_COST %s total=%.2fms (build %.2f, pack %.2f, zip %.2f) worst=%.2fms raw=%.1fkB packed=%.1fkB" % [
		label, result.total_ms, result.build_ms, result.pack_ms, result.zip_ms,
		result.worst_ms, result.raw_kb, result.packed_kb])

func run() -> void:
	seed(4242)
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	check(net.host("Host", 24694) == OK, "Snapshot cost fixture hosts a round")
	if not net.is_host():
		quit(1)
		return
	for id in [2, 3, 4]:
		net.roster[id] = "Mitspieler %d" % id
		net.world.add_player(id)
	net._begin(net.epoch, false)
	game.waves.set_process(false)
	check(net.world.actors.size() == 4, "Four players share the measured round")

	var solo := measure(40)
	report("4players_no_horde", solo)

	# A boss wave is the worst realistic case: MAX_ACTIVE zombies plus a titan.
	for i in Waves.MAX_ACTIVE:
		game.spawn_zombie(["shambler", "runner", "soldier", "nurse", "brute"][i % 5],
			Vector2(-28 + (i % 20) * 3, 108 + float(i / 20) * 3), 1.0)
		if i % 12 == 0: await process_frame
	game.spawn_zombie("titan", Vector2(0, 120), 1.0)
	await process_frame
	for z in game.zombies_root.get_children():
		if z is Zombie:
			z.set_physics_process(false)
			z.hp = 1000000.0
	var alive: int = game.zombies_root.get_children().filter(func(n): return n is Zombie).size()
	check(alive >= Waves.MAX_ACTIVE, "Full horde of %d zombies stands in the measured snapshot" % alive)

	var horde := measure(40)
	report("4players_full_horde", horde)

	check(horde.total_ms < BUDGET_MS, "Full-horde snapshot tick stays under %.1f ms (measured %.2f ms)" % [BUDGET_MS, horde.total_ms])
	check(horde.worst_ms < BUDGET_MS * 2.0, "Worst snapshot tick stays under %.1f ms (measured %.2f ms)" % [BUDGET_MS * 2.0, horde.worst_ms])
	# Ten ticks a second must not eat a noticeable share of the host's CPU time.
	var share: float = horde.total_ms * 10.0 / 1000.0 * 100.0
	print("SNAPSHOT_COST cpu_share=%.1f%% of one second at 10 Hz" % share)
	check(share < 10.0, "Snapshot work stays under 10%% of host CPU time (measured %.1f%%)" % share)

	print("COOP_SNAPSHOT_COST_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
