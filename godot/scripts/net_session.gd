extends Node

signal changed

const PORT := 24567
const MAX_PLAYERS := 4
const PROTOCOL := 2
const BUILD := "remz-dev-20260923-komplett"
const SNAPSHOT_CHUNK := 900 # Small enough for the additional Hamachi tunnel headers.
var enabled := false
var phase := "offline"
var status := "Co-op over LAN or Hamachi · up to 4 players"
var player_name := "Player"
var address := ""
var port := PORT
var roster: Dictionary = {}
var _leaderboard_t := 0.0
var ready_peers: Dictionary = {}
var _loading_peers: Dictionary = {}
var _initial_parts: Dictionary = {}
var _initial_received := -1
var diagnostic_path := ""
var _closing := false

func trace_load(message: String) -> void:
	print("COOP_LOAD ", message)
	if diagnostic_path.is_empty():
		var local_folder := ProjectSettings.globalize_path("res://../logs/coop") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("logs")
		for folder in [local_folder, ProjectSettings.globalize_path("user://logs"), OS.get_cache_dir().path_join("RemZ-logs")]:
			if DirAccess.make_dir_recursive_absolute(folder) != OK: continue
			var candidate: String = folder.path_join("coop-%d.log" % OS.get_process_id())
			var probe := FileAccess.open(candidate, FileAccess.WRITE)
			if probe:
				probe.close()
				diagnostic_path = candidate
				break
	if diagnostic_path.is_empty():
		push_warning("Co-op diagnostics: no log folder could be created.")
		return
	var file := FileAccess.open(diagnostic_path, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line("%s %s %s" % [Time.get_datetime_string_from_system(), BUILD, message])
		file.flush()
		file.close()

var game: Node3D
var world
var epoch := 0
var _elapsed := 0.0
var _snapshot_t := 0.0
var _pose_t := 0.0
var _connect_t := 0.0
var _hello_t := 0.0
var _fingerprint := ""
var _sequence := 0
var _received_sequence := -1
var _command_seq := 0
var _commands: Dictionary = {}
var _rates: Dictionary = {}
var _applying := false
var _message_after_load := ""
var _snapshot_parts: Dictionary = {}
var _cli_used := false
var _auto_start := 0
# "Nochmal" / "Neue Runde": the rebuilt scene starts the next round itself instead of showing the start menu.
var restart_pending := false
var _round_restart := false

func _ready() -> void:
	trace_load("BOOT exe=" + OS.get_executable_path())
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): leave("Connection failed. Check the Hamachi IP, the network and the UDP port."))
	multiplayer.server_disconnected.connect(func(): leave("The host ended the connection."))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(BUILD.to_utf8_buffer())
	# Variant availability changes the spawned/collidable characters. Reject a
	# partially updated install just as we reject a different terrain version.
	context.update(var_to_bytes(Zombie.TYPES))
	context.update(var_to_bytes(Weapons.DEFS))
	context.update(var_to_bytes(Weapons.Mods.DEFS))
	context.update("aim-ballistics-v14-forest-mushrooms".to_utf8_buffer())
	context.update(var_to_bytes([Waves.ARMY_START, Waves.ARMY_STEP, Waves.ARMY_MAX, Waves.MAX_ACTIVE, Waves.MAX_CORPSES, Waves.MAX_TITANS]))
	context.update(var_to_bytes(Player.RareItems.DEFS))
	context.update(var_to_bytes(Progression.NPCS))
	context.update(var_to_bytes(Progression.GOODS))
	context.update(var_to_bytes(Progression.QUESTS))
	context.update(var_to_bytes(Progression.QUEST_CHAINS))
	context.update(var_to_bytes(Inventory.MUSHROOMS))
	context.update(var_to_bytes(ForestKeys.SPAWN_CHANCE))
	for spec: Dictionary in Progression.NPCS.values():
		context.update((str(spec.model) + str(ResourceLoader.exists("res://assets/models/%s.glb" % spec.model))).to_utf8_buffer())
	for spec: Dictionary in Weapons.DEFS.values():
		context.update((str(spec.model) + str(ResourceLoader.exists("res://assets/models/%s.glb" % spec.model))).to_utf8_buffer())
	for spec: Dictionary in Zombie.TYPES.values():
		for asset in Zombie.skin_names(spec):
			context.update((str(asset) + str(ResourceLoader.exists("res://assets/models/%s.glb" % asset))).to_utf8_buffer())
	# Only files the export preset ships verbatim (include_filter) can be hashed here: an imported
	# texture like ground.png is absent from the pack, so the exe would hash different bytes than
	# the editor and refuse every connection. The BUILD constant above already separates releases.
	for file in ["map.json", "heightmap.f32"]:
		context.update(FileAccess.get_file_as_bytes("res://assets/map/" + file))
	_fingerprint = context.finish().hex_encode()
	trace_load("NETWORK_INITIALIZED")

func is_host() -> bool:
	return enabled and multiplayer.is_server()

func is_client() -> bool:
	return enabled and not multiplayer.is_server()

func local_id() -> int:
	return multiplayer.get_unique_id() if enabled else 1

func attach(node: Node3D) -> void:
	trace_load("MAP_READY")
	game = node
	world = preload("res://scripts/coop_world.gd").new()
	world.setup(game)
	game.player.peer_id = local_id()
	if enabled:
		if is_host():
			ready_peers[1] = true
			world.add_player(1)
			for id in roster:
				if id != 1:
					world.add_player(id)
			_send_lobby()
		else:
			world.make_client()
			_level_ready.rpc_id(1, epoch)
	if not _message_after_load.is_empty():
		status = _message_after_load
		_message_after_load = ""
		game.hud.show_tab("multiplayer")
	changed.emit()
	if not _cli_used:
		_cli_used = true
		_command_line()

# Optional shortcuts for LAN launchers; the same lobby is available in the menu.
func _command_line() -> void:
	var requested_host := false
	var requested_ip := ""
	var requested_name := "Player"
	var requested_port := PORT
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": requested_host = true
		elif arg.begins_with("--join="): requested_ip = arg.trim_prefix("--join=")
		elif arg.begins_with("--name="): requested_name = arg.trim_prefix("--name=")
		elif arg.begins_with("--port="): requested_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--coop-auto-start="): _auto_start = clampi(int(arg.trim_prefix("--coop-auto-start=")), 1, 4)
	if requested_host: host(requested_name, requested_port)
	elif not requested_ip.is_empty(): join(requested_ip, requested_name, requested_port)
	if requested_host or not requested_ip.is_empty(): game.hud.show_tab("multiplayer")

func host(display_name: String, requested_port: int = PORT) -> Error:
	if _closing or enabled or not is_instance_valid(game) or not game.navigation_ready or game.started:
		return ERR_BUSY
	if requested_port < 1024 or requested_port > 65535:
		status = "The port must be between 1024 and 65535."
		changed.emit()
		return ERR_INVALID_PARAMETER
	trace_load("HOST_CREATE port=%d" % requested_port)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(requested_port, MAX_PLAYERS - 1, 3)
	if error != OK:
		status = "Could not start the host. Is the UDP port already in use?"
		changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	enabled = true
	phase = "lobby"
	epoch += 1
	port = requested_port
	player_name = clean_name(display_name)
	roster = {1: player_name}
	game.stats.players.clear()
	ready_peers = {1: true}
	game.player.peer_id = 1
	world.add_player(1)
	status = Lang.t("Host ready · give your Hamachi IP to your teammates · UDP %d", [port])
	print("COOP_HOST_READY port=", port)
	trace_load("HOST_READY")
	changed.emit()
	return OK

func join(ip: String, display_name: String, requested_port: int = PORT) -> Error:
	if _closing or enabled or not is_instance_valid(game) or not game.navigation_ready or game.started:
		return ERR_BUSY
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address() or requested_port < 1024 or requested_port > 65535:
		status = "Enter a valid Hamachi / LAN IP and a port between 1024 and 65535."
		changed.emit()
		return ERR_INVALID_PARAMETER
	trace_load("JOIN_BEGIN address=%s port=%d" % [ip, requested_port])
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, requested_port, 3)
	trace_load("JOIN_SOCKET result=%d" % error)
	if error != OK:
		status = "Could not open the connection."
		changed.emit()
		return error
	multiplayer.multiplayer_peer = peer
	enabled = true
	phase = "connecting"
	game.stats.players.clear()
	_command_seq = 0
	_received_sequence = -1
	_snapshot_parts.clear()
	_initial_parts.clear()
	_initial_received = -1
	address = ip
	port = requested_port
	player_name = clean_name(display_name)
	_connect_t = 15.0
	status = Lang.t("Connecting to %s:%d …", [Lang.raw(ip), port])
	changed.emit()
	return OK

static func clean_name(value: String) -> String:
	value = value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ").left(24)
	return "Player" if value.is_empty() else value

func _connected() -> void:
	if not enabled or phase != "connecting": return
	trace_load("TRANSPORT_CONNECTED sending_hello")
	_hello_t = 0.0
	_connect_t = 12.0
	_hello.rpc_id(1, PROTOCOL, _fingerprint, player_name)

func _peer_connected(id: int) -> void:
	trace_load("PEER_CONNECTED id=%d" % id)
	if is_host():
		_rates[id] = {"deadline": _elapsed + 12.0, "tokens": 80.0, "time": _elapsed}

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(version: int, fingerprint: String, display_name: String) -> void:
	if not is_host(): return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id): return
	if not world or not is_instance_valid(game) or not game.navigation_ready:
		_rejected.rpc_id(id, "The host is still loading the map. Please try joining again in a moment.")
		return
	if version != PROTOCOL or fingerprint != _fingerprint:
		_rejected.rpc_id(id, "Different game version / map. Please use the same Windows version.")
		return
	if roster.size() >= MAX_PLAYERS:
		_rejected.rpc_id(id, "This session is full (4/4 players).")
		return
	roster[id] = clean_name(display_name)
	print("COOP_PEER_ACCEPTED count=", roster.size())
	ready_peers[id] = false
	_rates[id].deadline = _elapsed + 120.0
	world.add_player(id)
	_welcome.rpc_id(id, epoch, roster, phase, game.settings.difficulty)
	_send_lobby()

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(reason: String) -> void:
	leave(reason)

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(session_epoch: int, players: Dictionary, session_phase: String, difficulty_index: int) -> void:
	if not is_client(): return
	trace_load("WELCOME")
	epoch = session_epoch
	roster = players
	phase = session_phase
	_connect_t = 0.0
	_received_sequence = -1
	_snapshot_parts.clear()
	_initial_parts.clear()
	_initial_received = -1
	game.player.peer_id = local_id()
	game.difficulty = GameSettings.DIFFICULTIES[clampi(difficulty_index, 0, GameSettings.DIFFICULTIES.size()-1)]
	world.make_client()
	for id in roster:
		world.add_player(id)
	_level_ready.rpc_id(1, epoch)
	status = "Connected · waiting for the host" if phase == "lobby" else "Loading the game state …"
	print("COOP_CONNECTED players=", roster.size())
	changed.emit()

@rpc("any_peer", "call_remote", "reliable", 0)
func _level_ready(session_epoch: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or epoch != session_epoch or not roster.has(id) or not is_instance_valid(game) or not game.navigation_ready:
		return
	if ready_peers.get(id, false) or _loading_peers.has(id): return
	_loading_peers[id] = true
	_rates[id].deadline = _elapsed + 120.0
	_sequence += 1
	send_reliable_state(id, true, true)

func send_reliable_state(id: int, initial: bool, acknowledge := false) -> void:
	# Advance _sequence once at the caller, so a broadcast has one shared version.
	if not is_host() or not world: return
	var raw := var_to_bytes(world.snapshot())
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var count := ceili(float(packed.size()) / SNAPSHOT_CHUNK)
	trace_load("%s peer=%d raw=%d bytes=%d parts=%d" % ["INITIAL_SEND" if acknowledge else "STATE_SEND", id, raw.size(), packed.size(), count])
	# Also keep the initial reliable transfer below the tunnel MTU. Sending one
	# large RPC here used ENet fragmentation, unlike our small in-game snapshots.
	for part in count:
		_initial_part.rpc_id(id, epoch, _sequence, part, count, raw.size(), packed.slice(part * SNAPSHOT_CHUNK, (part + 1) * SNAPSHOT_CHUNK), initial, acknowledge)

@rpc("authority", "call_remote", "reliable", 0)
func _initial_part(session_epoch: int, sequence: int, part: int, count: int, raw_size: int, bytes: PackedByteArray, initial := true, acknowledge := true) -> void:
	if epoch != session_epoch or sequence <= _initial_received or not world: return
	if count < 1 or count > 600 or part < 0 or part >= count or raw_size < 1 or raw_size > 524288 or bytes.size() > SNAPSHOT_CHUNK: return
	if _initial_parts.is_empty():
		_initial_parts = {"sequence": sequence, "count": count, "size": raw_size, "parts": {}, "initial": initial, "acknowledge": acknowledge}
		trace_load("%s parts=%d" % ["INITIAL_RECEIVE" if acknowledge else "STATE_RECEIVE", count])
	if _initial_parts.sequence != sequence or _initial_parts.count != count or _initial_parts.size != raw_size or _initial_parts.initial != initial or _initial_parts.acknowledge != acknowledge: return
	_initial_parts.parts[part] = bytes
	if _initial_parts.parts.size() != count: return
	var packed := PackedByteArray()
	for index in count: packed.append_array(_initial_parts.parts[index])
	_initial_parts.clear()
	var unpacked := packed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if unpacked.size() != raw_size: return
	var data = bytes_to_var(unpacked)
	if not data is Dictionary: return
	_initial_received = sequence
	if acknowledge:
		_initial_state(session_epoch, sequence, data)
	else:
		_world_state(session_epoch, sequence, data, initial)
		trace_load("STATE_APPLY_DONE sequence=%d" % sequence)

func _initial_state(session_epoch: int, sequence: int, data: Dictionary) -> void:
	if epoch != session_epoch or not world: return
	status = "Preparing the game state and teammates …"
	changed.emit()
	trace_load("INITIAL_APPLY_BEGIN")
	var loading_world = world
	_world_state(session_epoch, sequence, data, true)
	# Give the renderer a frame before acknowledging a usable client.
	await get_tree().process_frame
	await get_tree().process_frame
	if not enabled or epoch != session_epoch or world != loading_world or not world.state_loaded: return
	trace_load("INITIAL_APPLY_DONE")
	_state_ready.rpc_id(1, epoch)

@rpc("any_peer", "call_remote", "reliable", 0)
func _state_ready(session_epoch: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or epoch != session_epoch or not _loading_peers.has(id) or not roster.has(id): return
	_loading_peers.erase(id)
	ready_peers[id] = true
	trace_load("CLIENT_READY peer=%d" % id)
	if phase == "running":
		_begin.rpc_id(id, epoch, false) # Late joins keep the replicated team position.
	_send_lobby()

func _send_lobby() -> void:
	if not is_host(): return
	_lobby.rpc(epoch, roster, ready_peers, phase)
	changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _lobby(session_epoch: int, players: Dictionary, ready: Dictionary, session_phase: String) -> void:
	if session_epoch != epoch: return
	roster = players
	ready_peers = ready
	phase = session_phase
	if is_client() and phase == "lobby" and ready_peers.get(local_id(), false):
		status = "Ready · waiting for the host"
	if world:
		world.sync_roster()
	changed.emit()

func start_game() -> void:
	if not is_host() or phase != "lobby" or not game.navigation_ready: return
	for id in roster:
		if not ready_peers.get(id, false):
			status = "A player is still loading."
			changed.emit()
			return
	trace_load("ROUND_START_SEND players=%d" % roster.size())
	phase = "running"
	var play_intro: bool = not _round_restart and game.should_play_intro()
	if play_intro: world.prepare_intro()
	_sequence += 1
	for id in roster:
		world.actor(id).active = true
		world.actor(id).regen_mul = float(game.difficulty.regen)
		if id != 1: send_reliable_state(id, true)
	_begin.rpc(epoch, play_intro)
	_begin(epoch, play_intro)
	_send_lobby()

@rpc("authority", "call_remote", "reliable", 0)
func _begin(session_epoch: int, play_intro: bool = false) -> void:
	if epoch != session_epoch: return
	trace_load("ROUND_BEGIN intro=%s" % play_intro)
	phase = "running"
	_applying = true
	game._on_start(play_intro)
	_applying = false
	status = Lang.t("Co-op · %d/4 players", [roster.size()])
	changed.emit()
	trace_load("ROUND_RUNNING players=%d" % roster.size())
	print("COOP_RUNNING players=", roster.size())

func _peer_disconnected(id: int) -> void:
	trace_load("PEER_DISCONNECTED id=%d" % id)
	if not enabled: return
	roster.erase(id)
	ready_peers.erase(id)
	_loading_peers.erase(id)
	_commands.erase(id)
	_rates.erase(id)
	if world: world.remove_player(id)
	if is_host():
		_send_lobby()
		if world: world.check_team()
	changed.emit()

func leave(reason := "Left the session.") -> void:
	if _closing: return
	if not enabled:
		status = reason
		changed.emit()
		return
	trace_load("LEAVE_BEGIN phase=%s reason=%s" % [phase, Lang.resolve(reason, "en")])
	var reuse_map: bool = is_instance_valid(game) and not game.started and world != null and not world.state_loaded and _initial_received < 0
	_closing = true
	enabled = false
	phase = "offline"
	epoch += 1 # Invalidate an initial-state callback waiting for rendering.
	status = "Closing the connection …"
	var leaving_game := game
	game = null
	changed.emit()
	_finish_leave.call_deferred(reason, reuse_map, leaving_game)

func _finish_leave(reason: String, reuse_map: bool, leaving_game: Node3D) -> void:
	# Never close ENet or reload a scene inside its poll/signal callback.
	var old_peer := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	trace_load("LEAVE_PEER_DETACHED")
	if old_peer: old_peer.close()
	trace_load("LEAVE_PEER_CLOSED")
	game = leaving_game
	_auto_start = 0
	restart_pending = false
	_round_restart = false
	_command_seq = 0
	_connect_t = 0.0
	roster.clear()
	ready_peers.clear()
	_loading_peers.clear()
	_initial_parts.clear()
	_initial_received = -1
	_commands.clear()
	_rates.clear()
	_snapshot_parts.clear()
	if reuse_map and is_instance_valid(game):
		for id in world.actors.keys(): world.remove_player(id)
		game.player.peer_id = 1
		game.stats.players.clear()
		game.stats.register_player(1, player_name)
		game.player.regen_timer = 0.0
		game.player.active = false
		game.player.camera.make_current()
		game.waves.set_process(true)
		game.day_night.set_process(true)
		game.achievements.set_process(true)
		for animal in world.deer: animal.set_physics_process(true)
		world = preload("res://scripts/coop_world.gd").new()
		world.setup(game)
		get_tree().paused = true
		game.hud.show_tab("multiplayer")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		status = reason
		_closing = false
		trace_load("LEAVE_DONE reused_loaded_map")
		changed.emit()
		return
	if is_instance_valid(game):
		game.player.active = false
		game.hud.set_loading(true)
	status = "Returning to the main menu …"
	changed.emit()
	# The loading screen covers the rebuild and fades into the start menu (boot_screen.gd).
	BootScreen.cover(get_tree(), "Back to main menu …")
	world = null
	game = null
	_message_after_load = reason
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	trace_load("LEAVE_RELOAD")
	_closing = false
	get_tree().call_deferred("reload_current_scene")

func restart() -> void:
	if not is_host() or phase != "over": return
	epoch += 1
	_auto_start = clampi(roster.size(), 1, 4)
	_reload.rpc(epoch)
	_reload(epoch)

@rpc("authority", "call_remote", "reliable", 0)
func _reload(session_epoch: int) -> void:
	epoch = session_epoch
	_round_restart = true
	phase = "lobby"
	ready_peers.clear()
	_loading_peers.clear()
	_initial_parts.clear()
	_initial_received = -1
	_command_seq = 0
	for id in _rates: _rates[id].deadline = _elapsed + 120.0
	_commands.clear()
	_received_sequence = -1
	_snapshot_parts.clear()
	world = null
	game = null
	BootScreen.cover(get_tree(), "New round …")
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")

func command(operation: String, args: Array = []) -> void:
	if not enabled or phase != "running": return
	if is_host():
		world.action(1, operation, args)
	else:
		_command_seq += 1
		_action.rpc_id(1, epoch, _command_seq, operation, args)

@rpc("any_peer", "call_remote", "reliable", 0)
func _action(session_epoch: int, sequence: int, operation: String, args: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _accept(id, session_epoch) or phase != "running" or args.size() > 8 or operation.length() > 24: return
	if sequence <= int(_commands.get(id, -1)): return
	_commands[id] = sequence
	world.action(id, operation, args)

func _accept(id: int, session_epoch: int) -> bool:
	if not is_host() or epoch != session_epoch or not ready_peers.get(id, false) or not world: return false
	var budget: Dictionary = _rates.get(id, {})
	if budget.is_empty(): return false
	budget.tokens = minf(80.0, budget.tokens + (_elapsed - float(budget.time)) * 100.0)
	budget.time = _elapsed
	if budget.tokens < 1.0: return false
	budget.tokens -= 1.0
	return true

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _pose(session_epoch: int, position: Vector3, yaw: float, pitch: float, light: bool, motion: Vector3, sequence: int = 0, crouching: bool = false) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _accept(id, session_epoch) or phase != "running": return
	if not position.is_finite() or not motion.is_finite() or not is_finite(yaw) or not is_finite(pitch): return
	if sequence <= 0: return
	world.move_player(id, position, yaw, pitch, light, motion, _elapsed, sequence, crouching)

@rpc("authority", "call_remote", "unreliable", 2)
func _snapshot_part(session_epoch: int, sequence: int, part: int, count: int, raw_size: int, bytes: PackedByteArray) -> void:
	if epoch != session_epoch or sequence <= _received_sequence or not world: return
	if count < 1 or count > 64 or part < 0 or part >= count or raw_size < 1 or raw_size > 524288 or bytes.size() > SNAPSHOT_CHUNK: return
	if not _snapshot_parts.has(sequence):
		_snapshot_parts[sequence] = {"count": count, "size": raw_size, "parts": {}}
	var pending: Dictionary = _snapshot_parts[sequence]
	if pending.count != count or pending.size != raw_size: return
	pending.parts[part] = bytes
	for old in _snapshot_parts.keys():
		if old < sequence - 2: _snapshot_parts.erase(old)
	if pending.parts.size() != count: return
	var packed := PackedByteArray()
	for i in count: packed.append_array(pending.parts[i])
	_snapshot_parts.erase(sequence)
	var unpacked := packed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if unpacked.size() != raw_size: return
	var data = bytes_to_var(unpacked)
	if not data is Dictionary: return
	_received_sequence = sequence
	world.apply_snapshot(data, false)

@rpc("authority", "call_remote", "reliable", 0)
func _world_state(session_epoch: int, sequence: int, data: Dictionary, initial: bool) -> void:
	if epoch != session_epoch or not world: return
	_received_sequence = maxi(_received_sequence, sequence)
	_snapshot_parts.clear()
	world.apply_snapshot(data, initial)

func feedback(id: int, kind: String, args: Array) -> void:
	if not is_host(): return
	if id == 1:
		_feedback(epoch, kind, args)
	elif ready_peers.get(id, false):
		_feedback.rpc_id(id, epoch, kind, args)

@rpc("authority", "call_remote", "reliable", 0)
func _feedback(session_epoch: int, kind: String, args: Array) -> void:
	if epoch != session_epoch or not is_instance_valid(game): return
	match kind:
		"quest_complete":
			if args.size() == 1 and args[0] is String and Progression.QUESTS.has(args[0]):
				game.progression.notifications.rewarded(args[0])
		"sfx":
			if args.size() == 1 and args[0] is String and Sfx.EVENTS.has(args[0]):
				Sfx.play(game, args[0], Sfx.EVENTS[args[0]])
		"trade":
			game.progression.status.text = str(args[0])
			if args.size() > 1: game.progression.show_gain(int(args[1]))
			if not game.progression.is_open and not str(args[0]).is_empty(): game.hud.message(str(args[0]), 3)
		"message": game.hud.message(args[0], args[1])
		"hit": game.hud.hitmarker(args[0])
		"hurt":
			game.hud.damage_flash(args[0])
			Sfx.play(game, "hurt", -3.0)
		"score": game.hud.score_popup(args[0], args[1])
		"streak": game.hud.streak(args[0], args[1])

func weapon_fired(id: int, weapon: String, stab: bool = false) -> void:
	if not is_host(): return
	var definition: Dictionary = world.weapons[id].state[weapon].def
	# Same colour the shooter sees in their own hands: an energy weapon carries its own element, a
	# bought round only shows when the weapon has none of its own (weapon_specials.flash_mode).
	var shot_mode: String = WeaponSpecials.flash_mode(weapon, str(world.game.progression.rare_market.round_mode(world.actors[id])))
	var mod_effects := [definition.get("sfx_db", -8.0), definition.get("flash_scale", 1.0), definition.kick_pitch, shot_mode]
	if Weapons.is_melee(weapon): mod_effects = [stab and Weapons.is_melee(weapon)]
	_shot.rpc(epoch, id, weapon, mod_effects)
	_shot(epoch, id, weapon, mod_effects)

@rpc("authority", "call_remote", "unreliable", 1)
func _shot(session_epoch: int, id: int, weapon: String, mod_effects: Array = []) -> void:
	if epoch == session_epoch and id != local_id() and world:
		world.show_shot(id, weapon, mod_effects)

func elemental_shot(origin: Vector3, end: Vector3, mode: String, impact: bool, shooter: int = 0) -> void:
	if is_host(): _elemental_shot.rpc(epoch, origin, end, mode, impact, shooter)
	_elemental_shot(epoch, origin, end, mode, impact, shooter)

@rpc("authority", "call_remote", "unreliable", 1)
func _elemental_shot(session_epoch: int, origin: Vector3, end: Vector3, mode: String, impact: bool, shooter: int = 0) -> void:
	if session_epoch != epoch: return
	var scene := get_tree().current_scene
	if not scene: return
	var follow_muzzle := Callable()
	if shooter == local_id() and "weapons" in scene and scene.weapons:
		follow_muzzle = scene.weapons.visual_muzzle_world
		origin = follow_muzzle.call()
	preload("res://scripts/elemental_effects.gd").shot(scene, origin, end, mode, impact, follow_muzzle)

func track_grenade(grenade: Node3D) -> void:
	if is_host() and world: world.track_grenade(grenade)

func explosion(position: Vector3) -> void:
	if is_host(): _explosion.rpc(epoch, position)

# A burning flare on the ground lights the forest for the whole team, not only for the shooter.
func flare(position: Vector3, shooter: int = 0) -> void:
	if is_host(): _flare.rpc(epoch, position, shooter)

@rpc("authority", "call_remote", "reliable", 0)
func _flare(session_epoch: int, position: Vector3, shooter: int = 0) -> void:
	# The shooter placed this light already when they predicted their own shot.
	if epoch == session_epoch and shooter != local_id() and world: world.show_flare(position)

# The graviton cannon's gravity well: drawn on every peer, including the one that fired.
func blast(position: Vector3) -> void:
	if is_host(): _blast.rpc(epoch, position)
	_blast(epoch, position)

@rpc("authority", "call_remote", "reliable", 0)
func _blast(session_epoch: int, position: Vector3) -> void:
	if epoch == session_epoch and world: world.show_blast(position)

@rpc("authority", "call_remote", "reliable", 0)
func _explosion(session_epoch: int, position: Vector3) -> void:
	if epoch == session_epoch and world: world.show_explosion(position)

func nearest_player(position: Vector3) -> Player:
	return world.nearest_player(position) if enabled and world else null

func titan_cue(kind: String, origin: Vector3, body_height: float, emitter: int, serial: int) -> void:
	if not is_host(): return
	for id in ready_peers:
		if id != 1 and ready_peers[id]:
			_titan_cue.rpc_id(id, epoch, kind, origin, body_height, emitter, serial)

@rpc("authority", "call_remote", "reliable", 0)
func _titan_cue(session_epoch: int, kind: String, origin: Vector3, body_height: float, emitter: int, serial: int) -> void:
	if epoch != session_epoch or not world or not is_instance_valid(game): return
	TitanPresence.for_scene(game).receive(kind, origin, body_height, emitter, serial)

func bullet_impact(position: Vector3, normal: Vector3) -> void:
	if is_host(): _bullet_impact.rpc(epoch, position, normal)
	_bullet_impact(epoch, position, normal)

@rpc("authority", "call_remote", "unreliable", 1)
func _bullet_impact(session_epoch: int, position: Vector3, normal: Vector3) -> void:
	if epoch != session_epoch: return
	preload("res://scripts/bullet_impacts.gd").show(get_tree().current_scene, position, normal)

func blood(position: Vector3, direction: Vector3) -> void:
	if is_host(): _blood.rpc(epoch, position, direction)

@rpc("authority", "call_remote", "unreliable", 1)
func _blood(session_epoch: int, position: Vector3, direction: Vector3) -> void:
	if epoch == session_epoch and is_instance_valid(game): game.weapons._blood(position, direction)

# Host-measured ENet round-trip time, in milliseconds. Never ask for a missing peer.
func peer_ping(id: int) -> int:
	if not is_host(): return -1
	if id == 1: return 0
	var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if not transport or not id in multiplayer.get_peers(): return -1
	var peer := transport.get_peer(id)
	if not peer or peer.get_state() != ENetPacketPeer.STATE_CONNECTED: return -1
	return maxi(0, roundi(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)))

@rpc("authority", "call_remote", "unreliable", 1)
func _leaderboard_live(session_epoch: int, rows: Dictionary) -> void:
	if is_client() and epoch == session_epoch and phase == "over" and is_instance_valid(game):
		game.stats.players = rows.duplicate(true)

func _process(delta: float) -> void:
	_elapsed += delta
	if not enabled: return
	if _connect_t > 0.0:
		_connect_t -= delta
		if _connect_t <= 0.0:
			leave(Lang.t("No answer from the host. Check the Hamachi connection and that UDP %d is allowed in the Windows Firewall.", [port]))
			return
	if is_host():
		_leaderboard_t += delta
		if _leaderboard_t >= 1.0:
			_leaderboard_t = 0.0
			var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if transport:
				for id in multiplayer.get_peers():
					var peer := transport.get_peer(id)
					if peer and peer.get_state() == ENetPacketPeer.STATE_CONNECTED: peer.ping()
			# Running rounds use world snapshots. Keep ping live after the round ends too.
			if phase == "over" and world and is_instance_valid(game):
				world.refresh_leaderboard()
				_leaderboard_live.rpc(epoch, game.stats.players)
		for id in _rates.keys():
			if not ready_peers.get(id, false) and _elapsed > float(_rates[id].deadline):
				multiplayer.multiplayer_peer.disconnect_peer(id)
		if _auto_start > 0 and phase == "lobby" and roster.size() >= _auto_start and ready_peers.size() == roster.size() and not false in ready_peers.values():
			_auto_start = 0
			start_game()
	elif is_instance_valid(game) and world and game.navigation_ready and phase == "lobby" and not ready_peers.get(local_id(), false):
		_hello_t += delta
		if _hello_t > 1.0:
			_hello_t = 0.0
			_level_ready.rpc_id(1, epoch)
	if not is_instance_valid(game) or not world or phase != "running": return
	world.tick(delta)
	if is_host():
		_snapshot_t += delta
		if _snapshot_t >= 0.1:
			_snapshot_t = 0.0
			_sequence += 1
			var raw := var_to_bytes(world.snapshot())
			var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
			var count := ceili(float(packed.size()) / SNAPSHOT_CHUNK)
			for i in count:
				var chunk := packed.slice(i * SNAPSHOT_CHUNK, (i+1) * SNAPSHOT_CHUNK)
				for id in ready_peers:
					if id != 1 and ready_peers[id]: _snapshot_part.rpc_id(id, epoch, _sequence, i, count, raw.size(), chunk)
	else:
		_pose_t += delta
		if _pose_t >= 0.05 and game.player.alive:
			_pose_t = 0.0
			var pose_sequence: int = world.movement_sync.record(game.player.global_position)
			_pose.rpc_id(1, epoch, game.player.global_position, game.player.rotation.y, game.player.pitch, game.player.flashlight.visible, game.player.velocity, pose_sequence, game.player.crouching)
