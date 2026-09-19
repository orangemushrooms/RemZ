# Inspect two packaged clients and a packaged host through the real protocol.
extends SceneTree

var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 90000:
		push_error("PACKED_COOP_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	var net := root.get_node("NetSession")
	check(net.join("127.0.0.1", "Verifier", 24692) == OK, "Probe connects to packaged host")
	while net.phase != "running": await process_frame
	check(net.roster.size() == 4 and net.world.avatars.size() == 3, "Packaged host, two packaged clients and probe share four-player round")
	await create_timer(2.0).timeout
	check(net._received_sequence > 5 and net.world.state_loaded, "Compressed snapshots arrive from packaged host")
	game.weapons.try_fire()
	await create_timer(0.4).timeout
	check(game.weapons.cur().ammo == 11 and net._command_seq > 0, "Packaged host acknowledges one shot and authoritative ammo")
	game.weapons.throw_grenade()
	await create_timer(0.6).timeout
	check(net.world.grenades.size() == 1 and game.weapons.grenades == 1, "Packaged host simulates and replicates the grenade")
	await create_timer(4.0).timeout
	check(net.world.grenades.is_empty(), "Packaged explosion removes grenade")
	check(game.zombies_root.get_children().any(func(node): return node is Zombie), "Packaged host spawns the common wave")
	check(game.stats.seconds > 5.0, "Packaged world simulation advances")
	game._pause()
	check(not paused and not game.hud.overlay_button.disabled, "Client resume button is enabled without pausing the host")
	game.hud.overlay_button.pressed.emit()
	check(game.player.active and not game.hud.overlay.visible, "Resume button returns client to play")
	game.inventory.open()
	await process_frame
	var first_slot: Node = game.inventory.grid.get_child(0)
	await create_timer(0.5).timeout
	check(is_instance_valid(first_slot), "Unchanged snapshots preserve clickable inventory controls")
	game.inventory.close()
	print("PACKED_COOP_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
