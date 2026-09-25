# Down instead of dead (26 Sep 2026, solo): the bleed-out, the hits that shorten it, the E hold that gets
# the player up once per wave, the wave end that restores it, and the death when the clock runs out.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=downed --smoke-test --no-intro --no-music --no-foliage
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

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var player: Player = game.player
	player.set_physics_process(false)
	check(player.alive and not player.downed and player.self_revives == 1, "The player starts up with one self revive")
	player.damage(500.0, player.global_position + Vector3.FORWARD * 3.0)
	check(player.downed and player.alive and player.hp == 0.0 and player.downs == 1, "A fatal hit puts the player down, not dead")
	check(absf(player.down_time - Player.DOWN_SECONDS) < 0.001 and player.active and not game.over, "The bleed-out clock starts and the game goes on")
	check(Lang.text(game.hud.msg_label.text).begins_with("YOU ARE DOWN"), "Going down is announced")
	check(game.pings.active.size() > 0 and game.pings.active.back().kind == "down" and game.stats.downs == 1, "The radio calls the down and the statistics count it")
	game._process(0.1)
	check(game.hud.downed_panel.visible and Lang.text(game.hud.downed_text.text).begins_with("YOU ARE DOWN"), "The HUD shows the down panel")
	await physics_frame
	await physics_frame
	check(player.crouching, "Down means crouched")
	player.damage(50.0)
	check(absf(player.down_time - (Player.DOWN_SECONDS - 50.0 * Player.HIT_BLEED)) < 0.01 and player.downed, "A hit while down bleeds the clock instead of the health (%.2f)" % player.down_time)
	check(player.hp == 0.0, "Health stays at zero while down")
	# no regeneration while down
	player.regen_timer = 0.0
	player._regenerate(5.0)
	check(player.hp == 0.0, "No regeneration while down")
	# ---- the E hold
	Input.action_press("interact")
	player._update_down(2.0)
	check(player.downed and absf(player.revive_hold - 2.0) < 0.001 and player.hold_fraction() == 0.5, "Holding E fills the bar")
	Input.action_release("interact")
	player._update_down(0.5)
	check(player.revive_hold < 2.0, "Letting go drains it")
	Input.action_press("interact")
	player._update_down(1.0)
	player._update_down(1.0)
	player._update_down(1.5)
	Input.action_release("interact")
	check(not player.downed and player.alive and player.hp == Player.SELF_REVIVE_HP and player.self_revives == 0, "Four seconds of E get the player back up with %d HP (down %s hp %.1f revives %d hold %.2f)" % [int(Player.SELF_REVIVE_HP), str(player.downed), player.hp, player.self_revives, player.revive_hold])
	check(player.regen_timer > 0.0, "Regeneration waits after getting up")
	game._process(0.1)
	check(not game.hud.downed_panel.visible, "The down panel is gone")
	# ---- the wave end restores the self revive and gets a downed player up
	game.waves.wave = 1
	game.waves._complete_wave()
	check(player.self_revives == 1, "A cleared wave restores the self revive")
	player.damage(500.0)
	check(player.downed, "Down again in the next wave (down %s alive %s hp %.1f)" % [str(player.downed), str(player.alive), player.hp])
	game.waves.wave = 2
	game.waves._complete_wave()
	check(not player.downed and player.hp == player.max_hp * 0.5, "A wave cleared while down gets the player up with half health")
	# ---- without a self revive left the clock runs out into death
	player.self_revives = 0
	player.damage(500.0)
	check(player.downed and player.self_revives == 0, "Down with no self revive left")
	Input.action_press("interact")
	player._update_down(5.0)
	Input.action_release("interact")
	check(player.downed and player.revive_hold == 0.0, "Holding E does nothing without a self revive")
	player.down_time = 0.05
	player._update_down(0.1)
	check(not player.alive and not player.downed and game.over, "Bleeding out ends the round")
	check(Lang.text(game.hud.overlay_title.text) == "YOU DIED", "... with the death screen")
	print("DOWNED_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
