extends SceneTree

# Use the production NetSession RPCs with tiny map fixtures: no terrain or graphics
# are needed to verify version rejection and the complete initial-state handshake.
class TestMap:
	extends Node3D
	var navigation_ready := true
	var started := false
	var stats := {"players": {}}
	var player := {"peer_id": 1}
	var settings := {"difficulty": 1}
	var campaign := {"selected_id": "forest"}
	var difficulty: Dictionary = {}

class TestWorld:
	extends RefCounted
	var actors: Dictionary = {}
	var state_loaded := false
	func add_player(id: int) -> void: actors[id] = true
	func remove_player(id: int) -> void: actors.erase(id)
	func sync_roster() -> void: pass
	func check_team() -> void: pass
	func make_client() -> void: pass
	func snapshot() -> Dictionary: return {"handshake_marker": "expedition-protocol", "players": actors}
	func apply_snapshot(data: Dictionary, _initial: bool) -> void:
		state_loaded = data.get("handshake_marker") == "expedition-protocol" and data.get("players", {}).size() == 2

var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var host := false
var case_name := ""
var folder := ""

func _initialize() -> void: call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 30000:
		print("NETWORK_COMPATIBILITY_TIMEOUT role=", "host" if host else "client", " case=", case_name)
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func signal_file(name: String) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	file.store_string("ready")
	file.close()

func wait_file(name: String) -> void:
	while not FileAccess.file_exists(folder.path_join(name)): await create_timer(0.05).timeout

func incompatible_hello() -> void:
	# A rejected production client normally rebuilds the full menu map. This
	# fixture stops before that unrelated scene reload, while leaving the actual
	# host version checks, remote rejection RPC and rejection text unchanged.
	NetSession.enabled = false
	var protocol: int = 7 if case_name == "protocol7" else NetSession.PROTOCOL
	var fingerprint: String = NetSession._fingerprint if case_name == "protocol7" else "incompatible-release-fingerprint"
	NetSession._hello.rpc_id(1, protocol, fingerprint, "Compatibility client", NetSession.local_class_profiles(), CharacterProfile.selected(), {})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--test-host": host = true
		elif arg.begins_with("--compat-case="): case_name = arg.trim_prefix("--compat-case=")
		elif arg.begins_with("--compat-folder="): folder = arg.trim_prefix("--compat-folder=")
	if case_name not in ["protocol7", "fingerprint", "matching"] or folder.is_empty():
		quit(1)
		return
	var game := TestMap.new()
	root.add_child(game)
	current_scene = game
	NetSession.game = game
	NetSession.world = TestWorld.new()
	check(NetSession.PROTOCOL > 7, "Expedition protocol rejects the previously published protocol 7")
	check(NetSession.BUILD != "remz-dev-20261002-rain-extinguish", "Expedition release has a distinct build identifier")
	check(Online.version_tag().begins_with("%d|%s|" % [NetSession.PROTOCOL, NetSession.BUILD]), "EOS lobby version includes the protocol and release identifier")
	if host:
		check(NetSession.host("Compatibility host", 24784) == OK, "Host opens a real ENet socket")
		signal_file("host-ready")
		await wait_file("client-done")
		if case_name == "matching":
			while NetSession.ready_peers.size() != 2 or false in NetSession.ready_peers.values(): await create_timer(0.05).timeout
			check(NetSession.roster.size() == 2 and NetSession.world.actors.size() == 2, "Matching client is accepted into the authoritative roster")
			check(NetSession._loading_peers.is_empty(), "Client acknowledges the complete initial state")
		else:
			check(NetSession.roster.size() == 1 and NetSession.world.actors.size() == 1, "Incompatible client never enters the authoritative roster")
			check(NetSession.class_profiles.size() == 1 and NetSession.ready_peers.size() == 1, "Rejected handshake does not allocate client class or ready state")
		signal_file("host-done")
		await wait_file("client-finished")
	else:
		await wait_file("host-ready")
		if case_name != "matching":
			get_multiplayer().connected_to_server.disconnect(NetSession._connected)
			get_multiplayer().connected_to_server.connect(incompatible_hello)
		check(NetSession.join("127.0.0.1", "Compatibility client", 24784) == OK, "Client opens a real ENet connection")
		if case_name == "matching":
			while not NetSession.ready_peers.get(NetSession.local_id(), false): await create_timer(0.05).timeout
			check(NetSession.phase == "lobby" and NetSession.roster.size() == 2, "Matching client receives welcome and lobby state")
			check(NetSession.world.state_loaded, "Matching client receives the initial snapshot over ENet")
		else:
			while not NetSession.status.begins_with("Different game version or map."): await create_timer(0.05).timeout
			check(NetSession.roster.is_empty(), "Incompatible client receives no welcome or roster")
			check(NetSession.status == "Different game version or map. Host and teammates need the same RemZ build.", "Incompatible client receives the explicit update message")
		signal_file("client-done")
		await wait_file("host-done")
		signal_file("client-finished")
	NetSession.enabled = false
	NetSession.world = null
	NetSession.game = null
	var peer := get_multiplayer().multiplayer_peer
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	print("NETWORK_COMPATIBILITY_DONE role=%s case=%s checks=%d failures=%d" % ["host" if host else "client", case_name, checks, failures])
	quit(0 if failures == 0 else 1)
