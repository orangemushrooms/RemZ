extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var net := root.get_node("NetSession")
	check(not net.diagnostic_path.is_empty() and FileAccess.get_file_as_string(net.diagnostic_path).contains("BOOT"), "Diagnostic file exists before any connection attempt")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game.settings._testing = true
	for attempt in 3:
		check(net.join("127.0.0.1", "Cancellation", 24699) == OK, "Start connection to an absent host")
		await create_timer(0.1, true).timeout
		var start := Time.get_ticks_msec()
		net.leave("Cancelled")
		net.leave("Duplicate cancellation")
		while net._closing: await process_frame
		check(Time.get_ticks_msec() - start < 1000, "Cancel returns within one second")
		check(is_instance_valid(game) and current_scene == game and net.game == game and game.navigation_ready, "Cancel preserves the already loaded map")
		check(not net.enabled and net.phase == "offline" and net.roster.is_empty() and net.world.actors.is_empty(), "Cancellation leaves a clean offline lobby")
	check(net.join("127.0.0.1", "Timeout", 24699) == OK, "Connection can be retried after cancellation")
	net._connect_t = 0.05
	await create_timer(0.3, true).timeout
	check(not net.enabled and not net._closing and current_scene == game, "Connection timeout does not reload or freeze the map")
	check(net.join("127.0.0.1", "Failure", 24699) == OK, "Connection can be retried after timeout")
	get_multiplayer().connection_failed.emit()
	await process_frame
	await process_frame
	check(not net.enabled and not net._closing and current_scene == game, "Failure signal safely detaches ENet outside its callback")
	check(net.host("Recovered", 24699) == OK, "Host can be created after repeated failed joins")
	net.leave()
	await process_frame
	await process_frame
	check(not net.enabled and current_scene == game, "Leaving an unstarted host also preserves the map")
	var log := FileAccess.get_file_as_string(net.diagnostic_path)
	check(log.contains("JOIN_BEGIN") and log.contains("JOIN_SOCKET") and log.contains("LEAVE_PEER_CLOSED") and log.contains("LEAVE_DONE"), "Connection and cancellation stages are immediately readable from disk")
	print("CONNECTION_CANCEL_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
