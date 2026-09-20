extends SceneTree

var game: Node3D
var NetSession: Node
var role := "host"
var folder := ProjectSettings.globalize_path("res://../artifacts/multiplayer/")
var checks := 0
var failures := 0
var test_port := 24687
var started_at := Time.get_ticks_msec()
var step_seen := -1
var test_step := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--coop-role="): role = arg.trim_prefix("--coop-role=")
		if arg.begins_with("--coop-port="): test_port = int(arg.trim_prefix("--coop-port="))
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 420000:
		push_error("COOP_TEST_TIMEOUT " + role)
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true).timeout

func write_json(name: String, data: Variant) -> void:
	var file := FileAccess.open(folder + name + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func read_json(name: String) -> Variant:
	if not FileAccess.file_exists(folder + name + ".json"): return null
	return JSON.parse_string(FileAccess.get_file_as_string(folder + name + ".json"))

func run() -> void:
	NetSession = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._flags.append("--all-forest-keys") # Keep the team-key pickup test deterministic.
	current_scene = game
	while not game.navigation_ready: await process_frame
	game.settings._testing = true
	game.achievements.hide()
	if role == "host": await host_run()
	else: await client_run()

func command_clients(action: String, targets: Array, args: Array = []) -> void:
	test_step += 1
	var minimum_sequence: int = NetSession._sequence + (1 if NetSession.phase == "running" else 0)
	write_json("step", {"number": test_step, "action": action, "targets": targets, "args": args, "minimum_sequence": minimum_sequence})
	var deadline := Time.get_ticks_msec() + (90000 if action == "rejoin" else 12000)
	while Time.get_ticks_msec() < deadline:
		var done := true
		for target in targets:
			var report = read_json("done-" + target)
			if not report is Dictionary or int(report.get("step", -1)) != test_step: done = false
		if done: return
		await wait_seconds(0.1)
	check(false, "Clients acknowledged " + action)

func find_peer(label: String) -> int:
	for id in NetSession.roster:
		if NetSession.roster[id] == label: return id
	return 0

func teleport(id: int, point: Vector3) -> void:
	var p: Player = NetSession.world.actor(id)
	p.global_position = point
	p.velocity = Vector3.ZERO
	NetSession._world_state.rpc_id(id, NetSession.epoch, NetSession._sequence, NetSession.world.snapshot(), true)
	await wait_seconds(0.4)

func verify_menu(kind: String, is_host: bool) -> void:
	var before: float = game.day_night.clock_seconds
	var sequence: int = NetSession._received_sequence
	match kind:
		"pause": game._pause()
		"inventory": game.inventory.open()
		"shop": game.progression.interact("camp")
		"barricades": game.barricade_menu.open()
	check(not game.player.active and not paused, role + " opens " + kind + " without pausing the world")
	game.settings._testing = false
	game.settings._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.settings._testing = true
	check(game.hud.overlay.visible == (kind == "pause"), role + " focus loss does not stack menus during " + kind)
	if is_host:
		var remote: Player = NetSession.world.actor(find_peer("c3"))
		var position_before := remote.global_position
		await command_clients("walk", ["c3"])
		check(remote.global_position.distance_to(position_before) > 1.0, "Other player moves while host opens " + kind)
	else:
		await wait_seconds(0.6)
		check(NetSession._received_sequence > sequence, role + " receives snapshots during " + kind)
	check(game.day_night.clock_seconds > before, role + " world advances during " + kind)
	match kind:
		"pause": game._on_start()
		"inventory": game.inventory.close()
		"shop": game.progression.close()
		"barricades": game.barricade_menu.close()
	check(game.player.active and not paused, role + " resumes after " + kind)

func host_run() -> void:
	check(NetSession.join("not-an-ip", "test", test_port) == ERR_INVALID_PARAMETER and not NetSession.enabled, "Invalid IP rejected without entering a session")
	check(NetSession.host("Host", test_port) == OK, "Host binds an ENet UDP socket")
	var occupied := ENetMultiplayerPeer.new()
	check(occupied.create_server(test_port, 3) != OK, "A second host cannot bind the same port")
	occupied.close()
	write_json("host-ready", {"port": test_port})
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		if NetSession.roster.size() == 4 and not false in NetSession.ready_peers.values(): break
		await wait_seconds(0.2)
	check(NetSession.roster.size() == 4, "Host plus three clients share the lobby")
	if NetSession.roster.size() != 4:
		quit(1)
		return
	check(not false in NetSession.ready_peers.values(), "All four maps are ready")
	NetSession.start_game()
	game.waves.timer = 10000.0
	game.player.set_physics_process(false)
	await wait_seconds(1.0)
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]:
		var report: Dictionary = read_json("done-" + label)
		check(report.players == 4 and report.avatars == 3 and report.started, label + " sees four players and three avatars")
	var c1 := find_peer("c1")
	var c2 := find_peer("c2")
	var c3 := find_peer("c3")
	var clock_before: float = game.day_night.clock_seconds
	game._pause()
	await wait_seconds(0.5)
	check(not paused and game.day_night.clock_seconds > clock_before, "Host pause menu leaves world clock running")
	game._on_start()
	for menu in ["pause", "inventory", "shop", "barricades"]:
		var original_position: Vector3 = game.player.global_position
		game.player.global_position = game.progression.npcs.camp.global_position + Vector3(0, 0.1, 2.3)
		await wait_seconds(0.1)
		await verify_menu(menu, true)
		game.player.global_position = original_position
	var moving_from: Vector3 = NetSession.world.actor(c1).global_position
	await command_clients("walk", ["c1"])
	await wait_seconds(0.5)
	check(NetSession.world.actor(c1).global_position.distance_to(moving_from) > 1.0, "Client walking replicates through host collision")
	for id in [c1, c2, c3]: NetSession.world.actor(id).score = 1000
	await wait_seconds(0.5)
	await command_clients("upgrade", ["c1"], ["w_ak47"])
	await wait_seconds(0.4)
	check(not NetSession.world.weapons[c1].unlocked.ak47 and NetSession.world.actor(c1).score == 1000, "Legacy remote weapon unlock rejected")
	await command_clients("shop", ["c1"], ["camp", "weapon", "ak47", ""])
	await wait_seconds(0.3)
	check(not NetSession.world.weapons[c1].unlocked.ak47, "Remote NPC purchase cannot bypass proximity")
	game.waves.completed = 4
	game.progression.data(c1).claimed = {"arrival": true, "line": true}
	await teleport(c1, game.progression.npcs.camp.global_position + Vector3(0, 0.1, 2.3))
	await command_clients("shop", ["c1"], ["camp", "weapon", "ak47", ""])
	await wait_seconds(0.4)
	check(NetSession.world.weapons[c1].unlocked.ak47 and NetSession.world.actor(c1).score == 220, "Eligible NPC weapon purchase is charged once by host")
	await command_clients("shop", ["c1"], ["camp", "weapon", "ak47", ""])
	await wait_seconds(0.3)
	check(NetSession.world.actor(c1).score == 220, "Duplicate purchase cannot spend twice")
	NetSession.world.actor(c1).score = 1000
	await command_clients("shop", ["c1"], ["camp", "skin", "forest", "ak47"])
	await wait_seconds(0.4)
	await command_clients("inspect", ["c1", "c2"])
	check(NetSession.world.weapons[c1].skins.get("ak47") == "forest" and read_json("done-c1").skins.get("ak47") == "forest", "Purchased weapon skin replicates to owner")
	check(read_json("done-c2").progress_people > 1, "Individual quest state reaches the other peers")
	await teleport(c2, game.progression.npcs.camp.global_position + Vector3(0, 0.1, 2.3))
	await command_clients("menus", ["c2"])
	var menu_report: Dictionary = read_json("done-c2")
	check(not menu_report.paused and not paused, "Client menus do not pause the common world")
	# A controlled target uses the real zombie collider and real network fire command.
	var at := Map.ground_pos(8, -13) + Vector3.UP * 0.3
	await teleport(c1, at)
	game.spawn_zombie("shambler", Vector2(8, -19), 1.0)
	var z: Zombie = game.zombies_root.get_children().back()
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.global_position = Map.ground_pos(8, -19)
	var hp := z.hp
	await wait_seconds(0.6)
	await command_clients("shoot", ["c1"], [[z.global_position.x, z.global_position.y + 1.2, z.global_position.z]])
	await wait_seconds(0.6)
	check(z.hp < hp, "Remote AK shot damages the host zombie")
	check(NetSession.world.weapons[c1].state.ak47.ammo == 29, "Exactly one round consumed on host")
	await command_clients("inspect", ["c2", "c3"])
	for label in ["c2", "c3"]:
		check(read_json("done-"+label).zombies == 1, label + " receives the same zombie")
	await command_clients("reload", ["c1"])
	await wait_seconds(2.5)
	check(NetSession.world.weapons[c1].state.ak47.ammo == 30, "Remote reload completes on the host")
	# Invalid fire and movement requests cannot unlock guns or teleport.
	var before: Vector3 = NetSession.world.actor(c2).global_position
	await command_clients("invalid", ["c2"])
	await wait_seconds(0.4)
	check(not NetSession.world.weapons[c2].unlocked.ak47, "Locked weapon request rejected")
	check(NetSession.world.actor(c2).global_position.distance_to(before) < 1.0, "Impossible movement request rejected")
	# The same world pickup is contended by two clients.
	var item: Node3D
	for node in NetSession.world.loot_nodes.values():
		if node is Loot and node.kind == "mushroom":
			item = node
			break
	var item_id := str(item.get_meta("coop_id"))
	var kind: String = item.id
	await teleport(c1, item.global_position + Vector3(0.7, 0.1, 0))
	await teleport(c2, item.global_position + Vector3(-0.7, 0.1, 0))
	await command_clients("interact", ["c1", "c2"], [item_id])
	await wait_seconds(0.6)
	check(NetSession.world.mushrooms[c1][kind] + NetSession.world.mushrooms[c2][kind] == 1, "Contended pickup granted exactly once")
	var key: ForestKey = game.forest_keys.spawned[0]
	var key_id := key.key_id
	await teleport(c3, key.global_position + Vector3(0.7, 0.1, 0))
	await command_clients("interact", ["c3"], [str(key.get_meta("coop_id"))])
	await wait_seconds(0.5)
	check(game.forest_keys.has_key(key_id), "Client collects a team key on host")
	await command_clients("inspect", ["c1"])
	check(read_json("done-c1").keys > 0, "Team key propagated to another client")
	var door: Door
	for node in NetSession.world.loot_nodes.values():
		if node is Door and node.key_id == key_id and node.width > 1.4:
			door = node
			break
	await teleport(c1, door.to_global(Vector3(-2.0, 0.1, 0)))
	await command_clients("interact", ["c1"], [str(door.get_meta("coop_id"))])
	await wait_seconds(1.0)
	check(door.is_open, "Different client opens door with the shared key")
	var bar: Barricade = game.barricades[0]
	await teleport(c1, bar.center + Vector3(bar.normal2.x, 0.0, bar.normal2.y) * 3.0 + Vector3.UP * 0.1)
	await command_clients("build", ["c1"], [0])
	await wait_seconds(0.5)
	check(bar.level == 1, "Remote barricade purchase builds real collision")
	bar.damage(40.0)
	await command_clients("repair", ["c1"], [0])
	await wait_seconds(0.4)
	check(bar.hp == bar.max_hp(), "Remote repair restores host barricade")
	await command_clients("inspect", ["c2"])
	check(read_json("done-c2").bar == 1 and read_json("done-c2").open_doors > 0, "Door and barricade states reach other peers")
	# Real remote building commands, autonomous fire, boss telegraphs and late join.
	await teleport(c2, Map.ground_pos(60, 117) + Vector3.UP * 0.1)
	var tower_score: int = NetSession.world.actor(c2).score
	await command_clients("tower_place", ["c2"], [[60, Map.ground_height(60, 112), 112]])
	await wait_seconds(0.5)
	check(game.defences.towers.size() == 1 and NetSession.world.actor(c2).score == tower_score - 120, "Remote tower placement creates one host tower and charges builder")
	await command_clients("tower_place", ["c2"], [[60, Map.ground_height(60, 112), 112]])
	await wait_seconds(0.3)
	check(game.defences.towers.size() == 1 and NetSession.world.actor(c2).score == tower_score - 120, "Duplicate remote tower placement rejected")
	var tower: DefenceTower = game.defences.towers.values()[0]
	await command_clients("tower_upgrade", ["c2"], [tower.tower_id])
	await wait_seconds(0.4)
	check(tower.level == 1, "Remote turret upgrade requires the mechanic")
	await command_clients("tower_rotate", ["c2"], [tower.tower_id, 0.4])
	await wait_seconds(0.4)
	check(is_equal_approx(tower.rotation.y, 0.4), "Remote tower rotation is authoritative")
	await command_clients("inspect", ["c1"])
	check(is_equal_approx(float(read_json("done-c1").tower_yaw), 0.4), "Tower heading replicates to other players")
	await teleport(c2, game.progression.npcs.mechanic.global_position + Vector3(0, 0.1, 2.3))
	await command_clients("shop", ["c2"], ["mechanic", "tower_upgrade", str(tower.tower_id), ""])
	await wait_seconds(0.4)
	check(tower.level == 2 and tower.hp == 400, "NPC turret upgrade applies on host")
	await teleport(c2, Map.ground_pos(60, 117) + Vector3.UP * 0.1)
	tower.damage(100)
	await command_clients("tower_repair", ["c2"], [tower.tower_id])
	await wait_seconds(0.4)
	check(tower.hp == 400, "Remote tower repair restores shared health")
	game.spawn_zombie("shambler", Vector2(60, 99), 1)
	var tower_target: Zombie = game.zombies_root.get_children().back()
	tower_target.set_physics_process(false)
	tower_target.agent.avoidance_enabled = false
	tower_target.hp = 10000
	await wait_seconds(2.5)
	await command_clients("inspect", ["c1"])
	check(tower.shots > 0 and tower_target.hp < 10000 and read_json("done-c1").tower_shots > 0, "Host turret fire and target damage replicate")
	game.waves.wave = 8
	game.spawn_zombie("titan", Vector2(20, 125), 1, "east")
	var titan: Titan = game.zombies_root.get_children().back()
	titan.set_physics_process(false)
	titan.agent.avoidance_enabled = false
	titan.begin_strike(Map.ground_pos(20, 121))
	await wait_seconds(0.5)
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]:
		var report: Dictionary = read_json("done-" + label)
		check(report.titans == 1 and report.boss_phase == "windup" and report.boss_max_hp == titan.max_hp, label + " receives full titan health and exact attack phase")
		check(report.boss_model == titan.model_path and int(report.boss_seed) == titan.appearance_seed and report.boss_height == titan.height, label + " sees the same boss model, size and appearance")
		check(int(report.titan_cues.get("arrival", 0)) == 1 and int(report.titan_cues.get("windup", 0)) == 1, label + " hears one arrival and one attack cry from the host")
	titan.emit_cue("step")
	titan.emit_cue("rage")
	titan.resolve_strike()
	titan.strike_phase = "recovery"
	await wait_seconds(0.4)
	await command_clients("inspect", ["c1", "c2", "c3"])
	check(read_json("done-c1").boss_impact == titan.impact_serial, "Boss impact event reaches client")
	for label in ["c1", "c2", "c3"]:
		var cues: Dictionary = read_json("done-" + label).titan_cues
		check(int(cues.get("step", 0)) == 1 and int(cues.get("rage", 0)) == 1 and int(cues.get("slam", 0)) == 1, label + " receives exactly one synchronized footstep, rage cry and slam")
	titan.die(Vector3.ZERO)
	await wait_seconds(2.0)
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]:
		var cues: Dictionary = read_json("done-" + label).titan_cues
		check(int(cues.get("death", 0)) == 1 and int(cues.get("collapse", 0)) == 1, label + " hears death and delayed body impact without replica duplicates")
	titan.queue_free()
	tower_target.queue_free()
	await wait_seconds(0.4)
	await command_clients("rejoin", ["c3"])
	c3 = find_peer("c3")
	check(c3 > 1 and NetSession.roster.size() == 4, "A player can reconnect to an ongoing round")
	var joined: Dictionary = read_json("done-c3")
	check(joined.started and joined.bar == 1 and joined.keys > 0 and joined.open_doors > 0 and joined.zombies == 1, "Late join restores doors, keys, barricades and enemies")
	check(joined.towers == 1 and joined.tower_hp == 400, "Late join restores upgraded tower and exact structure health")
	check(joined.titan_cues.is_empty(), "Late join does not replay earlier titan roars or impacts")
	tower.damage(10000)
	await wait_seconds(0.5)
	await command_clients("wait_tower_removed", ["c3"])
	check(read_json("done-c3").towers == 0, "Destroyed tower disappears on other peers")
	# A downed player leaves the team fighting; another player revives them.
	await teleport(c2, Map.ground_pos(-5, -12) + Vector3.UP * 0.1)
	await teleport(c3, Map.ground_pos(-6.5, -12) + Vector3.UP * 0.1)
	NetSession.world.actor(c2).damage(10000.0)
	await wait_seconds(0.4)
	check(not game.over and not NetSession.world.actor(c2).alive, "One death does not end coop")
	await command_clients("revive", ["c3"], [c2])
	await wait_seconds(3.6)
	check(NetSession.world.actor(c2).alive and NetSession.world.actor(c2).hp >= 50.0, "Host completes the three-second revive")
	await command_clients("inspect", ["c2"])
	check(read_json("done-c2").alive, "Revived client regains life state")
	await command_clients("grenade", ["c1"])
	await wait_seconds(0.5)
	check(NetSession.world.grenades.size() > 0, "Remote grenade exists on host")
	await wait_seconds(3.0)
	check(NetSession.world.grenades.is_empty(), "Host grenade explodes and despawns")
	await command_clients("inspect", ["c2"])
	check(read_json("done-c2").grenades == 0, "Grenade removal reaches clients")
	# ENet capacity is host + three incoming peers.
	var extra := ENetMultiplayerPeer.new()
	extra.create_client("127.0.0.1", test_port, 3)
	for frame in 100:
		extra.poll()
		await wait_seconds(0.02)
	check(extra.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED, "Fifth player is refused by ENet capacity")
	extra.close()
	for i in Waves.MAX_ACTIVE - 1:
		game.spawn_zombie("shambler", Vector2(-20 + i % 8 * 2, -30 - i / 8 * 2), 1.0)
		var enemy: Zombie = game.zombies_root.get_children().back()
		enemy.set_physics_process(false)
		enemy.agent.avoidance_enabled = false
	await wait_seconds(1.0)
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]: check(read_json("done-"+label).zombies == Waves.MAX_ACTIVE, label + " assembles full-capacity horde snapshots")
	var earned_before: int = NetSession.world.actor(c1).score
	z.killer_peer = c1
	z.damage(10000.0, Vector3.FORWARD)
	await wait_seconds(0.5)
	check(NetSession.world.actor(c1).score > earned_before, "Remote killer receives authoritative kill rewards")
	await command_clients("inspect", ["c2"])
	check(read_json("done-c2").alive_zombies == Waves.MAX_ACTIVE - 1, "Zombie death reaches another client")
	# Team defeat and an in-session restart.
	for p: Player in NetSession.world.actors.values(): p.damage(10000)
	await wait_seconds(0.7)
	check(game.over and NetSession.phase == "over", "Only team wipe ends the match")
	await command_clients("inspect", ["c1"])
	check(read_json("done-c1").over, "Team game over propagated")
	NetSession.restart()
	deadline = Time.get_ticks_msec() + 100000
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(NetSession.game) and NetSession.game.navigation_ready and NetSession.ready_peers.size() == 4 and not false in NetSession.ready_peers.values(): break
		await wait_seconds(0.25)
	game = NetSession.game
	check(is_instance_valid(game) and game.navigation_ready and NetSession.roster.size() == 4, "Session survives host restart with four peers")
	await wait_seconds(0.5)
	check(NetSession.phase == "running" and game.player.hp == 100.0 and not game.over, "Restart resets the run and starts the next round once every peer is ready")
	NetSession.start_game()
	game.waves.timer = 10000.0
	await wait_seconds(0.5)
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]: check(read_json("done-"+label).started, label + " starts the second round")
	check(game.defences.towers.is_empty(), "Session restart removes towers from previous round")
	var orphan: DefenceTower = game.defences.create_tower(Map.ground_pos(60, 112), c3)
	await command_clients("exit", ["c3"])
	await wait_seconds(0.7)
	check(NetSession.roster.size() == 3 and NetSession.world.actors.size() == 3, "Disconnected player is removed")
	check(orphan.owner_peer == 1, "Host inherits towers when their builder disconnects")
	test_step += 1
	write_json("step", {"number": test_step, "action": "wait_host_left", "targets": ["c1", "c2"], "args": []})
	await wait_seconds(0.2)
	NetSession.leave("Integration test finished")
	deadline = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var a = read_json("done-c1")
		var b = read_json("done-c2")
		if a is Dictionary and b is Dictionary and int(a.step) == test_step and int(b.step) == test_step: break
		await wait_seconds(0.2)
	for label in ["c1", "c2"]:
		var report: Dictionary = read_json("done-"+label)
		check(int(report.step) == test_step and report.get("offline", false), label + " returns to menu when host leaves")
	print("COOP_TEST_DONE checks=%d failures=%d" % [checks, failures])
	write_json("result", {"checks": checks, "failures": failures})
	quit(0 if failures == 0 else 1)

func client_run() -> void:
	while not FileAccess.file_exists(folder + "host-ready.json"): await wait_seconds(0.2)
	check(NetSession.join("127.0.0.1", role, test_port) == OK, "Client creates connection")
	while true:
		await wait_seconds(0.1)
		if is_instance_valid(NetSession.game):
			game = NetSession.game
			game.player.set_physics_process(false)
			game.player.set_process_unhandled_input(false)
		var request = read_json("step")
		if not request is Dictionary or int(request.number) <= step_seen or not role in request.targets: continue
		step_seen = int(request.number)
		var args: Array = request.args
		if request.action in ["build", "repair", "revive", "tower_upgrade", "tower_repair", "tower_sell"]: args[0] = int(args[0])
		if request.action == "tower_rotate":
			args[0] = int(args[0])
			args[1] = float(args[1])
		match request.action:
			"wait_tower_removed":
				var deadline := Time.get_ticks_msec() + 5000
				while not game.defences.towers.is_empty() and Time.get_ticks_msec() < deadline:
					await wait_seconds(0.1)
			"tower_place": NetSession.command("tower_place", [Vector3(args[0][0], args[0][1], args[0][2])])
			"menus":
				for menu in ["pause", "inventory", "shop", "barricades"]:
					await verify_menu(menu, false)
			"walk":
				game.player.set_physics_process(true)
				Input.action_press("move_forward")
				await wait_seconds(0.75)
				Input.action_release("move_forward")
				await wait_seconds(0.2)
				game.player.set_physics_process(false)
			"rejoin":
				NetSession.leave()
				while not is_instance_valid(NetSession.game) or not NetSession.game.navigation_ready: await wait_seconds(0.1)
				game = NetSession.game
				NetSession.join("127.0.0.1", role, test_port)
				while NetSession.phase != "running" or not game.started: await wait_seconds(0.1)
				game.player.set_physics_process(false)
			"wait_host_left":
				while NetSession.enabled or not is_instance_valid(NetSession.game) or not NetSession.game.navigation_ready: await wait_seconds(0.1)
				write_json("done-"+role, {"step": step_seen, "offline": not NetSession.enabled and NetSession.game.hud.overlay.visible})
				print("COOP_CLIENT_DONE ", role)
				quit(0)
				return
			"shoot":
				game.weapons.set_weapon("ak47")
				game.player.camera.look_at(Vector3(args[0][0], args[0][1], args[0][2]))
				game.weapons.try_fire()
			"reload": game.weapons.reload()
			"grenade": game.weapons.throw_grenade()
			"invalid":
				NetSession.command("fire", ["ak47", 0.0, 0.0, 0.0])
				NetSession._pose.rpc_id(1, NetSession.epoch, Vector3(99999, 5000, 99999), 0.0, 0.0, false, Vector3.ZERO)
			"exit", "finish":
				write_json("done-"+role, {"step": step_seen})
				print("COOP_CLIENT_DONE ", role)
				quit(0)
				return
			"inspect":
				# During play, inspect a snapshot produced after this request.
				# Game over sends one final reliable state, then stops snapshots.
				# Disk coordination can otherwise overtake the real UDP packets.
				var deadline := Time.get_ticks_msec() + 5000
				while NetSession._received_sequence < int(request.get("minimum_sequence", -1)) and Time.get_ticks_msec() < deadline:
					await wait_seconds(0.1)
				check(NetSession._received_sequence >= int(request.get("minimum_sequence", -1)), role + " received fresh world state for inspection")
			_: NetSession.command(request.action, args)
		await wait_seconds(0.2)
		var open_doors := 0
		for item in game.loots:
			if is_instance_valid(item) and item is Door and item.is_open: open_doors += 1
		var zombie_count := 0
		var titan_count := 0
		var boss_phase := ""
		var boss_max_hp := 0.0
		var boss_impact := 0
		var boss_model := ""
		var boss_seed := 0
		var boss_height := 0.0
		for node in game.zombies_root.get_children():
			if node is Zombie: zombie_count += 1
			if node is Titan:
				titan_count += 1
				boss_phase = node.strike_phase
				boss_max_hp = node.max_hp
				boss_impact = node.impact_serial
				boss_model = node.model_path
				boss_seed = node.appearance_seed
				boss_height = node.height
		var tower_shots := 0
		var presence := game.get_node_or_null("TitanPresence") as TitanPresence
		var titan_cues: Dictionary = presence.received.duplicate() if presence else {}
		var tower_hp := 0.0
		for tower: DefenceTower in game.defences.towers.values():
			tower_shots += tower.shots
			tower_hp += tower.hp
		write_json("done-"+role, {"step": step_seen, "players": NetSession.roster.size(), "avatars": NetSession.world.avatars.size(),
			"towers": game.defences.towers.size(), "tower_shots": tower_shots, "tower_hp": tower_hp,
			"tower_yaw": game.defences.towers.values()[0].rotation.y if game.defences.towers.size() else 0.0,
			"skins": game.weapons.skins, "progress_people": game.progression.people.size(),
			"titans": titan_count, "boss_phase": boss_phase, "boss_max_hp": boss_max_hp, "boss_impact": boss_impact,
			"boss_model": boss_model, "boss_seed": boss_seed, "boss_height": boss_height,
			"titan_cues": titan_cues,
			"started": game.started, "paused": paused, "alive": game.player.alive, "over": game.over,
			"bar": game.barricades[0].level, "open_doors": open_doors,
			"alive_zombies": game.alive_zombies(),
			"zombies": zombie_count, "grenades": NetSession.world.grenades.size(), "keys": game.forest_keys.owned.size()})
