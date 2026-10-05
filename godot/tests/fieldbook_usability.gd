extends SceneTree
var checks := 0
var failures := 0
var game: Node3D
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("test")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began > 600000:
		print("FAIL: fieldbook timeout")
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func test() -> void:
	for region in ["forest", "planes"]: await _map(region)
	print("FIELDBOOK_USABILITY_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _map(region: String) -> void:
	game = load("res://scenes/%s.tscn" % ("planes" if region == "planes" else "main")).instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if region == "planes":
		while not game.ready_for_exploration or game.preparing_survival or game.boot != null: await process_frame
	if region == "forest": game._on_start(false)
	if DisplayServer.get_name() != "headless": await create_timer(0.6, true).timeout
	paused = false
	game.waves.set_process(false)
	game.expedition.set_process(false)
	game.player.set_physics_process(false)
	game.player.active = true
	game.day_night.set_process(false)
	game.weather.set_process(false)
	var run: RunDirector = game.expedition
	var book: CanvasLayer = run.book
	book._process(1)
	check(not book.status.visible and not book.launch.visible, region+": no permanent key list or launcher in the playing view")
	game.started = false
	book.open()
	check(not book.is_open, "Fieldbook cannot open before the game begins")
	game.started = true
	game.player.controlling_drone = 1
	book.open()
	check(not book.is_open, "Fieldbook does not interrupt drone control")
	game.player.controlling_drone = 0
	book.open()
	check(book.is_open and paused and not game.player.active, "Solo fieldbook pauses and releases the mouse")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and root.gui_get_focus_owner() == book._navigation[0], "Keyboard starts on visible navigation and mouse is available")
	check(book._backdrop.visible, "Modal backdrop intercepts clicks outside the book")
	check(book.pages.get_tab_count() == 5 and not book.pages.tabs_visible, "Five short navigation sections replace crowded tabs")
	for i in 3: await process_frame
	check(book._close_button.size.x >= 150 and book._close_button.size.y <= 60, "Close button remains a readable compact control")
	check(not book._exploration.is_visible_in_tree(), "Distant opportunities start collapsed")
	check(not book._interact_button.visible or not run.nearest(game.player).is_empty(), "World interaction only appears for an actual nearby objective")
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.content_scale_size = size
		for i in 4: await process_frame
		for index in book.pages.get_tab_count():
			book._navigation[index].pressed.emit()
			for i in 3: await process_frame
			check(book.pages.current_tab == index and book._navigation[index].button_pressed, "Navigation opens page %d at %s" % [index, size])
			if not root.get_visible_rect().encloses(book.panel.get_global_rect()): print("LAYOUT viewport=", root.get_visible_rect(), " panel=", book.panel.get_global_rect(), " minimum=", book.panel.get_combined_minimum_size())
			check(root.get_visible_rect().encloses(book.panel.get_global_rect()), "Page %d fits %s including real minimum sizes" % [index, size])
			var scroll: ScrollContainer = book.pages.get_child(index)
			check(scroll.get_h_scroll_bar().max_value <= scroll.size.x+1, "Page %d has no inaccessible horizontal overflow" % index)
			check(book.pages.size.y >= 350, "Page %d retains room for readable content instead of a tall header" % index)
			await _capture(region, "page-%d-%d" % [index, size.y])
	book._navigation[2].grab_focus()
	for pressed in [true, false]:
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.physical_keycode = KEY_ENTER
		enter.pressed = pressed
		Input.parse_input_event(enter)
		await process_frame
	check(book.pages.current_tab == 2, "Focused navigation responds to the real Enter key")
	book.pages.current_tab = 4
	book._code.get_parent().show()
	await process_frame
	book._code.grab_focus()
	book._code.text = "RZ"
	var type_k := InputEventKey.new()
	type_k.keycode = KEY_K
	type_k.physical_keycode = KEY_K
	type_k.unicode = 107
	type_k.pressed = true
	Input.parse_input_event(type_k)
	await process_frame
	check(book.is_open and book._code.text.contains("k"), "Typing K in a run code edits text without closing the fieldbook")
	type_k.pressed = false
	Input.parse_input_event(type_k)
	book._code.text = "invalid-code"
	book._apply_code.pressed.emit()
	check(not Lang.text(book.message_label.text).is_empty() and book.is_open, "Invalid code gives feedback without dismissing the book")
	book._code.text = RunRules.encode(run.config)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	book._input(escape)
	check(not book.is_open and not paused and game.player.active and root.gui_get_focus_owner() == null, "Escape restores play and releases stale GUI focus")
	game.hud.show_overlay("Paused", "", "Continue", "", "pause")
	paused = true
	game.player.active = false
	game.hud.fieldbook_button.grab_focus()
	book.open()
	check(book.is_open, "Pause-menu entry can open the fieldbook")
	book.close()
	check(paused and not game.player.active and game.hud.overlay.visible, "Closing returns to the original pause menu")
	check(root.gui_get_focus_owner() == game.hud.fieldbook_button, "Keyboard focus returns to the pause-menu entry")
	game.hud.hide_overlay()
	paused = false
	game.player.active = true
	book.open()
	game.player.downed = true
	book._process(1)
	check(not book.is_open and not game.player.active, "Downing closes the book without reactivating the player")
	game.player.downed = false
	game.player.active = true
	game.waves.wave = 3
	game.waves.completed = 3
	run.wave_cleared(3)
	book.open()
	book.pages.current_tab = 1
	book.refresh()
	await process_frame
	check(book._navigation[1].text.contains("•"), "New augment choice has a quiet navigation indicator")
	check(book._apply_code.disabled and book._apply_mode.disabled and not book._code.editable, "Locked run settings are unavailable after the first wave")
	await _capture(region, "augment-offers")
	var offer: String = run.person(game.player.peer_id).offers[0]
	book._request("augment", [offer])
	check(run.person(game.player.peer_id).augments.has(offer) and run.person(game.player.peer_id).offers.is_empty(), "Selecting an augment applies exactly one live offer")
	check(not book._navigation[1].text.contains("•"), "Augment indicator clears after the choice")
	if region == "planes":
		check(not book._fire_button.visible, "No extinguish button when there is no nearby fire")
		for button in book._range_buttons: check(button.disabled, "Shooting challenges cannot start outside the unlocked range")
		game.player.global_position = run.camp()
		book.refresh()
		check(book._camp_actions.visible and book._contract_button.visible, "Camp services appear when standing at camp")
		game.player.global_position = run.camp()+Vector3(60, 0, 0)
		book.refresh()
		check(not book._camp_actions.visible, "Camp services disappear away from camp")
		var fires: Node3D = game.cornfield.fires
		var cell: Vector2i = fires.wheat.keys()[0]
		game.player.global_position = fires.wheat[cell]
		fires._light(cell, 1, "test")
		book.refresh()
		check(book._fire_button.visible, "Real nearby crop fire offers the extinguish action")
		book._request("extinguish")
		check(not fires.active.has(cell), "Contextual extinguish action removes the actual fire")
		book.close()
	else:
		run.person(game.player.peer_id).cooldown = 0
		book._request("ability")
		check(not book.is_open and game.player.active and not paused, "Using a ready combat action returns control immediately")
	paused = false
	game.queue_free()
	await process_frame
	await physics_frame
	current_scene = null

func _capture(region: String, page: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://../artifacts/fieldbook-polish/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory+region+"-"+page+"-"+Lang.current+".png") == OK, "Rendered fieldbook captured: "+page)
