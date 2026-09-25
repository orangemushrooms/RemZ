# Talks to the real EOS backend with the local credentials (internet required): platform start, anonymous
# Device ID login, a lobby with join code, the search by code (and its version and not-found answers),
# NetSession hosting over the EOS peer, leaving, and the lobby being gone afterwards. Prints ONLINE_LIVE_DONE,
# or ONLINE_LIVE_SKIPPED with exit code 3 when the runtime or the credentials are missing on this machine.
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=online_live --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("ONLINE_LIVE_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var net := root.get_node("NetSession")
	var online := root.get_node("Online")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game.settings._testing = true
	if not online.available():
		print("ONLINE_LIVE_SKIPPED reason=", Lang.resolve(online.unavailable_reason(), "en"))
		quit(3)
		return
	var signed_in: Dictionary = await online.ensure_ready("LiveTest")
	check(signed_in.ok, "Platform starts and the device signs in anonymously (%s)" % Lang.resolve(str(signed_in.get("error", "")), "en"))
	if not signed_in.ok:
		print("ONLINE_LIVE_DONE checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	check(online.state == "ready" and not online.product_user_id.is_empty(), "A product user id is known after the login")
	var local_user: String = str(ClassDB.class_call_static("EOSGMultiplayerPeer", "get_local_user_id"))
	check(local_user == online.product_user_id, "The P2P peer knows the same local user")
	# host through NetSession, exactly like the menu button
	var result: int = await net.host_online("LiveHost")
	check(result == OK and net.enabled and net.is_host() and net.transport == "eos" and net.is_online(), "NetSession hosts over the EOS peer")
	check(online.valid_code(net.join_code) and online.code == net.join_code, "A join code is issued and shown")
	check(net.multiplayer.multiplayer_peer.get_class() == "EOSGMultiplayerPeer" and net.multiplayer.is_server() and net.local_id() == 1, "The active MultiplayerPeer is the EOS P2P peer with the host as peer 1")
	check(online.lobby != null and online.lobby.is_valid() and online.is_owner() and int(online.lobby.max_members) == net.MAX_PLAYERS, "The lobby exists, we own it and it takes four players")
	check(str(online.lobby.get_attribute(online.ATTR_CODE).get("value", "")) == net.join_code and str(online.lobby.get_attribute(online.ATTR_VERSION).get("value", "")) == online.version_tag(), "The lobby advertises the code and our version tag")
	check(net.status.contains(net.join_code) or Lang.text(net.status).contains(net.join_code), "The status line shows the join code")
	var found: Dictionary = await online.find_lobby(net.join_code)
	check(found.ok and found.host_name == "LiveHost", "The search by code finds the lobby with the host name (%s)" % Lang.resolve(str(found.get("error", "")), "en"))
	var wrong: Dictionary = await online.find_lobby("ZZZZZZ")
	check(not wrong.ok and Lang.resolve(str(wrong.error), "en").begins_with("No open lobby"), "An unknown code is reported as not found")
	var changed: Dictionary = await online._apply_attributes(str(online.lobby.lobby_id), {online.ATTR_VERSION: "0|other-build|000000000000"})
	check(changed.ok, "The version attribute can be rewritten for the test")
	var mismatch: Dictionary = await online.find_lobby(net.join_code)
	check(not mismatch.ok and Lang.resolve(str(mismatch.error), "en").begins_with("The host runs a different RemZ version"), "A lobby of another build is refused with the version message")
	changed = await online._apply_attributes(str(online.lobby.lobby_id), {online.ATTR_VERSION: online.version_tag()})
	check(changed.ok, "The version attribute is restored")
	var lobby_code: String = net.join_code
	net.leave("Live test finished")
	while net._closing: await process_frame
	check(not net.enabled and net.transport == "offline" and net.join_code.is_empty() and net.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "Leaving closes the EOS peer and resets the transport")
	check(online.lobby == null and online.code.is_empty() and not online.active(), "Leaving drops the lobby locally")
	await create_timer(3.0, true).timeout
	var gone: Dictionary = await online.find_lobby(lobby_code)
	check(not gone.ok, "The destroyed lobby is no longer found")
	result = await net.join_online(lobby_code, "LiveGuest")
	check(result == FAILED and not net.enabled and Lang.resolve(net.status, "en").begins_with("No open lobby"), "Joining the destroyed lobby fails cleanly with the not-found message")
	check(online.state == "ready" and net.transport == "offline" and current_scene == game, "The failed join leaves the platform ready and the map loaded")
	var log := FileAccess.get_file_as_string(net.diagnostic_path)
	check(log.contains("EOS_PLATFORM_READY") and log.contains("EOS_LOGIN_OK") and log.contains("EOS_LOBBY_CREATED") and log.contains("EOS_LOBBY_DESTROY"), "The diagnostics file records platform, login, lobby and teardown")
	check(not log.contains(str(online.credentials.get("client_secret", "~"))), "The client secret never reaches the diagnostics file")
	print("ONLINE_LIVE_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
