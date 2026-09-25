# The second line (26 Sep 2026): a sandbag emplacement behind every gate that rises when the gate falls,
# is attacked by the zombies pouring in, can be vaulted, repaired and rebuilt, and travels in the snapshot.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=sandbags --smoke-test --no-intro --no-music --no-foliage
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

func xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var ring: Perimeter = game.perimeter
	check(game.sandbags.size() == 4 and game.barricades.size() == 4, "One sandbag line per gate")
	check(game.defence_lines().size() == 8 and game.defence_lines()[4] == game.sandbags[0], "Gates first, then the sandbag lines")
	for i in 4:
		var gate: Barricade = game.barricades[i]
		var line: SandbagLine = game.sandbags[i]
		var distance := xz(line.center).distance_to(xz(gate.center))
		check(ring.contains(xz(line.center)), "Line %d stands inside the ring" % i)
		check(absf(distance - SandbagLine.FALLBACK_DEPTH) < 0.6, "Line %d sits %.1f m behind its gate" % [i, distance])
		check(line.dir2.is_equal_approx(gate.dir2) and line.slot.segments == gate.slot.segments, "Line %d runs parallel to its gate" % i)
		check(line.level == 0 and line.hp == 0.0 and not line.is_gate() and line.gate == gate, "Line %d starts as a site behind %s" % [i, gate.slot.name])
		check(line.wall_height() == SandbagLine.SANDBAG_HEIGHT and line.body.collision_layer == 8, "Line %d is a low wall on the barricade layer" % i)
	# ---- a breach raises the line for free
	var gate: Barricade = game.barricades[1]
	var line: SandbagLine = game.sandbags[1]
	gate.build()
	var score_before: int = game.player.score
	gate.damage(1e6)
	check(gate.level == 0 and line.level == 1 and line.hp == SandbagLine.SANDBAG_HP and line.deployments == 1, "The breached gate raises its sandbag line")
	check(game.player.score == score_before, "The deployment costs nothing")
	check(Lang.text(game.hud.msg_label.text).contains("Sandbag line raised"), "The deployment is announced")
	check(game.pings.active.size() > 0 and game.pings.active.back().kind == "gate_breached", "The radio calls the breach")
	check(line.visual.get_child_count() == line.slot.segments and line.segment_scene(1) != null, "Sandbag segments stand on the line")
	check(line.max_hp() == SandbagLine.SANDBAG_HP and line.armor() == SandbagLine.ARMOR, "The line has its own health and armour")
	line.damage(100.0)
	check(absf(line.hp - (SandbagLine.SANDBAG_HP - 80.0)) < 0.01 and line.under_attack(), "A hit is partly shrugged off and raises the alert")
	game.hud._update_attack_dirs(0.1)
	var arrow := false
	for a in game.hud._attack_arrows:
		if a[1] == "Sandbags": arrow = true
	check(arrow, "The HUD arrows point at the attacked line")
	# ---- zombies inside the gate attack the line on their way in
	var player: Player = game.player
	var inward: Vector2 = xz(line.center) - xz(gate.center)
	inward = inward.normalized()
	var behind: Vector2 = xz(line.center) + inward * 4.0
	player.global_position = Map.ground_pos(behind.x, behind.y) + Vector3.UP * 0.3
	player.set_physics_process(false)
	var between: Vector2 = xz(line.center) - inward * 4.0
	var spawned: bool = game.spawn_zombie("shambler", between, 1.0)
	var zombie: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie: zombie = z
	if zombie: zombie.raider = false
	var before: float = line.hp
	var t := 0.0
	while t < 14.0 and line.hp >= before:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	check(spawned and zombie != null and zombie.siege_target == line, "The zombie between gate and line goes for the sandbags")
	check(line.hp < before, "The sandbag line takes the zombie's hits (%.0f -> %.0f after %.1f s)" % [before, line.hp, t])
	zombie.die(Vector3.FORWARD)
	# ---- the player vaults it
	player.global_position = Map.ground_pos(between.x, between.y) + Vector3.UP * 0.3
	var to_line: Vector3 = line.center - player.global_position
	player.rotation.y = atan2(-to_line.x, -to_line.z)
	var stand: Vector3 = line.attack_point(player.global_position) - Vector3(inward.x, 0.0, inward.y) * 1.0
	player.global_position = Map.ground_pos(stand.x, stand.z) + Vector3.UP * 0.05
	await physics_frame
	await physics_frame
	check(player._barricade_ahead(), "Space in front of the line finds it to climb over")
	# ---- repair and rebuild with E, paid from the player's money
	player.score = 0
	check(Lang.text(line.action_error(player, "repair")).begins_with("You are"), "Repairing needs Rem Dollars")
	player.score = SandbagLine.REPAIR_COST_SB
	check(line.purchase(player, "repair") and line.hp == line.max_hp() and player.score == 0, "Repair refills the line for its price")
	check(Lang.text(line.prompt_text()).contains("repair"), "The prompt offers the repair")
	line.damage(1e6)
	check(line.level == 0 and line.hp == 0.0 and Lang.text(game.hud.msg_label.text).contains("destroyed"), "A destroyed line falls back to a site")
	check(Lang.text(line.action_error(player, "build")).begins_with("You are"), "Rebuilding needs Rem Dollars")
	player.score = SandbagLine.DEPLOY_COST
	player.global_position = Map.ground_pos(behind.x, behind.y) + Vector3.UP * 0.3
	check(line.purchase(player, "build") and line.level == 1 and player.score == 0, "The line can be rebuilt for its price")
	check(line.action_error(player, "build") == "The sandbag line already stands.", "A standing line refuses a second build")
	# ---- the snapshot carries every line
	var snapshot: Dictionary = NetSession.world.snapshot()
	check(snapshot.has("sandbags") and snapshot.sandbags.size() == 4 and int(snapshot.sandbags[1][0]) == 1, "The co-op snapshot carries the sandbag lines")
	check(snapshot.has("purse") and int(snapshot.purse) == 0, "The snapshot carries the gate fund")
	# ---- the gate rebuilt: the line stays
	gate.build()
	check(gate.level == 1 and line.level == 1, "A rebuilt gate leaves the sandbag line standing")
	print("SANDBAGS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
