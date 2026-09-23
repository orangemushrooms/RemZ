# How long the menu round trips take and how long the window stops answering (the longest gap
# between two frames). Windowed:
# Godot.exe --path godot --resolution 1600x900 --script res://tests/run.gd -- --suite=menu_timing --no-intro --no-music --profile-boot
extends SceneTree

var game: Node
var began := Time.get_ticks_msec()
var _last_frame := Time.get_ticks_usec()
var _worst_gap := 0.0

func _initialize() -> void:
	call_deferred("run")

func _process(_dt: float) -> bool:
	var now := Time.get_ticks_usec()
	_worst_gap = maxf(_worst_gap, (now - _last_frame) / 1000.0)
	_last_frame = now
	if Time.get_ticks_msec() - began > 600000:
		push_error("MENU_TIMING_TIMEOUT")
		quit(1)
	return false

func _ready_game() -> void:
	game = current_scene
	while not is_instance_valid(game) or not game.navigation_ready:
		await process_frame
		game = current_scene

func _lap(label: String, t0: int) -> void:
	print("MENU_TIMING %-28s total=%6.1f s  longest_frame_gap=%6.0f ms" % [label, (Time.get_ticks_msec() - t0) / 1000.0, _worst_gap])
	_worst_gap = 0.0

func run() -> void:
	var t0 := Time.get_ticks_msec()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _ready_game()
	_lap("first load", t0)
	# start, then pause -> Hauptmenü
	game._on_start()
	for i in 30: await process_frame
	game._pause()
	_worst_gap = 0.0
	t0 = Time.get_ticks_msec()
	game._to_main_menu()
	await scene_changed
	await _ready_game()
	_lap("pause -> Hauptmenü", t0)
	# start, die, Nochmal
	game._on_start()
	for i in 30: await process_frame
	game.player.damage(1e6)
	for i in 10: await process_frame
	_worst_gap = 0.0
	t0 = Time.get_ticks_msec()
	game._on_start()
	await scene_changed
	await _ready_game()
	for i in 10: await process_frame
	_lap("death -> Nochmal", t0)
	print("MENU_TIMING_DONE")
	quit(0)
