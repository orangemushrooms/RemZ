extends SceneTree
# Run windowed: the headless display cannot capture the mouse.
const Classes = preload("res://scripts/character_classes.gd")
var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 300000: print("TELEPORT_INPUT_TIMEOUT"); quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("teleport_input requires a windowed renderer for mouse capture")
		quit(1)
		return
	CharacterProfile.data = CharacterProfile.empty_profile("Teleport test")
	CharacterProfile.data.selected = "assassin"
	CharacterProfile.data.classes.assassin.total_xp = Classes.threshold(15)
	CharacterProfile.choose_teleport("map")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	check(AssassinTeleport.mode_for(game.player) == "map", "Starting a round equips the saved map mode")
	key(KEY_V)
	for i in 4: await process_frame
	check(game.teleport.is_open and not game.player.active, "V opens map targeting through the actual input action")
	key(KEY_ESCAPE)
	check(not game.teleport.is_open and game.player.active and not paused, "Escape closes targeting without opening the pause menu")
	var landing := {}
	for distance in [6.0,12.0,20.0,30.0]:
		for angle in 16:
			var target: Vector2 = Vector2(game.player.position.x,game.player.position.z) + Vector2.RIGHT.rotated(angle * TAU / 16.0) * float(distance)
			landing = game.teleport.destination(game.player,target)
			if landing.has("point"): break
		if landing.has("point"): break
	check(landing.has("point"), "A safe map target exists on the actual level")
	if not landing.has("point"): quit(1); return
	var goal: Vector3 = landing.point
	key(KEY_V)
	for i in 4: await process_frame
	var local: Vector2 = game.teleport.map_view.pixel(Vector2(goal.x,goal.z))
	var click := InputEventMouseButton.new()
	click.position = game.teleport.map_view.get_global_transform_with_canvas() * local
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	check(game.teleport._pending and game.teleport._point.distance_to(Vector2(goal.x,goal.z)) < 0.1, "The map click resolves to the intended world coordinates")
	for i in 4: await physics_frame
	click.pressed = false
	root.push_input(click,true)
	check(not game.teleport.is_open and game.player.teleport_serial == 1, "Clicking the actual map performs one teleport and closes targeting")
	check(game.player.position.distance_to(goal) < 1.0 and game.player.active, "The player lands at the chosen map point with controls restored")
	check(game.player.teleport_cooldown > 29.0, "Successful map input starts the 30-second cooldown")
	key(KEY_V)
	check(not game.teleport.is_open and game.player.teleport_serial == 1, "V cannot reopen targeting while recharging")
	game.teleport.set_physics_process(false)
	game.player.teleport_cooldown = 5.0
	paused = true
	game.teleport._physics_process(3.0)
	check(game.player.teleport_cooldown == 5.0, "Solo pause does not spend teleport cooldown")
	paused = false
	print("TELEPORT_INPUT_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
