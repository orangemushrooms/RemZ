# The team purse and the co-op side of the down mechanic and the radio (26 Sep 2026), on a hosted session
# without a network peer (like coop_snapshot_cost): deposits, gates paid from the fund, the wave fund,
# the snapshot, a client's ping through the host, the self revive hold and a teammate's revive.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=team_purse --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var game: Node
var net: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	check(net.host("Host", 24695) == OK, "The fixture hosts a round")
	if not net.is_host():
		quit(1)
		return
	net.roster[2] = "Anna"
	net.world.add_player(2)
	net._begin(net.epoch, false)
	game.waves.set_process(false)
	var world = net.world
	var host: Player = game.player
	var anna: Player = world.actor(2)
	host.set_physics_process(false)
	check(world.actors.size() == 2 and anna != null and anna.remote_actor, "Host and a teammate share the round")
	# ---- the purse
	check(world.purse == 0 and Barricade.purse() == 0, "The gate fund starts empty")
	host.score = 150
	world.action(1, "purse_deposit", [100])
	check(world.purse == 100 and host.score == 50 and Barricade.purse() == 100, "A deposit moves Rem Dollars into the fund")
	world.action(1, "purse_deposit", [77])
	world.action(1, "purse_deposit", [250])
	check(world.purse == 100 and host.score == 50, "Odd amounts and unaffordable deposits are refused")
	var gate: Barricade = game.barricades[0]
	host.global_position = gate.center + Vector3(gate.normal2.x, 0.3, gate.normal2.y) * 2.0
	check(gate.action_error(host, "build").is_empty(), "The fund counts towards a gate the player could not afford alone")
	check(gate.purchase(host, "build") and gate.level == 1, "The gate is built")
	check(world.purse == 50 and host.score >= 50, "The fund pays first, the player keeps their money (fund %d, pocket %d)" % [world.purse, host.score])
	host.score = 70
	check(gate.action_error(host, "build").is_empty() and gate.purchase(host, "build") and gate.level == 2, "Fund plus pocket pay the next tier (120 R)")
	check(world.purse == 0 and host.score == 0, "Both are drained exactly (fund %d, pocket %d)" % [world.purse, host.score])
	var anna_before: int = anna.score
	world.wave_cleared(20)
	check(world.purse == 10 + game.waves.wave * 3 and anna.score == anna_before + 20, "A cleared wave feeds the fund and pays everyone (fund %d, Anna +%d)" % [world.purse, anna.score - anna_before])
	var snapshot: Dictionary = world.snapshot()
	check(int(snapshot.purse) == world.purse, "The snapshot carries the fund")
	check(snapshot.players[2].has("down") and snapshot.players[2].down.size() == 5, "Player snapshots carry the down state")
	# ---- a client's ping through the host
	world.action(2, "ping", ["gate_hold", gate.center, "Hut Path"])
	check(game.pings.active.size() > 0 and game.pings.active.back().kind == "gate_hold" and game.pings.active.back().author == "Anna", "Anna's ping arrives through the host")
	world.action(2, "ping", ["bogus", gate.center, ""])
	world.action(2, "ping", ["gate_hold", Vector3(INF, 0, 0), ""])
	check(game.pings.active.size() == 1, "Unknown kinds and broken positions are dropped")
	# ---- a teammate down: the self revive hold runs on the host
	anna.global_position = host.global_position + Vector3(1.5, 0, 0)
	anna.damage(500.0, host.global_position)
	check(anna.downed and anna.alive and world.nearest_player(Vector3.ZERO) != null and not game.over, "Anna goes down; the team is not over")
	check(game.pings.active.back().kind == "down", "The radio calls her down")
	world.action(2, "self_revive", [true])
	check(world.revive.has(2) and int(world.revive[2].target) == 2, "Her E hold is registered")
	world.tick(2.0)
	check(anna.downed and anna.revive_hold > 1.5, "Two seconds in she is still down")
	world.action(2, "self_revive", [false])
	check(not world.revive.has(2), "Letting go cancels the hold")
	world.action(2, "self_revive", [true])
	world.tick(2.5)
	world.tick(2.5)
	check(not anna.downed and anna.hp == Player.SELF_REVIVE_HP and anna.self_revives == 0, "Four seconds of E get her up")
	# ---- the host revives her when she has no self revive left
	anna.damage(500.0, host.global_position)
	check(anna.downed, "Down again")
	world.action(2, "self_revive", [true])
	world.tick(5.0)
	check(anna.downed and not world.revive.has(2), "No self revive left: the hold does nothing")
	check(world.nearby_downed_player() == 2, "The host stands next to a downed teammate")
	world.action(1, "revive", [2])
	world.tick(1.5)
	check(anna.downed and world.revive.has(1), "Halfway through the three seconds")
	world.tick(2.0)
	check(not anna.downed and anna.hp == 50.0 and anna.alive, "The host's E gets her up with 50 HP")
	# ---- bleeding out in co-op leaves a body the team can still revive
	anna.damage(500.0, host.global_position)
	anna.down_time = 0.05
	anna._update_down(0.1)
	check(not anna.alive and not anna.downed and not game.over, "Bleeding out kills her; the team fights on")
	world.action(1, "revive", [2])
	world.tick(3.5)
	check(anna.alive and anna.hp == 50.0, "A dead teammate can still be revived by hand")
	world.wave_cleared(10)
	check(anna.self_revives == 1 and host.self_revives == 1, "The wave end restores every self revive")
	net.leave("done")
	print("TEAM_PURSE_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
