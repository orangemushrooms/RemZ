# Opt-in capture fixture. Normal gameplay never loads this script.
# The host is the simulation clock. Connected clients send real NetSession commands;
# staged movement runs with collisions on the host so offline movie rendering cannot
# make headless clients run ahead. Gameplay damage, ammo, purchases and FX are unchanged.
extends Node

const STORY := "res://cinematics/trailer.json"
const MUTED_MUSIC := "TrailerMutedMusic"
const NAMES := ["KONM", "Luca", "Mara", "Nico"]
const Corn = preload("res://scripts/cornfield.gd")

var mode := "check"
var role := "host"
var folder := ""
var port := 24739
var fps := 30
var selected := PackedStringArray()
var game: Node3D
var camera: Camera3D
var caption: Label
var shots: Array = []
var clips: Array = []
var reports: Array = []
var peers: Array[int] = []
var shot: Dictionary = {}
var anchor := Vector3.ZERO
var route: Array[Vector3] = []
var route_indices: Dictionary = {}
var playing := false
var failed := false
var finishing := false
var ready_clients: Dictionary = {}
var acknowledgements: Dictionary = {}
var serial := 0
var command_count := 0
var remote_commands := 0
var local_time := 0.0
var cues_done: Dictionary = {}
var evidence: Dictionary = {}
var old_ammo: Dictionary = {}
var shot_counts: Dictionary = {}
var start_positions: Dictionary = {}
var tower: DefenceTower
var tower_point := Vector3.ZERO
var mushroom: Loot
var bird: Node3D
var pending_enemies: Array[Zombie] = []
var began := Time.get_ticks_msec()
var last_wall_frame := Time.get_ticks_usec()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fireworks updates first-person visibility every frame. Apply the cinematic
	# camera's visibility after the ordinary gameplay processes have run.
	process_priority = 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trailer-mode="): mode = arg.get_slice("=", 1)
		if arg.begins_with("--trailer-role="): role = arg.get_slice("=", 1)
		if arg.begins_with("--trailer-folder="): folder = arg.trim_prefix("--trailer-folder=")
		if arg.begins_with("--trailer-port="): port = int(arg.get_slice("=", 1))
		if arg.begins_with("--trailer-fps="): fps = int(arg.get_slice("=", 1))
		if arg.begins_with("--trailer-shots="): selected = arg.get_slice("=", 1).split(",", false)
	if not "--trailer-run" in OS.get_cmdline_user_args() or folder.is_empty():
		_fail("Use tools/trailer.py to launch the director.")
		return
	call_deferred("_run")

func _process(_delta: float) -> void:
	if failed or finishing: return
	# --fixed-fps bypasses Engine.max_fps in headless mode. Explicitly pace the
	# director so its simulated network deadlines cannot outrun the real clients.
	if role == "host" and mode != "check":
		var limit := 120 if mode == "verify" and NetSession.phase == "running" else fps
		var wait_usec := int(1000000.0 / limit) - (Time.get_ticks_usec() - last_wall_frame)
		if wait_usec > 0: OS.delay_usec(wait_usec)
		last_wall_frame = Time.get_ticks_usec()
	if Time.get_ticks_msec() - began > 7000000: _fail("Director watchdog expired.")
	if is_instance_valid(game):
		# Focus loss and human input cannot interrupt an unattended capture.
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		if NetSession.is_client(): NetSession._pose_t = -1.0e9
		if role == "host" and not shot.is_empty():
			game.weapons.viewmodel.visible = str(shot.camera).begins_with("fp")

func _write(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(folder.path_join(name + ".json"), FileAccess.WRITE)
	if file == null:
		push_error("TRAILER_FAILED Cannot write " + name)
		failed = true
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _fail(message: String) -> void:
	if failed: return
	failed = true
	playing = false
	push_error("TRAILER_FAILED " + message)
	_write("result" if role == "host" else role + "-result", {"passed": false, "reason": message, "shot": shot.get("id", "loading")})
	get_tree().quit(1)

func _progress(message: String) -> void:
	print("TRAILER ", message)
	if role == "host": _write("progress", {"message": message})

func _contract() -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(STORY))
	if not data is Dictionary:
		_fail("Invalid storyboard JSON.")
		return false
	var total := 0.0
	var ids := {}
	for s: Dictionary in data.shots:
		if ids.has(s.id) or float(s.seconds) <= 0:
			_fail("Invalid shot ID/duration.")
			return false
		ids[s.id] = true
		total += float(s.seconds)
		for weapon: String in s.get("weapons", []):
			if not Weapons.DEFS.has(weapon):
				_fail("Unknown weapon " + weapon)
				return false
		for cue: Dictionary in s.get("cues", []):
			if not Fireworks.DEFS.has(cue.item) or float(cue.at) >= float(s.seconds):
				_fail("Invalid fireworks cue in " + s.id)
				return false
		if s.has("npc") and not Progression.NPCS.has(s.npc):
			_fail("Unknown NPC.")
			return false
		if selected.is_empty() or s.id in selected: shots.append(s)
	if not is_equal_approx(total, 300.0) or shots.is_empty():
		_fail("Storyboard must total 300 seconds and have selected shots.")
		return false
	if mode == "record" and not OS.has_feature("editor"):
		_fail("OGV recording needs the Godot editor binary, not RemZ.exe.")
		return false
	_progress("Storyboard OK: %d shots, %.1f s" % [data.shots.size(), total])
	return true

func _run() -> void:
	if not _contract(): return
	if mode == "check":
		_write("result", {"passed": true, "shots": shots.size(), "editor_binary": OS.has_feature("editor")})
		get_tree().quit()
		return
	if mode not in ["verify", "record"]:
		_fail("Unknown mode.")
		return
	seed(4242)
	game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	# Keep the recorded fixture's navigation registered while the loading menu
	# pauses the world, including a mesh published between Movie Maker frames.
	game.nav_region.process_mode = Node.PROCESS_MODE_ALWAYS
	NavigationServer3D.map_set_use_async_iterations(game.nav_region.get_navigation_map(), false)
	while not game.navigation_ready: await get_tree().process_frame
	# Fixed-FPS headless loops otherwise consume minutes of network timeout while
	# another client is still loading. Lobby time must not run faster than real time.
	Engine.max_fps = fps if role == "host" else 60
	game.settings._testing = true
	game.settings.show_fps = false
	game.achievements.persist = false
	game.stats.persist = false
	game.player.set_process_unhandled_input(false)
	game.hud.set_process_unhandled_input(false)
	game.settings.set_process_unhandled_input(false)
	# Keep all diagnostic writes inside this take, including NetSession's subsequent traces.
	NetSession.diagnostic_path = folder.path_join(role + "-network.log")
	var log_file := FileAccess.open(NetSession.diagnostic_path, FileAccess.WRITE)
	if log_file: log_file.close()
	_mute_music()
	game.intro.set_process(false)
	game.day_night.set_process(false)
	if role == "host": await _host()
	else: await _client()

func _mute_music() -> void:
	var bus := AudioServer.get_bus_index(MUTED_MUSIC)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, MUTED_MUSIC)
	AudioServer.set_bus_mute(bus, true)
	game.music.stop_all()
	game.music.set_process(false)
	for voice: AudioStreamPlayer in game.music._players.values():
		voice.stop()
		voice.bus = MUTED_MUSIC
	game.intro._music.stop()
	game.intro._music.bus = MUTED_MUSIC

func _host() -> void:
	_progress("Loading host and three clients; no input needed.")
	if NetSession.host(NAMES[0], port) != OK:
		_fail("Unable to bind trailer ENet port.")
		return
	_write("host-ready", {"port": port})
	var deadline := Time.get_ticks_msec() + 240000
	while NetSession.roster.size() != 4 or false in NetSession.ready_peers.values() or ready_clients.size() != 3:
		if Time.get_ticks_msec() > deadline:
			_fail("Four clients did not become ready.")
			return
		await get_tree().process_frame
	peers.append(1)
	for index in range(1, 4):
		for id: int in NetSession.roster:
			if NetSession.roster[id] == NAMES[index]: peers.append(id)
	if peers.size() != 4:
		_fail("Unexpected player roster.")
		return
	NetSession.start_game()
	game.waves.set_process(false)
	game.waves.timer = 100000.0
	game.waves.phase = "idle"
	game.waves.wave = 1
	game.waves.completed = 12 # Staged equipment access, no changes to catalogue or combat stats.
	for id: int in peers:
		var p: Player = NetSession.world.actor(id)
		p.set_physics_process(false)
		p.set_process_unhandled_input(false)
	game.settings.fps_limit = 0
	Engine.max_fps = 120 if mode == "verify" else fps
	_build_camera()
	for s: Dictionary in shots:
		if failed: return
		await _run_shot(s)
	if failed: return
	_write("edit", {"mode": mode, "fps": fps, "clips": clips})
	_write("result", {"passed": true, "mode": mode, "players": 4, "reports": reports,
		"remote_commands": remote_commands, "seconds": _duration(), "gameplay_music_muted": true})
	_progress("All selected scenes passed; %d real client commands acknowledged." % remote_commands)
	# Finish clients before shutting down the host, avoiding an unintended map reload on disconnect.
	for id: int in peers:
		if id != 1: _finish_client.rpc_id(id)
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var all_done := true
		for label in ["c1", "c2", "c3"]:
			if not FileAccess.file_exists(folder.path_join(label + "-result.json")): all_done = false
		if all_done: break
		await get_tree().process_frame
	finishing = true
	get_tree().quit()

func _duration() -> float:
	var value := 0.0
	for clip: Dictionary in clips: value += float(clip.frames) / fps
	return value

func _client() -> void:
	# The rendered host may compile shaders long after headless clients are ready.
	var deadline := Time.get_ticks_msec() + 1800000
	while not FileAccess.file_exists(folder.path_join("host-ready.json")):
		if Time.get_ticks_msec() > deadline:
			_fail("Host did not become ready.")
			return
		await get_tree().process_frame
	deadline = Time.get_ticks_msec() + 240000
	var index := int(role.trim_prefix("c"))
	if index not in [1, 2, 3] or NetSession.join("127.0.0.1", NAMES[index], port) != OK:
		_fail("Client cannot join.")
		return
	while not NetSession.ready_peers.get(NetSession.local_id(), false):
		if Time.get_ticks_msec() > deadline:
			_fail("Client initial snapshot timeout.")
			return
		await get_tree().process_frame
	game.player.set_physics_process(false)
	NetSession._pose_t = -1.0e9
	_client_ready.rpc_id(1)
	Engine.max_fps = 60

@rpc("any_peer", "call_remote", "reliable", 0)
func _client_ready() -> void:
	if NetSession.is_host(): ready_clients[multiplayer.get_remote_sender_id()] = true

@rpc("authority", "call_remote", "reliable", 0)
func _perform(number: int, operation: String, args: Array) -> void:
	if not NetSession.is_client(): return
	NetSession.command(operation, args)
	command_count += 1
	_ack.rpc_id(1, number, NetSession._command_seq)

@rpc("any_peer", "call_remote", "reliable", 0)
func _ack(number: int, command_sequence: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not NetSession.is_host() or not ready_clients.has(id): return
	if int(NetSession._commands.get(id, -1)) < command_sequence:
		_fail("Client acknowledged a command the game did not accept.")
		return
	acknowledgements[number] = id
	remote_commands += 1

@rpc("authority", "call_remote", "reliable", 0)
func _finish_client() -> void:
	if not NetSession.is_client(): return
	finishing = true
	_write(role + "-result", {"passed": NetSession.roster.size() == 4 and NetSession._received_sequence > 0,
		"players": NetSession.roster.size(), "commands": command_count, "snapshots": NetSession._received_sequence})
	# Stay connected until the host quits; its disconnect callback must not rebuild this map.
	NetSession.set_process(false)
	get_tree().quit()

func _command(index: int, operation: String, args: Array) -> void:
	var id := peers[index]
	if id == 1: NetSession.command(operation, args)
	else:
		serial += 1
		_perform.rpc_id(id, serial, operation, args)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "TrailerCamera"
	camera.fov = 60.0
	game.add_child(camera)
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 36)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(caption)

func _run_shot(spec: Dictionary) -> void:
	shot = spec
	_progress("Preparing " + str(shot.id) + ": " + str(shot.label))
	await _prepare_shot()
	if failed: return
	# Warm camera exposure, viewmodels and physics outside the edit range.
	for i in 20: await get_tree().process_frame
	if shot.kind == "studio":
		game.intro.begin()
		game.intro._music.bus = "Master"
		game.intro._music.play()
	elif shot.kind == "intro":
		game.intro.begin()
		game.intro.phase = "wake"
		game.intro._t = 0.0
		game.intro._logo.hide()
		game.player.active = true
	for enemy: Zombie in pending_enemies:
		if is_instance_valid(enemy): enemy.set_physics_process(true)
	playing = true
	var frames := int(round(float(shot.seconds) * fps))
	await get_tree().process_frame
	var first_frame := Engine.get_process_frames()
	for frame in frames:
		if failed: return
		local_time = float(frame) / fps
		_tick(1.0 / fps, frame)
		await get_tree().process_frame
	playing = false
	Input.action_release("fire")
	Input.action_release("aim")
	game.intro._music.stop()
	game.intro._music.bus = MUTED_MUSIC
	# Wait for all RPC results outside the final cut. No stalled networking becomes footage.
	var deadline := Time.get_ticks_msec() + 12000
	while acknowledgements.size() < serial:
		if Time.get_ticks_msec() > deadline:
			_fail("Unacknowledged client action.")
			return
		await get_tree().process_frame
	if not _verify_shot(): return
	clips.append({"id": shot.id, "first_frame": first_frame, "frames": frames, "coop": shot.get("coop", false)})
	_write("edit", {"mode": mode, "fps": fps, "clips": clips})
	_progress("Passed " + str(shot.id))

func _prepare_shot() -> void:
	cues_done.clear()
	evidence.clear()
	old_ammo.clear()
	shot_counts.clear()
	start_positions.clear()
	route_indices.clear()
	pending_enemies.clear()
	local_time = 0.0
	Input.action_release("fire")
	Input.action_release("aim")
	game.progression.close()
	game.defences.cancel_placement()
	game.fireworks.cancel()
	# A cut can leave the original intro before it restores its temporary dense fog.
	# Restore it explicitly so every following landscape keeps its normal visibility.
	if game.intro.active:
		game.settings.env.fog_density = game.intro._fog_base
		game.settings.env.volumetric_fog_density = game.intro._vfog_base
		game.settings.env.fog_sky_affect = game.intro._sky_affect_base
		game.settings.env.fog_aerial_perspective = game.intro._aerial_base
	game.intro.active = false
	game.intro._layer.hide()
	game.intro._music.stop()
	game.intro._music.bus = MUTED_MUSIC
	for t: DefenceTower in game.defences.towers.values():
		game.defences.release_tower(t)
		t.queue_free()
	tower = null
	for enemy in game.zombies_root.get_children(): enemy.queue_free()
	for effect in game.fireworks.active.values():
		if is_instance_valid(effect): effect.queue_free()
	game.fireworks.active.clear()
	for drop in get_tree().get_nodes_in_group("pickups"): drop.queue_free()
	await get_tree().process_frame
	game.day_night.set_time_hours(float(shot.hour))
	game.waves.phase = "idle"
	game.waves.timer = 100000.0
	game.waves.set_process(false)
	game.over = false
	anchor = _resolve_anchor(shot.anchor)
	if failed: return
	route = _resolve_route()
	var count := 4 if shot.get("coop", false) else 1
	var loadout: Array = shot.get("weapons", ["pistol", "ak47", "shotgun", "smg"])
	for i in 4:
		var p: Player = NetSession.world.actor(peers[i])
		var w: Weapons = NetSession.world.weapons[peers[i]]
		p.alive = true
		p.hp = p.max_hp
		p.score = 5000
		p.active = i < count
		p.visible = i < count
		p.set_crouching(false, false)
		p.head.position.y = Player.EYE
		p.velocity = Vector3.ZERO
		p.recoil_offset = Vector2.ZERO
		p.rotation.y = 0.0
		p.pitch = 0.0
		p.head.rotation.x = 0.0
		p.camera.rotation = Vector3.ZERO
		p.global_position = anchor + Vector3(float(i) * 2.2, 0, -float(i % 2) * 2.0)
		if i >= count: p.global_position = _ground(Vector2(130, -210))
		elif shot.kind == "maze":
			p.global_position = route[mini(i * 2, route.size() - 1)]
		p.global_position.y = Map.ground_height(p.global_position.x, p.global_position.z) + 0.12
		route_indices[i] = mini(i * 2 + 1, route.size() - 1) if shot.kind == "maze" else 1
		start_positions[i] = p.global_position
		var weapon: String = loadout[mini(i, loadout.size() - 1)]
		w.unlock(weapon)
		w.set_weapon(weapon)
		w.refill_all()
		w.cur().cooldown = 0.0
		w.cur().reloading = 0.0
		old_ammo[i] = int(w.cur().ammo)
		shot_counts[i] = 0
		game.fireworks.cooldowns[peers[i]] = 0.0
		for item in Fireworks.DEFS: game.fireworks.stock(peers[i])[item] = 2
		if i != 0: NetSession.send_reliable_state(peers[i], true)
	var fp: bool = str(shot.camera).begins_with("fp")
	for layer: CanvasLayer in game.find_children("*", "CanvasLayer", true, false): layer.visible = fp
	game.hud.overlay.hide()
	game.hud.fps_label.hide()
	game.achievements.hide()
	game.intro._layer.visible = shot.kind in ["studio", "intro"]
	game.weapons.viewmodel.visible = fp
	if fp: game.player.camera.make_current()
	else: camera.make_current()
	caption.text = str(shot.get("caption", ""))
	caption.visible = not caption.text.is_empty()
	if shot.kind == "end":
		caption.add_theme_font_size_override("font_size", 42)
	else: caption.add_theme_font_size_override("font_size", 30)
	if shot.kind == "npc":
		_look(game.player, game.progression.npcs[shot.npc].global_position + Vector3.UP * 1.4)
	elif shot.kind == "mushroom":
		_look(game.player, mushroom.global_position + Vector3.UP * 0.25)
	elif shot.kind == "tower":
		tower_point = _find_tower_place()
		if failed: return
		# Stage the entry position before the edit range; the filmed mount is the real action.
		if game.player.global_position.distance_to(tower_point) > 3.5:
			var entry := tower_point + (anchor - tower_point).normalized() * 2.6
			game.player.global_position = _ground(Vector2(entry.x, entry.z))
	elif shot.kind == "birds":
		bird.flying = 0.0
		bird.flight_wait = 100.0
		bird.call_time = 0.5
		bird.position = bird.home
	if shot.kind in ["combat", "titan"] or (shot.kind == "tower" and shot.get("tower_action") == "fire"):
		_spawn_encounter()
	if route.size() > 1: _look(game.player, route[1] + Vector3.UP * Player.EYE)
	_camera(0.0)

func _ground(p: Vector2) -> Vector3:
	return Map.ground_pos(p.x, p.y) + Vector3.UP * 0.12

func _resolve_anchor(value: Variant) -> Vector3:
	if value is Array: return _ground(Vector2(float(value[0]), float(value[1])))
	match str(value):
		"intro": return Intro.start_position()
		"pond": return _ground(Map.POND.pos + Vector2(9, 7))
		"maze": return _ground(game.cornfield.cell_position(Vector2i(1, 0)))
		"bird":
			for candidate in game.cornfield.birds:
				if not candidate.owl:
					bird = candidate
					return _ground(Vector2(bird.home.x, bird.home.z) + Vector2(8, 3))
		"mushroom":
			for item in game.loots:
				if is_instance_valid(item) and item is Loot and item.kind == "mushroom" and not item.taken:
					var at := Vector2(item.global_position.x, item.global_position.z)
					if at.distance_to(Vector2(-48,-45)) > 90: continue
					mushroom = item
					return _ground(at + Vector2(0, 1.5))
		_:
			if game.progression.npcs.has(value):
				var npc: Node3D = game.progression.npcs[value]
				var pos := npc.global_position + npc.global_basis.z * 2.1
				return _ground(Vector2(pos.x, pos.z))
	_fail("Could not resolve scene location: " + str(value))
	return Vector3.ZERO

func _resolve_route() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if shot.kind == "maze":
		# Breadth-first path through the actual maze, never through a corn wall.
		var first := Vector2i(1, 0)
		var goal := Vector2i(11, 12)
		var queue: Array[Vector2i] = [first]
		var previous := {first: first}
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			if cell == goal: break
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = cell + offset
				if game.cornfield.passages.has(next) and not previous.has(next):
					previous[next] = cell
					queue.append(next)
		if not previous.has(goal):
			_fail("Maze has no connected route.")
			return points
		var cell := goal
		while cell != first:
			points.push_front(_ground(game.cornfield.cell_position(cell)))
			cell = previous[cell]
		points.push_front(_ground(game.cornfield.cell_position(first)))
	else:
		for point: Array in shot.get("route", []): points.append(_ground(Vector2(point[0], point[1])))
	return points

func _find_tower_place() -> Vector3:
	for radius in [3.0, 4.0, 5.0, 6.0]:
		for i in 16:
			var at: Vector3 = anchor + Vector3(sin(i * TAU / 16), 0, cos(i * TAU / 16)) * float(radius)
			at = Map.ground_pos(at.x, at.z)
			if game.defences.placement_error(game.player, at).is_empty(): return at
	_fail("No legal tower placement near " + str(anchor))
	return Vector3.ZERO

func _spawn_encounter() -> void:
	var offset: Array = shot.get("enemy_offset", [0, 28])
	var center := Vector2(anchor.x + float(offset[0]), anchor.z + float(offset[1]))
	var count := 1 if shot.kind == "titan" else int(shot.get("enemy_count", 6))
	for i in count:
		var kind: String = "titan" if shot.kind == "titan" else ["shambler", "runner", "shambler"][i % 3]
		var point := center + Vector2(float(i % 4) * 2.0, float(i / 4) * 2.5)
		if not game.spawn_zombie(kind, point, 1.0):
			_fail("Enemy staging failed.")
			return
		var enemy: Zombie = game.zombies_root.get_children().back()
		enemy.set_physics_process(false)
		pending_enemies.append(enemy)
	evidence["spawned"] = count

func _physics_process(delta: float) -> void:
	if not playing or failed or not NetSession.is_host(): return
	var count := 4 if shot.get("coop", false) else 1
	for i in count:
		var p: Player = NetSession.world.actor(peers[i])
		if not p.active or p.mounted_tower or route.size() < 2: continue
		var index: int = route_indices[i]
		if index >= route.size():
			p.velocity = Vector3.ZERO
			continue
		var target := route[index]
		if shot.kind != "maze": target += Vector3(i * 1.2, 0, -float(i % 2))
		var direction := target - p.global_position
		direction.y = 0.0
		if direction.length() < 0.55:
			route_indices[i] = index + 1
			continue
		var speed: float = minf(float(shot.get("speed", 2.8)), Player.WALK_SPEED * p.effective_speed_mul())
		p.velocity.x = direction.normalized().x * speed
		p.velocity.z = direction.normalized().z * speed
		p.velocity.y = -1.0 if p.is_on_floor() else p.velocity.y - 20.0 * delta
		p.move_and_slide()
		_look(p, target + Vector3.UP * Player.EYE, delta * 5.0)
		p._footsteps(delta, true, false)
		p.bob += delta * 9.0
		if i == 0: p.head.position.y = Player.EYE + sin(p.bob) * 0.022

func _look(p: Player, point: Vector3, weight := 1.0) -> void:
	var direction := point - p.camera.global_position
	if direction.length_squared() < 0.0001: return
	var yaw := atan2(-direction.x, -direction.z)
	var pitch := atan2(direction.y, Vector2(direction.x, direction.z).length())
	p.rotation.y = lerp_angle(p.rotation.y, yaw, clampf(weight, 0, 1))
	p.pitch = lerpf(p.pitch, clampf(pitch, -1.4, 1.4), clampf(weight, 0, 1))
	p.head.rotation.x = p.pitch

func _target(p: Player, index: int) -> Zombie:
	var candidates: Array[Zombie] = []
	for enemy: Zombie in pending_enemies:
		if is_instance_valid(enemy) and enemy.alive: candidates.append(enemy)
	if candidates.is_empty(): return null
	for j in candidates.size():
		var enemy := candidates[(j + index) % candidates.size()]
		var at := enemy.global_position + Vector3.UP * enemy.height * 0.65
		var exclude: Array[RID] = [p.get_rid()]
		if is_instance_valid(tower): exclude.append(tower.body.get_rid())
		var query := PhysicsRayQueryParameters3D.create(p.camera.global_position, at, 1 | 8, exclude)
		if game.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return enemy
	return null

func _tick(delta: float, frame: int) -> void:
	if NetSession.roster.size() != 4 or NetSession.phase != "running":
		_fail("Lost a real multiplayer client during a scene.")
		return
	if shot.kind in ["studio", "intro"]:
		if shot.kind == "intro" or local_time < 4.75: game.intro._process(delta)
		if shot.kind == "studio":
			game.intro._black.show()
			game.intro._black.color.a = 1.0
		else:
			game.intro._music.stop()
			game.intro._music.bus = MUTED_MUSIC
	if shot.kind == "mushroom" and local_time >= 3.0 and not cues_done.has("pickup"):
		cues_done.pickup = true
		var key := str(mushroom.get_meta("coop_id", ""))
		var kind := mushroom.id
		var before: int = NetSession.world.mushrooms[1].get(kind, 0)
		_command(0, "interact", [key])
		evidence.pickup = int(NetSession.world.mushrooms[1].get(kind, 0)) == before + 1
	if shot.kind == "npc": _npc_tick()
	if shot.kind == "birds" and local_time > 3.0 and not cues_done.has("birds"):
		cues_done.birds = true
		bird.scare(bird.home)
		evidence.birds = bird.flying > 0
	if shot.kind == "tower": _tower_tick()
	if shot.kind in ["combat", "titan", "tower"] and not shot.get("reveal_only", false):
		_fight_tick(delta, frame)
	if shot.kind == "fireworks": _firework_tick()
	_count_shots()
	if shot.kind != "studio":
		if game.intro._music.playing or not AudioServer.is_bus_mute(AudioServer.get_bus_index(MUTED_MUSIC)):
			_fail("Music guard failed during gameplay.")
			return
	if not game.player.alive or game.over:
		_fail("Staged player died; retake needs a different encounter.")
		return
	_camera(local_time / float(shot.seconds))
	# Hide developer counters, retain useful gameplay HUD and actual teammate nameplates.
	game.hud.fps_label.hide()
	if shot.get("ads", false): Input.action_press("aim")

func _npc_tick() -> void:
	if local_time >= 1.5 and not cues_done.has("dialog"):
		cues_done.dialog = true
		game.progression.interact(str(shot.npc))
		evidence.dialog = game.progression.is_open
	if shot.has("quest") and local_time >= 3.0 and not cues_done.has("quest"):
		cues_done.quest = true
		_command(0, "shop", [str(shot.npc), "quest", str(shot.quest), ""])
		evidence.quest = game.progression.data(1).accepted.get(shot.quest, false)
	if local_time >= float(shot.seconds) - 1.5: game.progression.close()

func _tower_tick() -> void:
	if local_time >= 1.5 and not cues_done.has("build"):
		cues_done.build = true
		_command(0, "tower_place", [tower_point, PI, "standard"])
		if game.defences.towers.is_empty():
			_fail("Real tower purchase was rejected.")
			return
		tower = game.defences.towers.values().back()
		evidence.built = true
	if is_instance_valid(tower) and shot.get("tower_action") == "fire" and local_time >= 3.0 and not cues_done.has("mount"):
		cues_done.mount = true
		_command(0, "tower_mount", [tower.tower_id])
		evidence.mounted = game.player.mounted_tower == tower.tower_id
	if is_instance_valid(tower) and shot.get("tower_action") == "build":
		_look(game.player, tower.global_position + Vector3.UP * 1.8)

func _fight_tick(delta: float, frame: int) -> void:
	if local_time < 0.8: return
	Input.action_release("fire")
	var count := 4 if shot.get("coop", false) else 1
	for i in count:
		var p: Player = NetSession.world.actor(peers[i])
		var w: Weapons = NetSession.world.weapons[peers[i]]
		var enemy := _target(p, i)
		if enemy == null: continue
		_look(p, enemy.global_position + Vector3.UP * enemy.height * 0.65, delta * 9.0)
		if p.mounted_tower:
			_command(i, "tower_control", [p.mounted_tower, float(p.rotation.y), float(p.pitch), true, false])
		elif i == 0:
			# Let automatic guns retain their native cadence and sustained sound.
			if Weapons.DEFS[w.current].auto: Input.action_press("fire")
			elif frame % maxi(1, int(float(Weapons.DEFS[w.current].rate) * fps) + 1) == 0:
				_command(i, "fire", [w.current, float(w.ads), float(p.rotation.y), float(p.pitch)])
		elif frame % 3 == 0:
			# These operations originate on each actual client and pass the game's ENet validator.
			if int(w.cur().ammo) == 0: _command(i, "reload", [])
			else: _command(i, "fire", [w.current, 0.0, float(p.rotation.y), float(p.pitch)])

func _count_shots() -> void:
	for i in (4 if shot.get("coop", false) else 1):
		var w: Weapons = NetSession.world.weapons[peers[i]]
		var ammo := int(w.cur().ammo)
		if ammo < int(old_ammo[i]): shot_counts[i] += int(old_ammo[i]) - ammo
		old_ammo[i] = ammo

func _firework_tick() -> void:
	for index in shot.get("cues", []).size():
		var cue: Dictionary = shot.cues[index]
		if local_time < float(cue.at) or cues_done.has(index): continue
		cues_done[index] = true
		var i := int(cue.actor)
		var p: Player = NetSession.world.actor(peers[i])
		p.rotation.y = PI
		p.pitch = 0.12
		p.head.rotation.x = p.pitch
		_command(i, "firework", [str(cue.item), float(p.rotation.y), float(p.pitch)])

func _camera(k: float) -> void:
	var style := str(shot.camera)
	camera.fov = 72.0 if style == "sky" else 60.0
	if style == "fp_sky":
		if local_time > 2: _look(game.player, anchor + Vector3(0, 26, 10), 0.035)
		return
	if style == "fp": return
	var at := anchor + Vector3.UP * 1.6
	var eye := anchor + Vector3(6, 3, 10)
	match style:
		"crane":
			if shot.anchor is String and shot.anchor == "maze": at = _ground(game.cornfield.cell_position(Vector2i(6, 6)))
			eye = at + Vector3(lerpf(15, -10, k), lerpf(10, 22, k), 24)
		"orbit":
			if shot.anchor is String and shot.anchor == "pond": at = _ground(Map.POND.pos)
			var angle := lerpf(-0.5, 0.5, k)
			eye = at + Vector3(sin(angle) * 12, 3.0, cos(angle) * 12)
		"detail":
			at = bird.global_position + Vector3.UP * 0.25
			eye = bird.home + Vector3(3.6 - k, 1.0 + k * 0.5, 3.0)
		"follow":
			at = NetSession.world.actor(peers[2]).global_position + Vector3.UP * 1.3
			eye = at + Vector3(5, 2.4, 8)
		"side":
			at = NetSession.world.actor(peers[2]).global_position + Vector3.UP * 1.4
			eye = at + Vector3(10 - k * 3, 3, -7)
			if shot.kind == "titan":
				eye = anchor + Vector3(12 - k * 3, 2.7, -6)
				at = anchor + Vector3(2, 7, 23)
		"low":
			eye = anchor + Vector3(3 - k * 4, 0.65, -4)
			if not pending_enemies.is_empty():
				var enemy := pending_enemies[0]
				if is_instance_valid(enemy): at = enemy.global_position + Vector3.UP * enemy.height * 0.6
		"sky":
			eye = anchor + Vector3(8 - k * 3, 4.0, -16)
			# Establish the teammates and their launches before tilting toward the bursts.
			at = anchor + Vector3(3, lerpf(3.0, 18.0, smoothstep(0.15, 0.65, k)), 28)
	eye.y = maxf(eye.y, Map.ground_height(eye.x, eye.z) + 0.6)
	camera.global_position = eye
	if not eye.is_equal_approx(at): camera.look_at(at)

func _verify_shot() -> bool:
	var ok := true
	if shot.kind == "mushroom": ok = evidence.get("pickup", false)
	if shot.kind == "npc":
		ok = evidence.get("dialog", false)
		if shot.has("quest"): ok = ok and evidence.get("quest", false)
	if shot.kind == "birds": ok = evidence.get("birds", false)
	if shot.kind in ["travel", "maze", "intro"]:
		for i in (4 if shot.get("coop", false) else 1):
			var p: Player = NetSession.world.actor(peers[i])
			var distance: float = p.global_position.distance_to(start_positions[i])
			evidence["distance_%d" % i] = distance
			ok = ok and distance > 1.0
	if shot.kind in ["combat", "titan"] and not shot.get("reveal_only", false):
		ok = int(shot_counts[0]) > 0
		if shot.get("coop", false):
			for i in range(1, 4): ok = ok and int(shot_counts[i]) > 0
	if shot.kind == "tower":
		ok = evidence.get("built", false)
		if shot.get("tower_action") == "fire":
			ok = ok and evidence.get("mounted", false) and is_instance_valid(tower) and tower.shots > 0
			if is_instance_valid(tower): evidence.tower_shots = tower.shots
	if shot.kind == "fireworks":
		var expected := {}
		for cue: Dictionary in shot.cues:
			var key := "%d:%s" % [int(cue.actor), cue.item]
			expected[key] = int(expected.get(key, 0)) + 1
		for key: String in expected:
			var index := int(key.get_slice(":", 0))
			var item := key.get_slice(":", 1)
			var used: int = 2 - int(game.fireworks.stock(peers[index])[item])
			evidence[key] = used
			ok = ok and used == int(expected[key])
	evidence["shots"] = shot_counts.duplicate()
	reports.append({"id": shot.id, "passed": ok, "evidence": evidence.duplicate(true)})
	_write("scene-reports", {"reports": reports})
	if not ok:
		_fail("Scene action checks failed: " + str(shot.id) + " " + JSON.stringify(evidence))
	return ok
