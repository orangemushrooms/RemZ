extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready:
		await process_frame
	game._on_start()
	game.waves.set_process(false)
	await physics_frame
	var menu = game.cheat_menu
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_D
	shortcut.ctrl_pressed = true
	shortcut.shift_pressed = true
	shortcut.pressed = true
	Input.parse_input_event(shortcut.duplicate())
	check(menu.is_open and menu.panel.visible and paused and not game.player.active, "Shortcut opens the cheat menu and pauses solo gameplay")
	check(not game.hud.minimap.reveal_secret, "Opening the menu does not toggle the secret vendor")
	shortcut.echo = true
	Input.parse_input_event(shortcut.duplicate())
	check(menu.is_open, "Holding the shortcut does not repeatedly toggle the menu")
	shortcut.echo = false
	Input.parse_input_event(shortcut.duplicate())
	check(not menu.is_open and not paused and game.player.active, "Shortcut closes the menu and restores gameplay")
	game.waves.start(1)
	game.spawn_zombie("shambler", Vector2(30, 30), 1.0)
	game.spawn_zombie("brute", Vector2(35, 30), 1.0)
	var victims: Array = game.zombies_root.get_children()
	check(game.alive_zombies() == 2 and not game.waves.queue.is_empty(), "Wave has living enemies and pending spawns")
	menu.open()
	menu.skip_button.pressed.emit()
	check(not menu.is_open and not paused and game.player.active, "Skip button resumes gameplay")
	check(game.alive_zombies() == 0, "Skipping kills every living zombie and updates the enemy count")
	for zombie in victims:
		check(not zombie.alive and zombie.collision_layer == 0, "Skipped enemies use normal death behaviour")
	check(game.waves.wave == 2 and game.waves.completed == 1 and game.waves.phase == "spawning", "Skip completes the current wave and immediately starts the next")
	check(game.waves.queue.size() == game.waves.preview_count(2), "Only the next wave remains queued")
	game.waves.queue.clear()
	game.waves._process(0.0)
	var score_before: int = game.player.score
	check(game.waves.phase == "idle" and game.waves.completed == 2, "Normal wave completion still works")
	game.waves.skip_current_wave()
	check(game.waves.wave == 3 and game.player.score == score_before, "Skipping intermission starts the next wave without duplicate rewards")
	game.intro.road_reached.emit()
	check(game.waves.wave == 3, "Intro cannot reset a skipped wave back to wave one")
	menu.open()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	check(not menu.is_open and not paused and not game.hud.overlay.visible, "Escape closes only the cheat menu")
	game.player.active = false
	menu.open()
	check(not menu.is_open, "Cheat menu does not replace another modal")
	game.over = true
	check(not game.waves.skip_current_wave() and game.waves.wave == 3, "Cannot skip waves after game over")
	print("CHEAT_MENU_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
