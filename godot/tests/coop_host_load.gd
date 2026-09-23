# Rendered host frame pacing while carrying a four-player round: the horde, three remote avatars
# and the ten-per-second snapshot work all land in the same frames the host has to draw.
# Godot.exe --path godot --resolution 1600x900 --script res://tests/run.gd -- \
#   --suite=coop_host_load --smoke-test --no-intro --no-music
extends SceneTree

var game: Node3D
var net: Node
var checks := 0
var failures := 0
var samples: Array[float] = []
var collecting := false
var previous := 0
var snapshot_t := 0.0
var snapshot_us := 0
var snapshot_ticks := 0
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if collecting:
		if previous > 0: samples.append((now - previous) / 1000.0)
		# Mirror the host's real snapshot cadence; without peers NetSession would skip it.
		snapshot_t += delta
		if snapshot_t >= 0.1:
			snapshot_t = 0.0
			var start := Time.get_ticks_usec()
			var raw := var_to_bytes(net.world.snapshot())
			var _packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
			snapshot_us += Time.get_ticks_usec() - start
			snapshot_ticks += 1
	previous = now
	if Time.get_ticks_msec() - began > 300000:
		push_error("COOP_HOST_LOAD_TIMEOUT")
		quit(1)
	return false

func stats(label: String) -> Dictionary:
	var total := 0.0
	var over_33 := 0
	var over_50 := 0
	for value in samples:
		total += value
		if value > 1000.0 / 30.0: over_33 += 1
		if value > 50.0: over_50 += 1
	var sorted := samples.duplicate()
	sorted.sort()
	var report := {
		"stage": label, "frames": sorted.size(), "average_fps": sorted.size() * 1000.0 / maxf(total, 0.001),
		"p95_ms": sorted[int(sorted.size() * 0.95)], "p99_ms": sorted[int(sorted.size() * 0.99)],
		"max_ms": sorted.back(), "over_33ms": over_33, "over_50ms": over_50,
		"alive": game.alive_zombies(),
		"snapshot_ms": (snapshot_us / 1000.0 / maxi(snapshot_ticks, 1)),
	}
	print("COOP_HOST_LOAD_STAGE ", JSON.stringify(report))
	return report

func collect(seconds: float) -> Dictionary:
	await process_frame
	samples.clear()
	snapshot_us = 0
	snapshot_ticks = 0
	previous = Time.get_ticks_usec()
	collecting = true
	await create_timer(seconds).timeout
	collecting = false
	return stats("four_players_full_horde")

func run() -> void:
	seed(4242)
	if DisplayServer.get_name() == "headless":
		push_error("Coop host load needs a rendered window.")
		quit(1)
		return
	net = root.get_node("NetSession")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	# host() refuses once the round is running, so open the session before starting it.
	check(net.host("Host", 24696) == OK, "Rendered host carries the load fixture")
	if not net.is_host():
		quit(1)
		return
	for id in [2, 3, 4]:
		net.roster[id] = "Mitspieler %d" % id
		net.world.add_player(id)
	net._begin(net.epoch, false)
	check(net.world.actors.size() == 4, "Four players share the rendered round")
	game.player.max_hp = 1000000
	game.player.hp = 1000000
	game.hut.hp = 1000000
	game.player.global_position = Map.ground_pos(0, 85) + Vector3.UP * 0.2
	game.player.camera.look_at(Map.ground_pos(0, 110) + Vector3.UP)
	# Keep the wave director quiet so the measured horde size stays fixed.
	game.waves.set_process(false)
	for i in Waves.MAX_ACTIVE:
		game.spawn_zombie(["shambler", "runner", "soldier", "nurse", "brute"][i % 5],
			Vector2(-28 + (i % 20) * 3, 100 + float(i / 20) * 3), 1.0)
		if i % 12 == 0: await process_frame
	for z in game.zombies_root.get_children():
		if z is Zombie: z.hp = 1000000.0
	await create_timer(2.0).timeout
	check(game.alive_zombies() >= Waves.MAX_ACTIVE, "Full horde walks at the rendered host")

	var report := await collect(15.0)
	check(report.average_fps > 60.0, "Host holds above 60 FPS (measured %.0f)" % report.average_fps)
	check(report.p99_ms < 33.0, "99%% of frames stay under 33 ms (measured %.1f ms)" % report.p99_ms)
	check(report.over_50ms == 0, "No frame exceeds 50 ms (measured %d)" % report.over_50ms)
	check(report.snapshot_ms < 4.0, "Snapshot tick stays under 4 ms (measured %.2f ms)" % report.snapshot_ms)

	var output := FileAccess.open("res://../logs/coop-host-load.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"resolution": str(root.size), "stage": report}, "\t"))
	output.close()
	print("COOP_HOST_LOAD_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
