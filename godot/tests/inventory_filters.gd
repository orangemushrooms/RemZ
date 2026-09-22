extends SceneTree

var game: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var inv = game.inventory
	inv.mushrooms.steinpilz = 2
	inv.mushrooms.goldroehrling = 1
	game.fireworks.stock(game.player.peer_id).fw_ruby = 1
	var rare: Dictionary = game.progression.rare_market.data(game.player.peer_id)
	rare.ammo.fire = 5
	rare.owned.hawk = true
	inv.open()
	await process_frame
	check(inv.category_buttons.size() == 5, "All and four category filters available")
	var total: int = inv.grid.get_child_count()
	var filtered_total := 0
	for category in range(1, 5):
		inv.category_buttons[category].pressed.emit()
		var matches := true
		for slot in inv.grid.get_children():
			matches = matches and int(slot.get_meta("category")) == category
		check(matches, "Filter only contains category %d" % category)
		filtered_total += inv.grid.get_child_count()
		check(inv.empty_label.visible == (inv.grid.get_child_count() == 0), "Empty state matches category %d" % category)
	check(filtered_total == total, "Every item belongs to exactly one category")
	inv.category_buttons[0].pressed.emit()
	for order in [1, 2]:
		inv.sort_select.select(order)
		inv.sort_select.item_selected.emit(order)
		var previous := ""
		var sorted := true
		for slot in inv.grid.get_children():
			var title := str(slot.get_meta("item_title"))
			var comparison := previous.naturalnocasecmp_to(title)
			if not previous.is_empty(): sorted = sorted and (comparison <= 0 if order == 1 else comparison >= 0)
			previous = title
		check(sorted, "Name sorting direction %d" % order)
	inv.category_buttons[1].pressed.emit()
	for slot in inv.grid.get_children():
		if str(slot.get_meta("item_title")).begins_with("Feldmesser"):
			slot.pressed.emit()
			break
	check(game.weapons.current == "knife", "Filtered sorted weapon remains usable")
	check(inv.category_filter == 1 and inv.sort_order == 2, "Refresh retains filter and sort")
	inv.category_buttons[3].pressed.emit()
	game.player.hp = 30
	for slot in inv.grid.get_children():
		if str(slot.get_meta("item_title")) == "Steinpilz":
			slot.pressed.emit()
			break
	check(inv.mushrooms.steinpilz == 1 and game.player.hp == 55, "Filtered food remains usable")
	inv.close()
	inv.open()
	check(inv.category_filter == 3 and inv.sort_order == 2, "Reopening retains selected view")
	inv.close()
	print("INVENTORY_FILTERS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
