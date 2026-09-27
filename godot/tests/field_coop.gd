extends SceneTree
var game: Node3D
var net: Node
var role := "host"
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var folder := "res://../artifacts/field-coop/"
func _initialize() -> void:
	if not OS.get_environment("REMZ_FIELD_TEST_DIR").is_empty(): folder = OS.get_environment("REMZ_FIELD_TEST_DIR").path_join("") + "/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--field-role="): role = arg.get_slice("=", 1)
	call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 210000: quit(1)
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)
func write(id: String, data: Dictionary) -> void:
	FileAccess.open(folder + id + ".json", FileAccess.WRITE).store_string(JSON.stringify(data))
func read(id: String) -> Dictionary:
	if not FileAccess.file_exists(folder + id + ".json"): return {}
	return JSON.parse_string(FileAccess.get_file_as_string(folder + id + ".json"))
func run() -> void:
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if role == "host": await host_run()
	else: await client_run()
func inspect(step: int, peers: Array, active: bool) -> void:
	write("step", {"id": step, "peers": peers, "seq": net._sequence + 3})
	var deadline := Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < deadline:
		var done := true
		for peer in peers:
			if int(read(peer).get("step", -1)) != step: done = false
		if done: break
		await create_timer(0.1).timeout
	for peer in peers:
		var s := read(peer)
		check(int(s.get("step", -1)) == step and s.get("active", not active) == active, "%s receives trial state %d" % [peer, step])
		check(s.get("inside", false), "%s is teleported inside the field" % peer)
		check(int(s.get("bosses", -1)) == (7 if active else 0), "%s receives all seven bosses / skip cleanup" % peer)
		check(int(s.get("sandbag", -1)) == 3, "%s receives upgraded sandbags" % peer)
func host_run() -> void:
	check(net.host("field-host", 24739) == OK, "ENet host starts")
	write("ready", {})
	while net.roster.size() < 2 or false in net.ready_peers.values(): await create_timer(0.1).timeout
	net.start_game()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.waves.wave = 19
	game.waves.completed = 19
	game.field_trials.begin(20)
	game.field_trials.countdown = 0
	while not game.field_trials.pending.is_empty(): await process_frame
	for z in game.field_trials.enemies: z.set_physics_process(false)
	game.sandbags[0].build()
	game.sandbags[0].build()
	game.sandbags[0].build()
	await inspect(1, ["client"], true)
	var remote: Player
	for id in net.world.actors:
		if id != 1: remote = net.world.actors[id]
	var before := remote.global_position
	net.world.move_player(remote.peer_id, Map.ground_pos(0, 0), 0, 0, false, Vector3.ZERO, net._elapsed + 0.1, 99999)
	check(remote.global_position.is_equal_approx(before), "Host rejects an escape packet")
	write("late", {})
	while net.roster.size() < 3 or false in net.ready_peers.values(): await create_timer(0.1).timeout
	await inspect(2, ["client", "late"], true)
	game.field_trials.finish(true)
	await inspect(3, ["client", "late"], false)
	write("finish", {"failures": failures})
	await create_timer(1).timeout
	net.leave()
	print("FIELD_COOP_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
func client_run() -> void:
	while not FileAccess.file_exists(folder + ("late" if role == "late" else "ready") + ".json"): await create_timer(0.1).timeout
	check(net.join("127.0.0.1", role, 24739) == OK, "ENet client joins")
	var seen := 0
	while not FileAccess.file_exists(folder + "finish.json"):
		await create_timer(0.1).timeout
		var request := read("step")
		if request.is_empty() or int(request.id) <= seen or role not in request.peers or net._received_sequence < int(request.seq): continue
		seen = int(request.id)
		game.player.set_physics_process(false)
		var bosses := 0
		for z in game.zombies_root.get_children():
			if z is Zombie and z.alive and z.replica: bosses += 1
		var point := Vector2(game.player.global_position.x, game.player.global_position.z)
		write(role, {"step": seen, "active": game.field_trials.active, "inside": FieldTrials.FIELD.has_point(point), "bosses": bosses, "sandbag": game.sandbags[0].level})
	net.leave()
	print("FIELD_CLIENT_DONE ", role)
	quit()
