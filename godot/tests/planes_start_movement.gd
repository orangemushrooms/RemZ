extends SceneTree

var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func send_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	if "--from-map" in OS.get_cmdline_user_args():
		var main: Node3D = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
		while not main.navigation_ready:
			await process_frame
		main._enter_planes()
		while not current_scene or current_scene == main:
			await process_frame
		game = current_scene
	else:
		game = load("res://scenes/planes.tscn").instantiate()
		root.add_child(game)
		current_scene = game
	while not game.ready_for_exploration:
		await process_frame
	for frame in 10:
		await physics_frame
	var start: Vector3 = game.player.global_position
	var focused: Control = root.gui_get_focus_owner()
	print("START_MOVEMENT_BEGIN pos=%s active=%s alive=%s paused=%s floor=%s mouse=%s focus=%s overlay=%s" % [start,game.player.active,game.player.alive,paused,game.player.is_on_floor(),Input.mouse_mode,focused.get_path() if focused else "none",game.hud.overlay.visible])
	send_key(KEY_W,true)
	for frame in 60:
		await physics_frame
	send_key(KEY_W,false)
	var finish: Vector3 = game.player.global_position
	var distance := Vector2(start.x,start.z).distance_to(Vector2(finish.x,finish.z))
	print("START_MOVEMENT_END pos=%s velocity=%s horizontal=%.3f" % [finish,game.player.velocity,distance])
	var input_ready: bool = game.player.active and game.player.alive and not paused and not game.hud.overlay.visible and focused == null
	if DisplayServer.get_name() != "headless": input_ready = input_ready and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	send_key(KEY_ESCAPE,true)
	await process_frame
	send_key(KEY_ESCAPE,false)
	var paused_by_menu: bool = game.hud.overlay.visible and not game.player.active
	await process_frame
	send_key(KEY_ESCAPE,true)
	await process_frame
	send_key(KEY_ESCAPE,false)
	var resumed: bool = not game.hud.overlay.visible and game.player.active and root.gui_get_focus_owner() == null
	print("START_MOVEMENT_ESCAPE paused=%s resumed=%s" % [paused_by_menu,resumed])
	var failures := int(not input_ready) + int(distance < 1.0) + int(not paused_by_menu) + int(not resumed)
	print("START_MOVEMENT_DONE checks=4 failures=%d" % failures)
	quit(0 if failures == 0 else 1)
