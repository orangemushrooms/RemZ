extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)

func run() -> void:
	var game: Node3D = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	await game.start_survival()
	game.waves.set_process(false)
	var menu = game.cheat_menu
	var house = game.shooting_range
	check(not house.key_owned,"Schützenhaus key is not initially owned")
	menu.open()
	check(menu.is_open and menu.keys_button.visible and not menu.keys_button.disabled and menu.keys_button.text.contains("Schützenhaus"),"Planes cheat menu exposes the key action")
	menu.keys_button.pressed.emit()
	check(house.key_owned and house.key.taken and house.snapshot().key_owned,"Cheat grants the key and updates the shared range state")
	menu.keys_button.pressed.emit()
	check(menu.world_note.text.contains("already have") and house.key_owned,"Repeated cheat reports the already owned key")
	menu.close()
	game.player.global_position = house.house.to_global(Vector3(-0.8,0,4.5))
	check(house.transact(game.player,"door")=="Schützenhaus unlocked." and house.opened,"Granted key opens the shooting house")
	print("PLANES_CHEAT_KEY_DONE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
