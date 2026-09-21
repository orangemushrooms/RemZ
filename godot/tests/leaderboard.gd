extends SceneTree

var game: Node
var net: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: quit(1)
	return false

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame

func enemy(hp := 100.0) -> Zombie:
	game.spawn_zombie("shambler", Vector2(55, 110), 1)
	var z: Zombie = game.zombies_root.get_children().back()
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.hp = hp
	return z

func run() -> void:
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	check(game.stats.players.size() == 1 and game.stats.players[1].kills == 0, "Solo round has one empty leaderboard row")
	game.player.score = 321
	game.leaderboard.refresh()
	check(game.stats.players[1].score == 321 and game.stats.players[1].ping_ms == 0, "Solo leaderboard reads current balance without a network connection")
	check(net.host("Michel", 24691) == OK, "Host starts leaderboard fixture")
	if not net.is_host():
		quit(1)
		return
	for id in [2, 3, 4]:
		net.roster[id] = "Mitspieler %d" % id
		net.world.add_player(id)
	net._begin(net.epoch, false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	check(game.stats.players.size() == 4 and game.stats.players[1].name == "Michel", "Roster has four named players without a duplicate solo row")
	var z := enemy()
	z.killer_peer = 2
	z.last_headshot = true
	z.damage(10, Vector3.ZERO)
	z.damage(10, Vector3.ZERO)
	check(game.stats.players[2].headshots == 0, "Nonlethal head hits do not count as headshot kills")
	z.killer_peer = 3
	z.damage(10, Vector3.ZERO)
	z.killer_peer = 1
	z.damage(100, Vector3.ZERO)
	check(game.stats.players[1].kills == 1 and game.stats.players[1].headshots == 1, "Lethal headshot belongs to the final shooter")
	check(game.stats.players[2].assists == 1 and game.stats.players[3].assists == 1, "Each contributing teammate gets exactly one assist")
	check(game.stats.players[1].assists == 0 and game.stats.players[4].assists == 0, "Killer and noncontributors get no assist")
	z.damage(100, Vector3.ZERO)
	z.die(Vector3.ZERO)
	check(game.stats.players[1].kills == 1, "Corpse hits and repeated death callbacks cannot duplicate kills")
	z = enemy()
	z.net_kind = "titan"
	z.killer_peer = 2
	z.damage(10, Vector3.ZERO)
	z.killer_peer = 3
	z.damage(1000, Vector3.ZERO)
	check(game.stats.players[3].kills == 1 and game.stats.players[3].titan_kills == 1, "Titan counts once as both kill and titan kill")
	check(game.stats.players[2].assists == 2 and game.stats.players[2].titan_kills == 0, "Titan support earns an assist, not a titan kill")
	var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(60, 112), 2)
	tower.set_physics_process(false)
	z = enemy(1)
	tower.hurt(z, Vector3.ZERO)
	check(game.stats.players[2].kills == 1, "Automatic turret kill belongs to builder")
	tower.operator_peer = 3
	z = enemy(1)
	tower.hurt(z, Vector3.ZERO)
	check(game.stats.players[3].kills == 2 and game.stats.players[2].kills == 1, "Operated turret kill belongs to operator")
	tower.operator_peer = 0
	z = enemy(22)
	game.progression.rare_market.hit(z, "fire", 2, "pistol")
	game.progression.rare_market.tick_statuses(1)
	z.killer_peer = 3
	z.damage(2, Vector3.ZERO)
	game.progression.rare_market.tick_statuses(1)
	check(game.stats.players[2].kills == 2 and game.stats.players[2].headshots == 0, "Burn finish belongs to original shooter without a headshot")
	check(game.stats.players[3].assists == 2, "Another shooter's damage assists a burn kill")
	var p: Player = net.world.actor(2)
	p.relic = "phoenix"
	p.damage(10000)
	check(p.alive and game.stats.players[2].deaths == 0, "Phoenix protection does not count a death")
	p.relic = ""
	p.damage(10000)
	p.damage(10000)
	check(not p.alive and game.stats.players[2].deaths == 1, "Death counts once before team checks and corpse damage is ignored")
	p.alive = true
	p.hp = 50
	p.damage(10000)
	check(game.stats.players[2].deaths == 2, "Death after revival counts as a new death")
	check(game.stats.leaderboard_rows()[0].id == 3, "Ranking breaks equal kills by titan kills")
	var snap: Dictionary = net.world.snapshot()
	check(snap.leaderboard == game.stats.players, "Full world snapshot carries every leaderboard column")
	check(snap.leaderboard[1].score == game.player.score and snap.leaderboard[1].ping_ms == 0, "Snapshot includes current points and zero host latency")
	check(snap.leaderboard[2].ping_ms == -1, "Absent transport connection is unknown, not a fabricated ping")
	snap.leaderboard[1].kills = 999
	check(game.stats.players[1].kills == 1, "Snapshot data cannot mutate host counters")
	net.world.actor(4).score = 777
	net.world.remove_player(4)
	check(not game.stats.players[4].connected and game.stats.players[4].kills == 0, "Departed player remains marked offline for this round")
	check(game.stats.players[4].score == 777 and game.stats.players[4].ping_ms == -1, "Disconnect preserves final balance and clears stale ping")
	var before: bool = game.progression._journal
	await key(KEY_Q, true)
	check(game.progression._journal != before and game.weapons._melee_t == 0, "Q toggles quests without attacking")
	await key(KEY_Q, true, true)
	check(game.progression._journal != before, "Held Q does not repeatedly toggle quests")
	await key(KEY_Q, false)
	var cursor := Input.mouse_mode
	await key(KEY_TAB, true)
	check(game.leaderboard.panel.visible and game.leaderboard.rows_box.get_child_count() == 4, "Tab shows all player rows")
	check(game.player.active and not paused and Input.mouse_mode == cursor, "Leaderboard keeps gameplay and cursor state unchanged")
	check(game.progression._journal != before, "Tab does not toggle quests")
	var balance: int = game.player.score
	game.player.add_score(100)
	await process_frame
	check(game.stats.players[1].score == balance + 100, "Open leaderboard updates newly earned points")
	game.player.add_score(-35)
	await process_frame
	check(game.stats.players[1].score == balance + 65, "Open leaderboard also reflects spending")
	var displayed: Array = game.stats.leaderboard_rows()
	for i in displayed.size():
		var cells: Array = game.leaderboard.rows_box.get_child(i).get_child(0).get_children()
		check(cells.size() == 9 and cells[7].text == str(displayed[i].score), "Player row shows its current point balance")
		check(cells[8].text == ("0 ms" if displayed[i].id == 1 else "—"), "Player row shows host ping or unavailable marker")
	if "--render-leaderboard" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../artifacts/leaderboard/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder + "leaderboard.png")
	await key(KEY_TAB, false)
	check(not game.leaderboard.panel.visible, "Releasing Tab hides the leaderboard")
	game.inventory.open()
	await key(KEY_TAB, true)
	check(not game.leaderboard.panel.visible, "Inventory retains its own keyboard focus")
	await key(KEY_TAB, false)
	game.inventory.close()
	game._pause()
	await key(KEY_TAB, true)
	check(game.leaderboard.panel.visible, "Standings remain available in pause menu")
	await key(KEY_TAB, false)
	game._on_start()
	await key(KEY_TAB, true)
	game.leaderboard._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.leaderboard.panel.visible, "Focus loss clears held leaderboard")
	await key(KEY_TAB, false)
	game.weapons.set_process(true)
	await key(KEY_H, true)
	check(game.weapons._melee_t > 0, "H triggers the existing quick melee attack")
	await key(KEY_H, false)
	for actor: Player in net.world.actors.values(): actor.damage(10000)
	await key(KEY_TAB, true)
	check(game.over and game.leaderboard.panel.visible, "Final standings remain accessible after team defeat")
	await key(KEY_TAB, false)
	print("LEADERBOARD_TEST_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
