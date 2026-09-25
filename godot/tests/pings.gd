# The radio (26 Sep 2026): contextual pings from what the crosshair rests on, the automatic callouts with
# their cooldown, the radio log, the markers, and the text that arrives in the receiver's language.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=pings --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func look_at(player: Player, target: Vector3) -> void:
	var to: Vector3 = target - player.camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	var flat := Vector2(to.x, to.z).length()
	player.pitch = clampf(atan2(to.y, flat), -1.45, 1.45)
	player.head.rotation.x = player.pitch

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var pings: Pings = game.pings
	var player: Player = game.player
	player.set_physics_process(false)
	check(pings != null and pings.active.is_empty(), "The radio starts silent")
	check(InputMap.has_action("ping") and InputMap.action_get_events("ping").size() == 2, "X and the middle mouse button are bound to the ping")
	# ---- a plain ping
	pings.send("regroup", player.global_position)
	check(pings.active.size() == 1 and pings.count == 1 and pings.active[0].kind == "regroup", "A ping is recorded")
	check(pings.log.size() == 1 and game.hud.radio_box.get_child_count() == 1, "The radio log shows the line")
	check(Lang.text(pings.log[0][0]).ends_with("Regroup on me!"), "The line carries the author and the text (%s)" % Lang.text(pings.log[0][0]))
	# ---- what the crosshair rests on
	var gate: Barricade = game.barricades[1]
	var outside: Vector2 = Vector2(gate.center.x, gate.center.z) - gate.normal2 * 5.0
	if game.perimeter.contains(outside): outside = Vector2(gate.center.x, gate.center.z) + gate.normal2 * 5.0
	player.global_position = Map.ground_pos(outside.x, outside.y) + Vector3.UP * 0.3
	await physics_frame
	look_at(player, gate.center + Vector3.UP * 0.6)
	pings.contextual()
	check(pings.active.back().kind == "gate_hold" and Lang.text(pings.active.back().text).begins_with("Hold"), "Looking at an open gate: hold it (%s)" % Lang.text(pings.active.back().text))
	gate.build()
	await physics_frame
	look_at(player, gate.center + Vector3.UP * 0.7)
	gate.update_attack_alert(5.0)
	pings.contextual()
	check(pings.active.back().kind == "gate_attack", "A gate under attack: under attack")
	gate.hp = gate.max_hp() * 0.3
	pings.contextual()
	check(pings.active.back().kind == "gate_breaking" and Lang.text(pings.active.back().text).contains("breaking"), "A gate under attack below half health: breaking")
	gate.update_attack_alert(0.0)
	# an enemy
	var spawned: bool = game.spawn_zombie("shambler", outside + gate.normal2 * -6.0, 1.0)
	var zombie: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie: zombie = z
	await physics_frame
	await physics_frame
	if zombie:
		look_at(player, zombie.global_position + Vector3.UP * 1.0)
		pings.contextual()
	check(spawned and zombie != null and pings.active.back().kind == "enemy", "Looking at a zombie: enemy spotted")
	# the ground and the sky: away from the gate and the zombie
	if zombie: zombie.die(Vector3.FORWARD)
	var ground := player.global_position + player.global_basis.z * 14.0
	ground = Map.ground_pos(ground.x, ground.z)
	look_at(player, ground)
	pings.contextual()
	check(pings.active.back().kind == "move" and pings.active.back().position.distance_to(ground) < 3.0, "Looking at the ground: move here")
	player.pitch = 1.3
	player.head.rotation.x = 1.3
	pings.contextual()
	check(pings.active.back().kind == "regroup", "Looking at the sky: regroup on me")
	# ---- automatic callouts and their cooldown
	var count_before: int = pings.count
	pings.callout("titan", "titan", Vector3.ZERO)
	pings.callout("titan", "titan", Vector3.ZERO)
	check(pings.count == count_before + 1, "A repeated callout waits for its cooldown")
	pings._process(Pings.CALLOUT_COOLDOWN + 0.1)
	pings.callout("titan", "titan", Vector3.ZERO)
	check(pings.count == count_before + 2, "... and speaks again afterwards")
	# ---- the receiving side: names stay, gate names translate
	pings.receive("Anna", "spotted", Vector3.ZERO, "Michel")
	var spotted: String = pings.log.back()[0]
	check(Lang.resolve(spotted, "en") == "Anna: Michel was spotted by a screamer!", "A teammate's callout names both players (%s)" % Lang.resolve(spotted, "en"))
	check(Lang.resolve(spotted, "de") == "Anna: Michel wurde von einem Kreischer entdeckt!", "... in German too")
	pings.receive("Anna", "gate_hold", Vector3.ZERO, "Meadow Gate")
	check(Lang.resolve(pings.log.back()[0], "de") == "Anna: Haltet Wiesentor!", "A gate's name is translated on the receiving side")
	check(pings.active.size() <= 6, "The marker list stays bounded")
	# ---- markers expire
	pings._process(Pings.LIFETIME + 4.0)
	check(pings.active.is_empty() and pings.log.is_empty(), "Markers and log lines expire")
	game.hud.pings_layer.queue_redraw()
	await process_frame
	await process_frame
	check(true, "The marker layer redraws without errors")
	print("PINGS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
