# The online lobby without any network: join codes, credential parsing, the two transports (EOS lobby and
# direct ENet) never touching each other, the application ping, every RPC shape against the EOS P2P packet
# limit and the Multiplayer tab carrying both ways in.
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=online_lobby --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

const EOS_MAX_PACKET := 1170 - 6 # EOS_P2P_MAX_PACKET_SIZE minus the EOSGMultiplayerPeer header

# Records what SceneMultiplayer hands to the transport, so RPC sizes can be measured without a network.
class CapturePeer extends MultiplayerPeerExtension:
	var sizes: Array[int] = []
	var labels: Array[String] = []
	var label := ""
	var target := 0
	var channel := 0
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _put_packet_script(buffer: PackedByteArray) -> Error:
		sizes.append(buffer.size())
		labels.append(label)
		return OK
	func _get_packet_script() -> PackedByteArray: return PackedByteArray()
	func _get_available_packet_count() -> int: return 0
	func _get_max_packet_size() -> int: return 1 << 20
	func _get_packet_channel() -> int: return 0
	func _get_packet_mode() -> MultiplayerPeer.TransferMode: return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _set_transfer_channel(p_channel: int) -> void: channel = p_channel
	func _get_transfer_channel() -> int: return channel
	func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void: mode = p_mode
	func _get_transfer_mode() -> MultiplayerPeer.TransferMode: return mode
	func _set_target_peer(p_peer: int) -> void: target = p_peer
	func _get_packet_peer() -> int: return 0
	func _is_server() -> bool: return true
	func _poll() -> void: pass
	func _close() -> void: pass
	func _disconnect_peer(_peer: int, _force: bool) -> void: pass
	func _get_unique_id() -> int: return 1
	func _set_refuse_new_connections(_enable: bool) -> void: pass
	func _is_refusing_new_connections() -> bool: return false
	func _is_server_relay_supported() -> bool: return false
	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus: return MultiplayerPeer.CONNECTION_CONNECTED

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
	var online := root.get_node("Online")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game.settings._testing = true
	_join_codes(online)
	_credentials(online)
	await _transport_separation(net, online, game)
	await _packet_sizes(net)
	_menu(game, online)
	print("ONLINE_LOBBY_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

# ---------------------------------------------------------------- join codes and credentials
func _join_codes(online: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 200:
		var code: String = online.make_code(rng)
		seen[code] = true
		check(code.length() == 6 and online.valid_code(code), "Generated code %s has six letters from the safe alphabet" % code) if i == 0 else null
		for ch in code:
			if not ch in online.CODE_ALPHABET: check(false, "Code %s uses a character outside the alphabet" % code)
	check(seen.size() == 200, "200 generated codes are distinct")
	check(online.normalize_code(" k7pz-4m ") == "K7PZ4M", "Normalisation upper-cases and strips separators")
	check(online.normalize_code("O0I1AB") == "AB", "Ambiguous letters O, 0, I and 1 are never part of a code")
	check(not online.valid_code("ABCDE") and not online.valid_code("ABCDEFG") and online.valid_code("ABCDEF"), "A valid code has exactly six letters")
	var tag: String = online.version_tag()
	check(tag.get_slice_count("|") == 3 and tag.begins_with(str(NetSession.PROTOCOL) + "|") and tag.contains(NetSession.BUILD), "Version tag carries protocol, build and map fingerprint")

func _credentials(online: Node) -> void:
	var text := "# comment\r\nexport EOS_PRODUCT_ID = \"pid\"\r\nEOS_SANDBOX_ID='sid'\nEOS_DEPLOYMENT_ID=did # trailing comment\n\nEOS_CLIENT_ID=cid\nEOS_CLIENT_SECRET=sec=ret\n"
	var env: Dictionary = online.parse_env(text)
	check(env.get("EOS_PRODUCT_ID") == "pid" and env.get("EOS_SANDBOX_ID") == "sid" and env.get("EOS_DEPLOYMENT_ID") == "did", "Env parsing accepts export, quotes, CRLF and trailing comments")
	check(env.get("EOS_CLIENT_SECRET") == "sec=ret", "An equals sign inside a value survives")
	var creds: Dictionary = online.credentials_from_env(env)
	check(online.credentials_complete(creds) and creds.product_name == "RemZ" and creds.client_secret == "sec=ret", "Complete credentials are recognised and the product name defaults to RemZ")
	env.erase("EOS_CLIENT_ID")
	check(not online.credentials_complete(online.credentials_from_env(env)), "A missing client id makes the credentials incomplete")
	check(online.credentials_complete(online.load_credentials()) or not OS.has_feature("editor"), "The editor finds the local credentials (eos.cfg or .env)")

# ---------------------------------------------------------------- the two ways in never touch each other
func _transport_separation(net: Node, online: Node, game: Node) -> void:
	var saved_credentials: Dictionary = online.credentials
	online.force_unavailable = true
	check(not online.available() and online.unavailable_reason().contains("runtime"), "A missing runtime reports itself as unavailable")
	var result: int = await net.host_online("Offline")
	check(result == ERR_UNAVAILABLE and not net.enabled and net.transport == "offline" and not net.online_pending, "Hosting online without the runtime is refused without touching the session")
	check(net.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "The refused online host leaves the offline peer in place")
	check(net.status == online.unavailable_reason(), "The menu status explains why the online lobby is unavailable")
	result = await net.join_online("K7PZ4M", "Offline")
	check(result == ERR_UNAVAILABLE and not net.enabled, "Joining online without the runtime is refused as well")
	result = await net.join_online("k7p", "Offline")
	check(result == ERR_INVALID_PARAMETER and not net.enabled and net.status.contains("6-character"), "A short code is rejected before anything is contacted")
	online.force_unavailable = false
	online.credentials = {}
	check(not online.available() and online.unavailable_reason().contains("not configured"), "Missing credentials give a different reason than a missing runtime")
	result = await net.host_online("Offline")
	check(result == ERR_UNAVAILABLE and not net.enabled, "Hosting online without credentials is refused")
	online.credentials = saved_credentials
	online.force_unavailable = true
	# The direct path works regardless of the online lobby.
	check(net.host("Direct", 24701) == OK and net.enabled and net.is_host() and net.transport == "enet" and not net.is_online(), "ENet host opens while the online lobby is unavailable")
	check(net.peer_ping(1) == 0 and net.peer_ping(9) == -1, "Host ping is zero, an unknown peer has none")
	check(await net.host_online("Second") == ERR_BUSY and await net.join_online("K7PZ4M", "Second") == ERR_BUSY, "An open ENet session blocks the online buttons")
	net._record_pong(2, Time.get_ticks_msec())
	check(net._pings.is_empty(), "A pong from a peer outside the roster is ignored")
	net.leave()
	while net._closing: await process_frame
	check(not net.enabled and net.transport == "offline" and net.join_code.is_empty() and current_scene == game, "Leaving the ENet session resets the transport and keeps the map")
	online.leave() # no lobby, no platform: must be a no-op
	check(online.lobby == null and online.code.is_empty() and not online.active(), "Leaving without a lobby is harmless")
	# Cancelling an online attempt that is still signing in.
	net.online_pending = true
	net.join_code = "K7PZ4M"
	net.leave("Cancelled by the player.")
	check(not net.online_pending and net.join_code.is_empty() and not net.enabled and net.status == "Cancelled by the player.", "Cancel while signing in clears the pending attempt")
	check(not net._online_step_ok({"ok": true}), "A step finishing after the cancel is ignored")
	check(net.host("Direct", 24701) == OK, "ENet host works again right after the cancelled online attempt")
	net.leave()
	while net._closing: await process_frame
	# Application ping on a transport without ENet statistics.
	var capture := CapturePeer.new()
	net.multiplayer.multiplayer_peer = capture
	capture.emit_signal("peer_connected", 2)
	await process_frame
	net.enabled = true
	net.transport = "eos"
	net.roster = {1: "Host", 2: "Guest"}
	check(net.is_online() and net.peer_ping(2) == -1, "Before the first pong an online peer shows no ping")
	net._record_pong(2, Time.get_ticks_msec() - 37)
	check(net.peer_ping(2) >= 37 and net.peer_ping(2) < 1000, "The application ping measures the round trip")
	net._peer_disconnected(2)
	check(not net._pings.has(2), "A disconnect forgets the peer's ping")
	net.enabled = false
	net.transport = "offline"
	net.roster.clear()
	net.ready_peers.clear()
	net._rates.clear()
	if net.world:
		for id in net.world.actors.keys(): net.world.remove_player(id)
	net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online.force_unavailable = false
	await process_frame

# ---------------------------------------------------------------- every RPC must fit one EOS P2P packet
func _packet_sizes(net: Node) -> void:
	var capture := CapturePeer.new()
	net.multiplayer.multiplayer_peer = capture
	capture.emit_signal("peer_connected", 2)
	await process_frame
	var big_epoch := 1 << 40 # eight-byte integers: the worst case the encoder can produce
	var long_name := "WWWWWWWWWWWWWWWWWWWWWWWW" # 24 characters, the name limit
	var chunk := PackedByteArray()
	chunk.resize(net.SNAPSHOT_CHUNK)
	capture.label = "_initial_part"
	net._initial_part.rpc_id(2, big_epoch, big_epoch, 599, 600, 524288, chunk, true, true)
	capture.label = "_snapshot_part"
	net._snapshot_part.rpc_id(2, big_epoch, big_epoch, 63, 64, 524288, chunk)
	capture.label = "_lobby"
	net._lobby.rpc(big_epoch, {1: long_name, 2: long_name, 3: long_name, 4: long_name}, {1: true, 2: true, 3: false, 4: false}, "running")
	capture.label = "_welcome"
	net._welcome.rpc_id(2, big_epoch, {1: long_name, 2: long_name, 3: long_name, 4: long_name}, "running", 3)
	capture.label = "_feedback"
	var text := ""
	for i in 40: text += "Wörter "
	net._feedback.rpc_id(2, big_epoch, "message", [Lang.t("%s unlocked. Achievements stay saved; progress and rewards count per round. In multiplayer you reach the goals together as a team.", [Lang.raw(text)]), 5.0])
	capture.label = "_leaderboard_live"
	net._leaderboard_live.rpc(big_epoch, {2: {"id": 2, "name": long_name, "connected": true, "kills": 99999, "headshots": 99999, "deaths": 99999, "titan_kills": 99999, "assists": 99999, "score": 9999999, "ping_ms": 999}})
	capture.label = "_ping"
	net._ping.rpc_id(2, big_epoch, Time.get_ticks_msec() + (1 << 40))
	capture.label = "_titan_cue"
	net._titan_cue.rpc_id(2, big_epoch, "slam_warning", Vector3(1000, 20, 1000), 27.5, 4, 999999)
	capture.label = "_shot"
	net._shot.rpc(big_epoch, 2, "graviton_cannon", [-8.0, 1.0, 0.5, "plasma"])
	await process_frame
	check(capture.sizes.size() >= 9, "Every RPC shape reached the transport (%d packets)" % capture.sizes.size())
	var largest := 0
	var largest_label := ""
	for i in capture.sizes.size():
		if capture.sizes[i] > largest:
			largest = capture.sizes[i]
			largest_label = capture.labels[i]
	print("RPC_PACKETS largest=%d bytes (%s) limit=%d" % [largest, largest_label, EOS_MAX_PACKET])
	check(largest <= EOS_MAX_PACKET, "The largest RPC packet (%d bytes, %s) fits the EOS P2P limit of %d" % [largest, largest_label, EOS_MAX_PACKET])
	# The first RPC to a node is preceded by a small path-confirmation packet, so judge the largest per label.
	for label in ["_initial_part", "_snapshot_part"]:
		var biggest := 0
		for i in capture.sizes.size():
			if capture.labels[i] == label: biggest = maxi(biggest, capture.sizes[i])
		check(biggest >= net.SNAPSHOT_CHUNK, "%s carries the whole %d-byte chunk (%d bytes)" % [label, net.SNAPSHOT_CHUNK, biggest])
	net._rates.clear()
	net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	await process_frame

# ---------------------------------------------------------------- the Multiplayer tab
func _menu(game: Node, online: Node) -> void:
	var hud = game.hud
	hud.show_tab("multiplayer")
	var menu: Node = hud._tabs["multiplayer"].get_child(0)
	check(menu.mode_tabs is TabBar and menu.mode_tabs.tab_count == 2, "The tab offers the online lobby and the direct connection")
	check(menu.create_button.text == "Create lobby" and menu.join_code_button.text == "Join with code" and menu.code_edit is LineEdit, "The online section has its own buttons and the code field")
	check(menu.host_button.text == "Host game" and menu.join_button.text == "Join" and menu.ip_edit is LineEdit and menu.port_edit is SpinBox, "The direct section keeps IP, port, host and join")
	menu._set_mode("direct")
	check(menu.direct_box.visible and not menu.online_box.visible and menu.mode_tabs.current_tab == 1, "Direct mode shows the IP form only")
	menu._set_mode("online")
	check(menu.online_box.visible and not menu.direct_box.visible and menu.mode_tabs.current_tab == 0, "Online mode shows the lobby form only")
	menu.refresh()
	check(not menu.code_panel.visible and menu.host_button.disabled == false and menu.create_button.disabled == (not online.available()), "Without a session the code panel is hidden and the buttons follow availability")
	online.force_unavailable = true
	menu.refresh()
	check(menu.create_button.disabled and menu.join_code_button.disabled and menu.online_note.visible and not menu.host_button.disabled, "An unavailable runtime greys out only the online buttons")
	online.force_unavailable = false
	menu.refresh()
	check(menu.leave_button.visible == false and menu.start_button.visible == false, "Start and leave stay hidden outside a session")
