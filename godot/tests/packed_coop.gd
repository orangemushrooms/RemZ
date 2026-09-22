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

func wait_for(condition: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await process_frame
	return bool(condition.call())

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	var net := root.get_node("NetSession")
	check(net.join("127.0.0.1", "Verifier", 24692) == OK, "Probe connects to packaged host")
	while net.phase != "running": await process_frame
	check(net.roster.size() == 4 and net.world.avatars.size() == 3, "Packaged host, two packaged clients and probe share four-player round")
	check(await wait_for(func(): return net._received_sequence > 5 and net.world.state_loaded), "Compressed snapshots arrive from packaged host")
	# Model loading on the first real wave may take several frames in a fresh pack.
	check(await wait_for(func(): return game.zombies_root.get_children().any(func(node): return node is Zombie)), "Packaged host spawns the common wave")
	game.weapons.try_fire()
	check(await wait_for(func(): return game.weapons.cur().ammo == 11 and net._command_seq > 0), "Packaged host acknowledges one shot and authoritative ammo")
	game.weapons.throw_grenade()
	check(await wait_for(func(): return net.world.grenades.size() == 1 and game.weapons.grenades == 1, 2.5), "Packaged host simulates and replicates the grenade")
	await create_timer(4.0).timeout
	check(net.world.grenades.is_empty(), "Packaged explosion removes grenade")
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
	check(game.progression.npcs.size() == Progression.NPCS.size() and game.progression.people.size() == 4, "Packaged NPC catalogue and four player quest states are present")
	check(Weapons.ORDER.all(func(id): return Weapons.is_melee(id) or ResourceLoader.exists("res://assets/models/%s.glb" % Weapons.DEFS[id].model)), "Packaged build contains every firearm mesh")
	check(game.progression.npcs.values().all(func(npc): return npc.anim != null and npc.anim.is_playing()), "All packaged NPCs have active skeletal animations")
	net.command("upgrade", ["w_ak47"])
	net.command("shop", ["camp", "weapon", "ak47", ""])
	await create_timer(0.5).timeout
	check(not game.weapons.unlocked.ak47, "Packaged host rejects both legacy and remote merchant weapon bypasses")
	print("PACKED_COOP_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
