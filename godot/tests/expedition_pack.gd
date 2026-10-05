extends SceneTree
## Loaded externally by Godot with --main-pack; game resources come from the release PCK.
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("test")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began > 300000: quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func test() -> void:
	var region := "forest"
	for flag in OS.get_cmdline_user_args():
		if flag.begins_with("--test-region="): region = flag.trim_prefix("--test-region=")
	check(not FileAccess.file_exists("res://tests/run.gd"), "Production pack excludes development test suites")
	var game = load("res://scenes/planes.tscn" if region == "planes" else "res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if region == "planes":
		while not game.ready_for_exploration or game.preparing_survival: await process_frame
	else: game._on_start(false)
	paused = false
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.expedition.set_process(false)
	var run = game.expedition
	check(run.enabled and run.book != null and run.structures != null, "Packed scene installs all expedition systems")
	check(run.configure({"seed": 72531, "region": region}), "Packed run can be configured before wave one")
	check(game.waves.plan(8) == game.waves.plan(8) and not game.waves.plan(8).is_empty(), "Packed wave plans are populated and deterministic")
	game.waves.wave = 3
	game.waves.completed = 3
	game.waves.phase = "idle"
	run.wave_cleared(3)
	check(run.person(1).offers.size() == 3, "Packed run offers three personal augments")
	run.book.open()
	check(paused and run.book.panel.visible, "Packed fieldbook opens and pauses solo play")
	run.book.close()
	game.player.global_position = run.camp()+Vector3(2, 0.3, 2)
	game.player.score = 389
	run.checkpoints.override_path = "user://packed_%s.save" % region
	check(run.checkpoints.save_run() == "Checkpoint saved.", "Packed game writes a validated checkpoint")
	game.player.score = 1
	check(run.checkpoints.load_run() == "Expedition continued." and game.player.score == 389, "Packed game restores its checkpoint")
	check(run.begin_finale() and game.waves.phase == "finale", "Packed game installs its region finale")
	paused = false
	game.queue_free()
	await process_frame
	await physics_frame
	print("EXPEDITION_PACK_DONE region=%s checks=%d failures=%d" % [region, checks, failures])
	quit(1 if failures else 0)
