extends SceneTree

var game: Node
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func press(key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var bar = game.quickbar
	check(bar.buttons.size() == 10, "Ten quick slots are built")
	bar.bind_item(1, "hatchet")
	check(bar.bindings[1].is_empty(), "Items not owned cannot be assigned")
	await press(KEY_0)
	check(game.weapons.current == "knife", "0 activates slot ten")
	game.inventory.mushrooms.steinpilz = 2
	bar.bind_item(0, "steinpilz")
	game.player.hp = 30
	await press(KEY_1)
	check(game.player.hp == 55 and game.inventory.mushrooms.steinpilz == 1, "Number key consumes a bound mushroom once")
	check(game.weapons.current == "knife", "Old number-key weapon polling does not override a binding")
	await press(KEY_1)
	await press(KEY_1)
	check(game.inventory.mushrooms.steinpilz == 0 and bar.bindings[0] == "steinpilz", "Empty stacks retain the binding without consuming again")
	game.inventory.mushrooms.steinpilz = 1
	bar.refresh()
	check(bar.counts[0].text == "1" and bar.item_data("steinpilz").owned, "Replenished stacks become usable again")
	game.inventory.open()
	await process_frame
	await press(KEY_1)
	check(game.inventory.mushrooms.steinpilz == 1, "Inventory blocks quick-use actions")
	bar.offer_item("steinpilz")
	bar._pick(4)
	bar.picker.hide()
	check(bar.bindings[4] == "steinpilz", "Inventory item picker assigns the chosen slot")
	bar.show_picker(4)
	bar._pick(0)
	bar.picker.hide()
	check(bar.bindings[4].is_empty(), "Slot picker can clear a binding")
	game.inventory.close()
	game.fireworks.stock(game.player.peer_id).fw_ruby = 1
	bar.bind_item(1, "fw_ruby")
	await press(KEY_2)
	check(game.fireworks.armed and game.fireworks.selected == "fw_ruby", "Number key selects bound fireworks")
	await press(KEY_3)
	check(game.fireworks.armed, "Empty quick slot does not cancel fireworks")
	bar.bind_item(2, "pistol")
	await press(KEY_3)
	check(not game.fireworks.armed and game.weapons.current == "pistol", "Bound weapon restores gun after fireworks")
	bar.bind_item(3, "grenade")
	var before: int = game.weapons.grenades
	await press(KEY_4)
	check(game.weapons.grenades == before - 1, "Bound grenade uses the existing throw action")
	var rare: Dictionary = game.progression.rare_market.data(game.player.peer_id)
	rare.owned.hawk = true
	bar.bind_item(5, "hawk")
	await press(KEY_6)
	check(rare.active == "hawk", "Bound talisman equips through the existing action")
	rare.ammo.fire = 2
	bar.bind_item(6, "fire")
	await press(KEY_7)
	check(rare.mode == "fire", "Bound special ammo activates")
	game.player.active = false
	await press(KEY_4)
	check(game.weapons.grenades == before - 1, "Modal state blocks quick-use actions")
	game.player.active = true
	await process_frame
	check(bar.bar.get_global_rect().end.y <= root.get_visible_rect().size.y, "Quickbar fits within viewport")
	if "--render-quickbar" in OS.get_cmdline_user_args():
		game.inventory.open()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../logs/quickbar-inventory.png")
		bar.show_picker(0)
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../logs/quickbar-picker.png")
	print("QUICKBAR_DONE checks=%d failures=%d" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
