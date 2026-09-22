# Waldhütte health: warning, repair with cost, a zombie really attacks the walls, destruction ends the round.
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=hut_health --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var hut: HutHealth = game.hut
	check(hut != null and hut.hp == HutHealth.MAX_HP, "Hut starts with full health")
	check(hut.body != null and hut.body.is_in_group("hut_body"), "Hut wall bodies are tagged for zombie hits")
	var west := hut.attack_point(hut.center + Vector3(-20, 0, 0))
	check(hut.distance(hut.center + Vector3(-20, 0, 0)) < 20.0 and hut.distance(west) < 0.05, "Attack point lies just outside the west wall")
	# warning and alert
	hut.damage(40)
	check(hut.hp == HutHealth.MAX_HP - 40 and hut.under_attack(), "Damage lowers health and raises the alert")
	check(game.hud.msg_label.text == HutHealth.WARNING and game.hud.hut_alarm.visible, "First hit immediately shows the large attack alarm")
	check(hut._attack_sound != null and hut._attack_sound.playing and hut._attack_sound.stream.resource_path.ends_with("hut_under_attack.mp3") and hut._attack_sound.pitch_scale == 1.0, "First hit plays the supplied warning with its original voice pitch")
	game.hud.message("keep", 3.0)
	hut.damage(40)
	check(game.hud.msg_label.text == "keep" and game.hud.hut_alarm.visible, "Attack alarm stays visible independently of ordinary messages")
	hut._process(HutHealth.ATTACK_ALERT_SECONDS + 0.1)
	check(not hut.under_attack() and not game.hud.hut_alarm.visible, "Alert disappears after the attacks stop")
	check(not hut._attack_sound.playing, "Warning audio stops with the visual alarm")
	hut.update_attack_alert(HutHealth.ATTACK_ALERT_SECONDS, false)
	check(game.hud.hut_alarm.visible and not hut._attack_sound.playing, "Initial multiplayer state shows an active alarm without replaying old audio")
	hut.update_attack_alert(0.0, false)
	hut.update_attack_alert(HutHealth.ATTACK_ALERT_SECONDS, true)
	check(hut._attack_sound.playing, "A new authoritative attack phase replays the warning")
	hut.update_attack_alert(0.0, false)
	check(game.hud.hut_label.text.begins_with("HÜTTE %d" % ceili(hut.hp)), "HUD shows the hut health")
	# repair: reach, cost, step
	var player: Player = game.player
	player.score = 0
	player.global_position = west
	check(hut.can_repair(player), "Player at the wall may repair")
	check(hut.repair(player).begins_with("Es fehlen"), "Repair needs points")
	player.score = 100
	var partial_cost: int = hut.repair_quote().cost
	check(partial_cost == 5 and hut.repair_quote().amount == 80, "Small repairs charge proportionally for actual missing HP")
	check(hut.repair(player) == "" and player.score == 100 - partial_cost, "Repair charges the displayed quote")
	check(hut.hp == HutHealth.MAX_HP, "Repair restores health up to the maximum")
	check(hut.repair(player) == "Keine Reparatur nötig.", "Full hut refuses repair")
	var saved_wave: int = game.waves.wave
	var saved_completed: int = game.waves.completed
	for entry in [[1, 30], [5, 50], [10, 75], [20, 125]]:
		game.waves.wave = entry[0]
		game.waves.completed = maxi(0, int(entry[0]) - 1)
		hut.hp = HutHealth.MAX_HP - 1000
		var quote: Dictionary = hut.repair_quote()
		check(quote.cost == entry[1] and quote.amount == 500, "Repair price scales at wave %d without reducing restored HP" % entry[0])
		player.score = int(quote.cost) - 1
		check(hut.repair(player).begins_with("Es fehlen") and hut.hp == HutHealth.MAX_HP - 1000, "Insufficient points cannot buy late-wave repairs")
		player.score = int(quote.cost)
		check(hut.prompt_text().contains("%d R" % quote.cost) and hut.repair(player).is_empty() and player.score == 0 and hut.hp == HutHealth.MAX_HP - 500, "Prompt and actual repair charge agree")
	game.waves.wave = 10
	game.waves.completed = 10
	hut.hp = HutHealth.MAX_HP - 100
	check(hut.repair_quote().cost == 15, "Late-wave partial repair remains proportional")
	game.waves.wave = 0
	check(hut.repair_quote().cost == 15, "Completed wave prevents cheaper intermission repairs")
	hut.hp = HutHealth.MAX_HP
	check(hut.repair_quote().cost == 0 and hut.repair_quote().amount == 0, "Full health produces a zero repair quote")
	game.waves.wave = saved_wave
	game.waves.completed = saved_completed
	hut.damage(1200)
	hut.hp = HutHealth.MAX_HP - 1200
	player.global_position = hut.center + Vector3(-30, 0, 0)
	check(not hut.can_repair(player) and hut.repair(player).begins_with("Zu weit"), "Repair needs the player at the hut")
	# a zombie inside the ring goes for the hut and damages it
	player.global_position = Map.ground_pos(-40, -60)
	player.set_physics_process(false)
	var before := hut.hp
	var spawned: bool = game.spawn_zombie("shambler", Vector2(hut.center.x - 7.5, hut.center.z), 1.0)
	check(spawned, "Test zombie spawned beside the hut")
	var zombie: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie: zombie = z
	if zombie: zombie.raider = true
	var t := 0.0
	while t < 14.0 and hut.hp >= before:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	check(zombie != null and zombie.siege_target == hut, "Zombie beside the hut targets it")
	check(hut.hp < before, "Zombie attack damages the hut (%.0f -> %.0f after %.1f s)" % [before, hut.hp, t])
	# destruction loses the round
	hut.damage(100000)
	check(hut.destroyed and hut.hp == 0.0 and not game.hud.hut_alarm.visible, "Destroyed hut clears the attack alarm")
	check(not hut._attack_sound.playing, "Hut destruction stops the attack warning")
	check(game.over and game.hud.overlay_title.text == "HÜTTE VERLOREN", "Destroyed hut ends the round with its own title")
	print("HUT_HEALTH_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
