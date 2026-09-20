extends SceneTree
# Menu round trips: death -> Nochmal, pause -> Hauptmenü, coop host solo death -> Neue Runde.
# godot --headless --path godot --script res://tests/run.gd -- --suite=menu_flow --smoke-test --no-intro --no-music --no-foliage
var game: Node
var failures := 0
var checks := 0
var t0 := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_d: float) -> bool:
	if Time.get_ticks_msec() - t0 > 900000: push_error("MENU_TIMEOUT"); quit(1)
	return false
func check(c: bool, d: String) -> void:
	checks += 1
	if c: print("PASS: " + d)
	else: failures += 1; push_error("FAIL: " + d)
func stamp(what: String) -> void:
	print("MENU_T %s %.1f s" % [what, (Time.get_ticks_msec() - t0) / 1000.0])
func fresh() -> void:
	game = current_scene
	while not game.navigation_ready: await process_frame
func run() -> void:
	seed(7)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); current_scene = game
	await fresh(); stamp("first load")
	game._on_start(); game.waves.set_process(false)
	await physics_frame; await physics_frame
	# zombie damage
	var pp: Vector3 = game.player.global_position
	game.spawn_zombie("shambler", Vector2(pp.x + 1.2, pp.z), 1.0)
	var z: Zombie = game.zombies_root.get_child(0)
	var hp0: float = game.player.hp
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < 5000 and game.player.hp == hp0: await process_frame
	print("MENU hurt hp=%s dist=%.2f state=%s can_hit=%s" % [game.player.hp, z.global_position.distance_to(game.player.global_position), z.state, z._can_hit(null)])
	check(game.player.hp < hp0, "A zombie next to the player takes health")
	z.damage(1e5, Vector3.FORWARD)
	# death -> Nochmal
	game.player.damage(1e5)
	check(game.over and paused, "Death shows the game-over card")
	var t1 := Time.get_ticks_msec()
	game._on_start()
	await scene_changed
	await fresh(); stamp("reload after death (%.1f s)" % ((Time.get_ticks_msec() - t1) / 1000.0))
	check(not paused and game.started and game.player.active and game.player.hp == 100.0 and game.waves.phase != "intro", "Nochmal starts a fresh round directly, without menu or intro")
	game.waves.set_process(false)
	# pause -> Hauptmenü
	game._pause()
	check(paused and not game.player.active, "Pause halts the game")
	t1 = Time.get_ticks_msec()
	game._to_main_menu()
	await scene_changed
	await fresh(); stamp("reload to main menu (%.1f s)" % ((Time.get_ticks_msec() - t1) / 1000.0))
	check(paused and not game.started, "Hauptmenü shows the start menu again")
	# coop host solo: start, die, Neue Runde
	var err: int = NetSession.host("Host", 24599)
	check(err == OK, "Hosting a coop session works (%d)" % err)
	await process_frame
	NetSession.start_game()
	await physics_frame; await physics_frame
	check(NetSession.phase == "running" and game.started and game.player.active, "Coop host starts solo")
	game.waves.set_process(false)
	game.player.damage(1e5)
	await process_frame
	check(NetSession.phase == "over" and game.over, "Host death ends the coop round")
	t1 = Time.get_ticks_msec()
	game._on_start()   # "Neue Runde"
	await scene_changed
	await fresh(); stamp("coop reload (%.1f s)" % ((Time.get_ticks_msec() - t1) / 1000.0))
	for i in 10: await process_frame
	check(NetSession.enabled and NetSession.phase == "running" and NetSession.ready_peers.get(1, false), "Neue Runde reloads and the host auto-starts the next coop round")
	check(NetSession.phase == "running" and game.started and game.player.active and not game.over, "Second coop round starts")
	game._pause(); game._to_main_menu()
	await scene_changed
	await fresh(); stamp("leave coop")
	check(not NetSession.enabled and paused and not game.started, "Leaving coop returns to the offline start menu")
	print("MENU_FLOW_DONE checks=%d failures=%d" % [checks, failures])
	quit(0)
