extends "res://tests/expedition.gd"
## Separate write/read processes exercise restoration into a freshly constructed map.
func test() -> void:
	var region := "forest"
	var phase := "read"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-region="): region = arg.trim_prefix("--test-region=")
		if arg.begins_with("--checkpoint-phase="): phase = arg.trim_prefix("--checkpoint-phase=")
	game = load("res://scenes/planes.tscn" if region == "planes" else "res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if region == "planes":
		while not game.ready_for_exploration or game.preparing_survival: await process_frame
	run = game.expedition
	run.checkpoints.override_path = "user://restart_%s.save" % region
	if phase == "write":
		if region == "forest": game._on_start(false)
		paused = false
		run.configure({"seed": 782391, "region": region, "mode": "fortress"})
		game.waves.set_process(false)
		game.player.set_physics_process(false)
		run.set_process(false)
		game.waves.wave = 3
		game.waves.completed = 3
		game.waves.phase = "idle"
		game.waves.queue.clear()
		game.player.global_position = run.camp()+Vector3(2, 0.3, 2)
		game.player.score = 473
		game.player.hp = 62
		game.weapons.state.pistol.reserve = 23
		game.weapons.set_process(false)
		game.weapons.unlock("plasma_sniper")
		game.weapons.set_weapon("plasma_sniper")
		game.weapons.state.plasma_sniper.heat = 0.82
		game.weapons.state.plasma_sniper.vent = true
		game.weapons.state.plasma_sniper.reloading = 2.0
		run.person(1).bandages = 5
		run.person(1).augments.append("frost")
		if region == "forest":
			game.loots[0].taken = true
			game.pumpkins[0].shatter(false)
			var path: String = run.checkpoints.windows.values()[0].path
			game.get_node(path).free()
		check(run.checkpoints.save_run() == "Checkpoint saved.", "First process writes a complete intermission save")
	else:
		game.waves.set_process(false)
		check(run.checkpoints.load_run() == "Expedition continued.", "Fresh process accepts and restores the checkpoint")
		check(game.started and game.player.alive and game.player.hp == 62 and game.player.score == 473, "Fresh map resumes the living player with saved health and money")
		check(game.waves.completed == 3 and game.waves.phase == "idle" and game.weapons.state.pistol.reserve == 23, "Fresh map restores wave progress and ammunition")
		check(run.config.seed == 782391 and run.config.mode == "fortress" and run.person(1).bandages == 5 and "frost" in run.person(1).augments, "Seed, challenge and selected augment survive process restart")
		check(game.weapons.current == "plasma_sniper" and game.weapons.state.plasma_sniper.vent and is_equal_approx(game.weapons.state.plasma_sniper.heat, 0.82) and game.weapons.state.plasma_sniper.reloading == 2.0 and game.weapons.specials.blocks_fire(game.weapons, "plasma_sniper"), "A warm plasma weapon keeps its fire lock and remaining cooling time after restart")
		if region == "forest":
			check(game.loots[0].taken and game.pumpkins[0].broken, "Collected loot and destroyed props stay unavailable after restart")
			check(game.get_node_or_null(run.checkpoints.windows.values()[0].path) == null, "Shattered windows stay shattered after restart")
	paused = false
	game.queue_free()
	await process_frame
	await physics_frame
	print("EXPEDITION_RESTART_DONE region=%s phase=%s checks=%d failures=%d" % [region, phase, checks, failures])
	quit(1 if failures else 0)
