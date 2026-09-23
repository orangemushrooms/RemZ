extends SceneTree

var game: Node3D
var net: Node
var role := "host"
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var folder := "res://../artifacts/earthworm-coop/"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--worm-role="): role = arg.trim_prefix("--worm-role=")
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 210000:
		push_error("EARTHWORM_COOP_TIMEOUT " + role)
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1

func write(name: String, value: Dictionary) -> void:
	FileAccess.open(folder + name + ".json", FileAccess.WRITE).store_string(JSON.stringify(value))

func read(name: String) -> Dictionary:
	if not FileAccess.file_exists(folder + name + ".json"): return {}
	return JSON.parse_string(FileAccess.get_file_as_string(folder + name + ".json"))

func run() -> void:
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if role == "host": await host_run()
	else: await client_run()

func inspect_clients(step: int, peers: Array, phase: String) -> void:
	write("step", {"step": step, "phase": phase, "peers": peers, "sequence": net._sequence + 2})
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var done := true
		for peer in peers:
			if read(peer).get("step", -1) != step: done = false
		if done: break
		await create_timer(0.1).timeout
	for peer in peers:
		var data := read(peer)
		check(data.get("step", -1) == step and data.get("phase", "") == phase and data.get("replica", false), "%s receives authoritative %s worm" % [peer, phase])
		check(data.get("anim", false) and data.get("height", 0) == 14, "%s receives model, scale and animation" % peer)
		check(data.get("targetable", false) == (phase in ["windup", "recovery"]), "%s receives matching hitability" % peer)
		check(data.get("cue", -1) == 1, "%s hears or acknowledges exactly one arrival cue" % peer)
		if phase == "recovery": check(data.get("clip", "") == "recovery", "%s renders the recovery clip after the strike" % peer)
		if peer == "late" and step == 2: check(not data.get("playing", true), "Late join does not replay an old spawn recording")

func host_run() -> void:
	check(net.host("worm-host", 24736) == OK, "Host opens ENet")
	if not net.enabled:
		quit(1)
		return
	write("ready", {"ready": true})
	while net.roster.size() < 2 or false in net.ready_peers.values(): await create_timer(0.1).timeout
	net.start_game()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.waves.wave = 12
	game.spawn_zombie("earthworm", Vector2(10, 126), 1.3, "south")
	var worm: Earthworm = game.zombies_root.get_children().back()
	worm.set_physics_process(false)
	await process_frame
	worm.strike_point = Map.ground_pos(10, 118)
	worm._set_phase("windup", Earthworm.WINDUP_TIME)
	await inspect_clients(1, ["client"], "windup")
	write("join-late", {"ready": true})
	while net.roster.size() < 3 or false in net.ready_peers.values(): await create_timer(0.1).timeout
	await inspect_clients(2, ["client", "late"], "windup")
	worm._set_phase("recovery", Earthworm.RECOVERY_TIME)
	await inspect_clients(3, ["client", "late"], "recovery")
	worm._set_phase("burrow", Earthworm.BURROW_TIME)
	worm.global_position += Vector3(3, 0, 2)
	await inspect_clients(4, ["client", "late"], "burrow")
	worm.die(Vector3.ZERO)
	await inspect_clients(5, ["client", "late"], "death")
	check(game.alive_zombies() == 0, "Host releases the dead worm from wave counter")
	write("finish", {"failures": failures})
	await create_timer(1.0).timeout
	net.leave()
	print("EARTHWORM_COOP_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func client_run() -> void:
	while read("join-late" if role == "late" else "ready").is_empty(): await create_timer(0.1).timeout
	check(net.join("127.0.0.1", role, 24736) == OK, "Client joins ENet")
	var seen := 0
	while read("finish").is_empty():
		await create_timer(0.1).timeout
		var request := read("step")
		if request.is_empty() or int(request.step) <= seen or not role in request.peers: continue
		if net._received_sequence < int(request.sequence): continue
		var worm: Earthworm
		for enemy in game.zombies_root.get_children():
			if enemy is Earthworm: worm = enemy
		if not worm: continue
		seen = int(request.step)
		game.player.set_physics_process(false)
		write(role, {"step": seen, "phase": worm.phase, "replica": worm.replica, "height": worm.height, "anim": worm.anim != null and worm.anim.has_animation("attack"), "clip": worm.anim.current_animation if worm.anim else "", "targetable": worm.targetable(), "cue": worm._heard_cue, "playing": worm._voice.playing})
	net.leave()
	print("EARTHWORM_CLIENT_DONE ", role)
	quit()
