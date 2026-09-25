# Two real processes over EOS P2P: the host opens an online lobby, the client joins by code, the round runs,
# snapshots, movement, ping and a clean leave travel over the EOS peer. tools/test_online_coop.ps1 starts both
# (the client with --eos-fresh-device, so two identities exist on one PC) and coordinates through
# artifacts/online/. Internet access and the local EOS credentials are required.
# --suite=online_coop --online-role=host|client --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var role := "host"
var folder := ProjectSettings.globalize_path("res://../artifacts/online/")
var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()
var game: Node
var net: Node

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online-role="): role = arg.trim_prefix("--online-role=")
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 300000:
		push_error("ONLINE_COOP_TIMEOUT " + role)
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func write_json(name: String, data: Variant) -> void:
	var file := FileAccess.open(folder + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func read_json(name: String) -> Variant:
	if not FileAccess.file_exists(folder + name + ".json"): return null
	return JSON.parse_string(FileAccess.get_file_as_string(folder + name + ".json"))

func wait_for(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await create_timer(0.1, true).timeout
	return bool(condition.call())

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game.settings._testing = true
	if not root.get_node("Online").available():
		print("ONLINE_COOP_SKIPPED reason=", Lang.resolve(root.get_node("Online").unavailable_reason(), "en"))
		quit(3)
		return
	if role == "host": await host_run()
	else: await client_run()

func host_run() -> void:
	var result: int = await net.host_online("OnlineHost")
	check(result == OK and net.is_online(), "Host opens the online lobby (%s)" % Lang.resolve(net.status, "en"))
	if result != OK:
		print("ONLINE_COOP_DONE checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	write_json("code", {"code": net.join_code})
	print("ONLINE_CODE=", net.join_code)
	check(await wait_for(func(): return net.roster.size() == 2 and not false in net.ready_peers.values(), 150.0), "The client joins by code over EOS P2P and loads the map")
	if net.roster.size() != 2:
		write_json("step", {"action": "abort"})
		print("ONLINE_COOP_DONE checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var client_id := 0
	for id in net.roster:
		if id != 1: client_id = id
	check(net.roster[client_id] == "OnlineClient", "The client's name arrived through the hello handshake")
	net.start_game()
	check(await wait_for(func(): return net.phase == "running" and game.started, 20.0), "The round starts for the host")
	game.waves.timer = 10000.0
	game.player.set_physics_process(false)
	check(await wait_for(func(): return net.peer_ping(client_id) >= 0, 8.0), "The application ping measures the client (%d ms)" % net.peer_ping(client_id))
	var actor: Node3D = net.world.actor(client_id)
	var before: Vector3 = actor.global_position
	write_json("step", {"action": "walk"})
	check(await wait_for(func(): return actor.global_position.distance_to(before) > 1.0, 15.0), "Client movement replicates through the host over EOS (%.1f m)" % actor.global_position.distance_to(before))
	check(net._sequence > 5, "The host keeps streaming snapshots (%d)" % net._sequence)
	write_json("step", {"action": "inspect"})
	check(await wait_for(func(): return read_json("client") != null and read_json("client").get("step") == "inspect", 20.0), "The client reports back")
	var report = read_json("client")
	if report is Dictionary:
		check(bool(report.get("running", false)) and int(report.get("players", 0)) == 2 and int(report.get("received", 0)) > 10, "The client runs the round with two players and receives snapshots (%s)" % JSON.stringify(report))
		check(str(report.get("transport", "")) == "eos" and str(report.get("peer_class", "")) == "EOSGMultiplayerPeer", "The client plays over the EOS peer")
	write_json("step", {"action": "finish"})
	check(await wait_for(func(): return net.roster.size() == 1, 30.0), "The client's leave reaches the host as a peer disconnect")
	net.leave("Online test finished")
	while net._closing: await process_frame
	check(not net.enabled and net.transport == "offline", "The host leaves and the transport is offline again")
	print("ONLINE_COOP_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func client_run() -> void:
	check(await wait_for(func(): return read_json("code") != null, 120.0), "The host published a join code")
	var code := str(read_json("code").get("code", ""))
	var result: int = await net.join_online(code, "OnlineClient")
	check(result == OK and net.enabled and net.transport == "eos", "Client finds the lobby by code and opens the EOS peer (%s)" % Lang.resolve(net.status, "en"))
	if result != OK:
		print("ONLINE_CLIENT_DONE checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	check(await wait_for(func(): return is_instance_valid(net.game) and net.phase == "running" and net.game.started, 150.0), "Client is welcomed and the round starts (%s)" % Lang.resolve(net.status, "en"))
	game = net.game
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	var seen := ""
	while true:
		await create_timer(0.1, true).timeout
		var step = read_json("step")
		if not step is Dictionary or str(step.get("action", "")) == seen: continue
		seen = str(step.get("action", ""))
		match seen:
			"walk":
				game.player.set_physics_process(true)
				Input.action_press("move_forward")
				await create_timer(0.9, true).timeout
				Input.action_release("move_forward")
				await create_timer(0.2, true).timeout
				game.player.set_physics_process(false)
			"inspect":
				write_json("client", {"step": "inspect", "running": net.phase == "running" and game.started, "players": net.roster.size(), "received": net._received_sequence, "transport": net.transport, "peer_class": net.multiplayer.multiplayer_peer.get_class()})
			"finish", "abort":
				net.leave("Online test finished")
				while net._closing: await process_frame
				check(not net.enabled and net.transport == "offline", "The client leaves cleanly")
				print("ONLINE_CLIENT_DONE checks=%d failures=%d" % [checks, failures])
				quit(0 if failures == 0 else 1)
				return
