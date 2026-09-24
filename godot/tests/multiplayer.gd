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

func command_clients(action: String, targets: Array, args: Array = [], next_snapshot := true) -> void:
	test_step += 1
	var minimum_sequence: int = NetSession._sequence + (1 if next_snapshot and NetSession.phase == "running" else 0)
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

func check_leaderboard(report: Dictionary, label: String) -> void:
	var expected = JSON.parse_string(JSON.stringify(game.stats.leaderboard_rows()))
	var received: Array = report.get("leaderboard", []).duplicate(true)
	var valid_pings := not received.is_empty()
	for row: Dictionary in received:
		var ping := int(row.get("ping_ms", -2))
		valid_pings = valid_pings and (ping == -1 if not row.connected else ping == 0 if int(row.id) == 1 else ping >= 0)
		row.erase("ping_ms") # Live RTT can change while the disk-based test handshake completes.
	for row: Dictionary in expected: row.erase("ping_ms")
	check(valid_pings, label + " receives measured peer pings, zero host ping and no stale disconnected ping")
	check(received == expected, label + " receives all authoritative leaderboard rows, points and counters")

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
	if "--test-coop-intro" in OS.get_cmdline_user_args():
		game._flags.erase("--smoke-test")
		game._flags.erase("--no-intro")
	NetSession.start_game()
	if "--test-coop-intro" in OS.get_cmdline_user_args(): await verify_intro()
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
	game.progression.data(c1).claimed = {"arrival": true, "line": true, "night_shift": true}
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
	check_leaderboard(read_json("done-c1"), "After purchase")
	check(read_json("done-c2").progress_people > 1, "Individual quest state reaches the other peers")
	await teleport(c2, game.progression.npcs.camp.global_position + Vector3(0, 0.1, 2.3))
	await command_clients("shop", ["c2"], ["camp", "quest", "arrival", ""])
	await wait_seconds(0.4)
	await command_clients("inspect", ["c2"])
	check(read_json("done-c2").quest_notice.get("kind") == "ready", "A client sees its completed quest after the host snapshot")
	await command_clients("shop", ["c2"], ["camp", "quest", "arrival", ""])
	await command_clients("inspect", ["c1", "c2"])
	check(read_json("done-c2").quest_notice.get("kind") == "complete" and read_json("done-c2").quest_notice.get("id") == "arrival", "Reliable turn-in feedback displays the client's reward popup")
	check(read_json("done-c1").quest_notice.is_empty() and game.progression.notifications._current.is_empty(), "Other players do not receive the client's quest popup")
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
	# Random Meshy skins have different hunched torso heights. A fixed 1.2 m
	# point can lie in empty space; this test checks transport, not hip-fire luck.
	var aim_probe := DefenceTower.new()
	var shot_at := aim_probe.target_point(z)
	aim_probe.free()
	await command_clients("shoot", ["c1"], [[shot_at.x, shot_at.y, shot_at.z]])
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
	var item: Node3D = game.gold_mushroom
	item.global_position = Map.ground_pos(42, 102)
	item.taken = false
	item.show()
	await command_clients("inspect", ["c1"])
	var rare_report: Dictionary = read_json("done-c1")
	check(rare_report.gold_available and Vector3(rare_report.gold_position[0], rare_report.gold_position[1], rare_report.gold_position[2]).distance_to(item.global_position) < 0.01, "Host rare mushroom availability and exact location reach the client")
	var item_id := str(item.get_meta("coop_id"))
	var kind: String = item.id
	await teleport(c1, item.global_position + Vector3(0.7, 0.1, 0))
	await teleport(c2, item.global_position + Vector3(-0.7, 0.1, 0))
	await command_clients("interact", ["c1", "c2"], [item_id])
	await wait_seconds(0.6)
	check(NetSession.world.mushrooms[c1][kind] + NetSession.world.mushrooms[c2][kind] == 1, "Contended pickup granted exactly once")
	# Shoot wildlife through a remote weapon command, then race for the same meat.
	var hunt = game.hunting
	var animal: Deer = hunt.animals[0]
	animal.set_physics_process(false)
	animal.global_position = Map.ground_pos(42, 105)
	hunt.health[0] = 1.0
	await teleport(c1, animal.global_position + Vector3(0, 0.1, 4))
	var animal_target := animal.global_position + Vector3.UP * 0.7
	await command_clients("shoot", ["c1"], [[animal_target.x, animal_target.y, animal_target.z]])
	await wait_seconds(0.4)
	check(hunt.health[0] == 0 and hunt.drops.has(0), "Remote shot kills wildlife and creates host meat")
	await teleport(c1, animal.global_position + Vector3(1.2, 0.1, 0))
	await teleport(c2, animal.global_position + Vector3(-1.2, 0.1, 0))
	await command_clients("hunting", ["c1", "c2"], ["collect", 0])
	await wait_seconds(0.4)
	check(int(hunt.stock(c1).raw_meat) + int(hunt.stock(c2).raw_meat) == 4 and not hunt.drops.has(0), "Competing clients receive meat exactly once")
	var cook_peer: int = c1 if int(hunt.stock(c1).raw_meat) > 0 else c2
	var cook_label := "c1" if cook_peer == c1 else "c2"
	await teleport(cook_peer, Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 2.5))
	await command_clients("hunting", [cook_label], ["cook", -1])
	check(hunt.jobs.has(cook_peer) and int(hunt.stock(cook_peer).raw_meat) == 3, "Client starts host cooking at camp")
	await wait_seconds(6.2)
	await command_clients("inspect", [cook_label])
	check(int(read_json("done-" + cook_label).food.cooked_meat) == 1, "Cooked meat reaches the client inventory")
	var diner: Player = NetSession.world.actor(cook_peer)
	diner.hp = 40
	diner.regen_timer = 99999
	await command_clients("hunting", [cook_label], ["eat", -1])
	await wait_seconds(0.4)
	check(is_equal_approx(diner.hp, 75) and int(hunt.stock(cook_peer).cooked_meat) == 0, "Client eating applies healing on the host")
	# Leave a second animal's meat for the reconnect/late-join assertions below.
	hunt.hit(hunt.animals[1], 999, c1)
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
	await teleport(c2,Map.ground_pos(60,115)+Vector3.UP*0.1)
	await command_clients("tower_mount",["c2"],[tower.tower_id])
	await wait_seconds(0.4)
	check(tower.operator_peer==c2 and NetSession.world.actor(c2).mounted_tower==tower.tower_id,"Client mounts turret on host")
	await command_clients("inspect",["c2"])
	check(int(read_json("done-c2").mounted_tower)==tower.tower_id,"Mounted seat replicates to controlling client")
	await teleport(c1,Map.ground_pos(62,114)+Vector3.UP*0.1)
	await command_clients("tower_mount",["c1"],[tower.tower_id])
	await wait_seconds(0.3)
	check(tower.operator_peer==c2 and NetSession.world.actor(c1).mounted_tower==0,"Second player cannot steal an occupied turret")
	await command_clients("tower_exit",["c2"])
	await wait_seconds(0.4)
	check(tower.operator_peer==0 and NetSession.world.actor(c2).mounted_tower==0,"Remote dismount frees turret")
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
	var replica_shots: int = int(read_json("done-c1").tower_shots)
	check(tower.shots > 0 and tower_target.hp < 10000 and replica_shots > 0, "Host turret fire and target damage replicate (host=%d client=%d target_hp=%.1f)" % [tower.shots, replica_shots, tower_target.hp])
	await teleport(c2,Map.ground_pos(60,115)+Vector3.UP*0.1)
	await command_clients("tower_mount",["c2"],[tower.tower_id])
	await wait_seconds(0.4)
	tower.heat = 0
	tower.overheated = false
	tower.cooldown = 0
	var manual_hp := tower_target.hp
	var aim := tower.target_point(tower_target)
	await command_clients("tower_fire",["c2"],[[aim.x,aim.y,aim.z]])
	await wait_seconds(0.3)
	check(tower_target.hp<manual_hp,"Client mouse aim and trigger deal authoritative turret damage")
	check(tower.aiming,"Client right mouse reaches the host's turret precision state")
	check(float(read_json("done-c2").tower_fov)<56,"Client turret zoom survives weapon processing and snapshots")
	await command_clients("inspect",["c1"])
	check(bool(read_json("done-c1").tower_aiming),"Other clients receive the turret aiming state")
	await command_clients("tower_aim_release",["c2"])
	await wait_seconds(0.3)
	check(not tower.aiming and float(read_json("done-c2").tower_fov)>74.9,"Releasing right mouse restores host precision and client view")
	await command_clients("tower_exit",["c2"])
	await wait_seconds(0.3)
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
	titan.killer_peer = c2
	titan.damage(1, Vector3.ZERO)
	titan.killer_peer = c1
	titan.last_headshot = true
	titan.damage(titan.hp + 1, Vector3.ZERO)
	check(game.stats.players[c1].titan_kills == 1 and game.stats.players[c1].headshots == 1 and game.stats.players[c2].assists == 1, "Titan headshot and contributor assist belong to their respective players")
	await wait_seconds(2.0)
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]:
		var cues: Dictionary = read_json("done-" + label).titan_cues
		check(int(cues.get("death", 0)) == 1 and int(cues.get("collapse", 0)) == 1, label + " hears death and delayed body impact without replica duplicates")
		check_leaderboard(read_json("done-" + label), label)
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
	check(not joined.gold_available, "Collected gold bolete remains absent for late joiners")
	check(joined.hunted_dead >= 2 and joined.meat_drops >= 1, "Late join restores hunted animals and remaining meat")
	check_leaderboard(joined, "Late join")
	tower.damage(10000)
	await wait_seconds(0.5)
	await command_clients("wait_tower_removed", ["c3"])
	check(read_json("done-c3").towers == 0, "Destroyed tower disappears on other peers")
	NetSession.world.actor(c2).add_score(10000)
	# Tower types unlock with waves the team survived (Schweres MG after wave 6): the host refuses a
	# locked type from a client with money to spare and charges nothing, then the team gets there.
	await teleport(c2,Map.ground_pos(60,115)+Vector3.UP*0.1)
	var locked_score: int = NetSession.world.actor(c2).score
	await command_clients("tower_place",["c2"],[[60,Map.ground_height(60,112),112],"mg42"])
	await wait_seconds(0.4)
	check(game.defences.towers.is_empty() and NetSession.world.actor(c2).score==locked_score,"Host refuses a remote tower the team has not unlocked yet (%d of 6 waves)" % game.waves.completed)
	game.waves.completed = maxi(game.waves.completed, DefenceTower.SPECS.tesla.unlock_waves)
	for tower_kind in ["flame","mortar","mg42","tesla"]:
		await teleport(c2,Map.ground_pos(60,115)+Vector3.UP*0.1)
		var score_before: int = NetSession.world.actor(c2).score
		await command_clients("tower_place",["c2"],[[60,Map.ground_height(60,112),112],tower_kind])
		await wait_seconds(0.4)
		check(game.defences.towers.size()==1,tower_kind+" can be built by a remote client")
		if game.defences.towers.is_empty():
			var builder: Player = NetSession.world.actor(c2)
			push_error("TOWER_PLACE_DIAGNOSTIC kind=%s position=%s mounted=%d reason=%s" % [tower_kind, builder.global_position, builder.mounted_tower, game.defences.placement_error(builder, Map.ground_pos(60, 112), tower_kind)])
			quit(1)
			return
		var variant: DefenceTower = game.defences.towers.values()[0]
		check(variant.kind==tower_kind and NetSession.world.actor(c2).score==score_before-int(DefenceTower.SPECS[tower_kind].cost),tower_kind+" uses host-validated type and price")
		await command_clients("tower_mount",["c2"],[variant.tower_id])
		await wait_seconds(0.3)
		await command_clients("inspect",["c3"])
		check(read_json("done-c3").tower_kind==tower_kind and int(read_json("done-c3").operator_peer)==c2,tower_kind+" type and occupation reach other peers")
		variant.damage(100000)
		await wait_seconds(0.3)
		await command_clients("wait_tower_removed",["c2"])
		check(int(read_json("done-c2").mounted_tower)==0,tower_kind+" destruction releases remote operator")
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
	check(game.stats.players[c2].deaths == 1, "Revival preserves one recorded death")
	check_leaderboard(read_json("done-c2"), "Revived client")
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
	check_leaderboard(read_json("done-c1"), "Final reliable game-over snapshot")
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
	check(game.hunting.drops.is_empty() and not 0.0 in game.hunting.health and int(game.hunting.stock(1).raw_meat) == 0, "New round restores wildlife and clears food")
	check(game.stats.players.size() == 4, "Round restart removes disconnected leaderboard history")
	for row: Dictionary in game.stats.players.values():
		check(row.kills == 0 and row.headshots == 0 and row.deaths == 0 and row.titan_kills == 0 and row.assists == 0, "New round clears all five player counters")
	for label in ["c1", "c2", "c3"]: check_leaderboard(read_json("done-"+label), "Restarted " + label)
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

func verify_intro() -> void:
	game.player.set_physics_process(false)
	game.waves.set_process(false)
	check(game.intro.active and game.intro.phase == "logo" and not game.player.active, "Host starts with the normal intro card")
	var positions: Array[Vector3] = []
	for id in NetSession.roster:
		var p: Player = NetSession.world.actor(id)
		check(Vector2(p.global_position.x, p.global_position.z).distance_to(Intro.START) < 4.0, "Teammate starts on Sennhofstrasse")
		for previous in positions: check(previous.distance_to(p.global_position) > 1.0, "Intro spawns do not overlap")
		positions.append(p.global_position)
	var c1 := find_peer("c1")
	var before: Vector3 = NetSession.world.actor(c1).global_position
	NetSession.world.move_player(c1, before + Vector3(0.2, 0, 0), 0, 0, false, Vector3.RIGHT, NetSession._elapsed)
	check(NetSession.world.actor(c1).global_position == before, "Logo prevents remote movement")
	game._pause()
	game._on_start()
	check(not game.player.active, "Resume cannot bypass intro card")
	# Inspect the reliable start state while the logo is visible. Waiting for a
	# subsequent unreliable update can outlast the logo when packets are dropped.
	# The walk-phase inspection below separately requires a fresh live snapshot.
	await command_clients("inspect", ["c1", "c2", "c3"], [], false)
	for label in ["c1", "c2", "c3"]:
		var report: Dictionary = read_json("done-" + label)
		check(report.intro_active and report.intro_phase == "logo", label + " plays the intro")
		check(report.intro_distance < 4.0 and report.wave == 0, label + " retains the road spawn through snapshots")
	await wait_seconds(Intro.LOGO_IN + Intro.LOGO_HOLD + Intro.LOGO_OUT + Intro.WAKE)
	check(game.player.active and game.intro.phase == "walk", "Host wakes and can walk")
	check(game.waves.wave == 0 and game.waves.phase == "intro", "Wave one waits for the road trigger")
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]:
		var report: Dictionary = read_json("done-" + label)
		check(report.intro_phase == "walk" and report.player_active and report.wave == 0, label + " wakes without starting a local wave")
	await teleport(c1, Map.ground_pos(118.0, 24.0) + Vector3.UP * 0.3)
	await wait_seconds(0.3)
	check(game.waves.wave == 1 and game.waves.phase == "spawning", "A remote teammate releases the host's first wave")
	await command_clients("inspect", ["c1", "c2", "c3"])
	for label in ["c1", "c2", "c3"]:
		var report: Dictionary = read_json("done-" + label)
		check(report.wave == 1, label + " receives the authoritative first wave")
	# Continue the existing gameplay suite from its usual campsite fixture.
	game.intro._end()
	await command_clients("finish_intro", ["c1", "c2", "c3"])
	game.waves.queue.clear()
	game.waves.wave = 0
	game.waves.phase = "idle"
	game.waves.timer = 10000.0
	game.waves.set_process(true)
	var index := 0
	for id in NetSession.roster:
		var p: Player = NetSession.world.actor(id)
		p.global_position = Map.ground_pos(Map.PLAYER_START.x + index * 1.3, Map.PLAYER_START.y + 1.0) + Vector3.UP * 0.3
		p.rotation.y = PI
		p.velocity = Vector3.ZERO
		index += 1
	for id in NetSession.roster:
		if id != 1: NetSession._world_state.rpc_id(id, NetSession.epoch, NetSession._sequence, NetSession.world.snapshot(), true)

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
		if request.action == "hunting": args[1] = int(args[1])
		if request.action in ["build", "repair", "revive", "tower_upgrade", "tower_repair", "tower_sell", "tower_mount"]: args[0] = int(args[0])
		if request.action == "tower_rotate":
			args[0] = int(args[0])
			args[1] = float(args[1])
		match request.action:
			"tower_fire":
				var aim := Vector3(args[0][0],args[0][1],args[0][2])
				var direction: Vector3 = aim-game.player.camera.global_position
				game.player.rotation.y = atan2(-direction.x,-direction.z)
				game.player.pitch = atan2(direction.y,Vector2(direction.x,direction.z).length())
				game.player.head.rotation.x = game.player.pitch
				Input.action_press("aim")
				Input.action_press("fire")
				await wait_seconds(0.7)
				Input.action_release("fire")
			"tower_aim_release":
				Input.action_release("aim")
				await wait_seconds(0.7)
			"finish_intro": game.intro._end()
			"wait_tower_removed":
				var deadline := Time.get_ticks_msec() + 5000
				while not game.defences.towers.is_empty() and Time.get_ticks_msec() < deadline:
					await wait_seconds(0.1)
			"tower_place": NetSession.command("tower_place", [Vector3(args[0][0], args[0][1], args[0][2]),0.0,str(args[1]) if args.size()>1 else "standard"])
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
				game.weapons.ads = 1.0
				game.weapons.try_fire()
			"reload": game.weapons.reload()
			"grenade": game.weapons.throw_grenade()
			"invalid":
				NetSession.command("fire", ["ak47", 0.0, 0.0, 0.0])
				NetSession._pose.rpc_id(1, NetSession.epoch, Vector3(99999, 5000, 99999), 0.0, 0.0, false, Vector3.ZERO, NetSession.world.movement_sync.record(game.player.global_position))
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
				check(NetSession._received_sequence >= int(request.get("minimum_sequence", -1)), role + " received world state for inspection (received=%d required=%d)" % [NetSession._received_sequence, int(request.get("minimum_sequence", -1))])
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
			"quest_notice": game.progression.notifications._current,
			"gold_available": is_instance_valid(game.gold_mushroom) and not game.gold_mushroom.taken,
			"gold_position": [game.gold_mushroom.global_position.x, game.gold_mushroom.global_position.y, game.gold_mushroom.global_position.z] if is_instance_valid(game.gold_mushroom) else [],
			"food": game.hunting.stock(game.player.peer_id), "hunted_dead": game.hunting.health.count(0.0), "meat_drops": game.hunting.drops.size(),
			"leaderboard": game.stats.leaderboard_rows(),
			"mounted_tower": game.player.mounted_tower,
			"tower_fov": game.player.camera.fov,
			"tower_aiming": game.defences.towers.values()[0].aiming if game.defences.towers.size() else false,
			"intro_active": game.intro.active, "intro_phase": game.intro.phase, "player_active": game.player.active,
			"intro_distance": Vector2(game.player.global_position.x, game.player.global_position.z).distance_to(Intro.START), "wave": game.waves.wave,
			"towers": game.defences.towers.size(), "tower_shots": tower_shots, "tower_hp": tower_hp,
			"tower_yaw": game.defences.towers.values()[0].rotation.y if game.defences.towers.size() else 0.0,
			"tower_kind": game.defences.towers.values()[0].kind if game.defences.towers.size() else "",
			"operator_peer": game.defences.towers.values()[0].operator_peer if game.defences.towers.size() else 0,
			"skins": game.weapons.skins, "progress_people": game.progression.people.size(),
			"titans": titan_count, "boss_phase": boss_phase, "boss_max_hp": boss_max_hp, "boss_impact": boss_impact,
			"boss_model": boss_model, "boss_seed": boss_seed, "boss_height": boss_height,
			"titan_cues": titan_cues,
			"started": game.started, "paused": paused, "alive": game.player.alive, "over": game.over,
			"bar": game.barricades[0].level, "open_doors": open_doors,
			"alive_zombies": game.alive_zombies(),
			"zombies": zombie_count, "grenades": NetSession.world.grenades.size(), "keys": game.forest_keys.owned.size()})
