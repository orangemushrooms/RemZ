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

func shot(menu: CanvasLayer, name: String) -> void:
	if "--render-cheats" not in OS.get_cmdline_user_args(): return
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/cheat-menu/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + name + ".png")
	var bounds: Rect2 = menu.box.get_global_rect()
	check(root.get_visible_rect().encloses(bounds), "Cheat menu fits the viewport: " + name)

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
	var starting_points: int = game.player.score
	menu.points_button.pressed.emit()
	check(game.player.score == starting_points + 1000 and Lang.text(menu.status.text).contains(str(game.player.score)), "Points button credits 1000 points and updates the displayed balance while paused")
	menu.points_button.pressed.emit()
	check(game.player.score == starting_points + 2000 and menu.is_open and paused, "Points button can be used repeatedly without closing or resuming the game")
	# Weapon cheat: any weapon, unlocked with a full magazine and a full reserve, straight into the hands.
	var w: Weapons = game.weapons
	check(menu.weapon_buttons.size() == Weapons.ORDER.size() and Weapons.ORDER.all(func(id): return menu.weapon_buttons.has(id)), "Every weapon has its own cheat button (%d)" % menu.weapon_buttons.size())
	menu.weapon_buttons["minigun"].pressed.emit()
	var belt: Dictionary = w.state["minigun"]
	check(w.unlocked.get("minigun", false) and w.current == "minigun", "The weapon button unlocks the minigun and puts it in the hands")
	check(int(belt.ammo) == int(belt.def.mag) and int(belt.reserve) == w.reserve_limit("minigun"), "The minigun comes with a full belt and a full reserve (%d + %d)" % [belt.ammo, belt.reserve])
	check(menu.is_open and paused and Lang.text(menu.weapon_note.text).contains(str(Weapons.DEFS["minigun"].name)), "The menu stays open and names what was handed out")
	belt.ammo = 3
	belt.reserve = 0
	menu.weapon_buttons["minigun"].pressed.emit()
	check(int(belt.ammo) == int(belt.def.mag) and int(belt.reserve) == w.reserve_limit("minigun"), "Pressing an owned weapon fills it up again")
	menu.weapon_buttons["plasma_sniper"].pressed.emit()
	var plasma: Dictionary = w.state["plasma_sniper"]
	plasma.heat = 1.0
	plasma.vent = true
	plasma.ammo = 0
	plasma.reloading = 2.5
	menu.weapon_buttons["plasma_sniper"].pressed.emit()
	check(float(plasma.heat) == 0.0 and not plasma.vent and float(plasma.reloading) == 0.0 and int(plasma.ammo) == int(plasma.def.mag) and not w.specials.blocks_fire(w, "plasma_sniper"),
		"An overheated plasma rifle comes back cold and loaded")
	menu.all_weapons_button.pressed.emit()
	var all_full := true
	for id: String in Weapons.ORDER:
		if not w.unlocked.get(id, false): all_full = false
		elif not Weapons.is_melee(id) and (int(w.state[id].ammo) != int(w.state[id].def.mag) or int(w.state[id].reserve) != w.reserve_limit(id)): all_full = false
	check(all_full, "'Alle Waffen' unlocks every weapon with a full magazine and reserve")
	check(w.current == "plasma_sniper" and menu.is_open and paused, "'Alle Waffen' leaves the weapon in the hands and the menu open")
	# The Golden Bolete: placed when none is out this round, then marked on the map; off hides the marker.
	var gold: Loot = game.gold_mushroom
	gold.taken = true
	gold.hide()
	menu.gold_toggle.button_pressed = true
	check(game.hud.minimap.reveal_gold and not gold.taken and gold.visible and Map.in_forest(gold.global_position.x, gold.global_position.z), "The Golden Bolete toggle places one in the forest and marks it on the map")
	var spot := gold.global_position
	menu.gold_toggle.button_pressed = false
	check(not game.hud.minimap.reveal_gold, "Turning the toggle off removes the map marker")
	menu.gold_toggle.button_pressed = true
	check(gold.global_position == spot and not gold.taken, "A Golden Bolete that is already out keeps its spot")
	menu.gold_toggle.button_pressed = false
	# Both hut keys at once; a key still lying in the forest disappears like a collected one.
	game.forest_keys.owned.clear()
	menu.keys_button.pressed.emit()
	check(game.forest_keys.has_key("waldhuette") and game.forest_keys.has_key("holzlager"), "The keys button hands out both hut keys")
	var lying := false
	for key: ForestKey in game.forest_keys.spawned:
		if not key.taken: lying = true
	check(not lying and menu.is_open and paused, "No hut key is left in the forest and the menu stays open")
	# Every catalogue type and every legal helmet variant must be reachable from a real button.
	check(Zombie.TYPES.keys().all(func(kind): return menu.spawn_buttons.has(kind)), "Every enemy type has a spawn button")
	var armored_count := 0
	for kind: String in Zombie.TYPES:
		if Zombie.can_be_armored(kind): armored_count += 1
	check(menu.spawn_buttons.size() == Zombie.TYPES.size() + armored_count, "All supported armored variants are included, with no duplicate entries")
	if "--render-cheats" in OS.get_cmdline_user_args():
		Lang.set_language("de")
		await shot(menu, "enemies-top")
		menu.spawn_scroll.ensure_control_visible(menu.spawn_buttons["forest_spirit"])
		await shot(menu, "enemies-bosses")
		var original_size := root.size
		root.size = Vector2i(1280, 720)
		await shot(menu, "enemies-720p")
		root.size = original_size
		Lang.set_language("en")
	var original_position: Vector3 = game.player.global_position
	game.player.global_position = Map.ground_pos(10, 110)
	for key: String in menu.spawn_buttons:
		var kind := key.trim_prefix("armored:")
		var armored := key.begins_with("armored:")
		var count_before: int = game.zombies_root.get_child_count()
		menu.spawn_buttons[key].pressed.emit()
		var created: bool = game.zombies_root.get_child_count() == count_before + 1
		var enemy: Zombie = game.zombies_root.get_child(count_before) if created else null
		var correct := created and enemy.net_kind == kind and enemy.armored == armored and ResourceLoader.exists(enemy.model_path)
		if correct:
			if Zombie.is_worm_kind(kind): correct = enemy is Earthworm
			elif Zombie.is_titan_kind(kind): correct = enemy is Titan
			elif kind == "forest_spirit": correct = enemy is ForestSpirit
			elif Zombie.is_beast_kind(kind): correct = enemy is ZombieBeast
		check(correct and menu.is_open and paused, "Spawn button creates the correct enemy and keeps the menu open: " + key)
		if enemy:
			await process_frame
			enemy.queue_free()
			await process_frame
			await process_frame
	check(game.alive_zombies() == 0, "Removing test spawns restores the live enemy count")
	var children_before: int = game.zombies_root.get_child_count()
	menu._spawn("missing_enemy")
	menu._spawn("earthworm", true)
	check(game.zombies_root.get_child_count() == children_before and game.alive_zombies() == 0, "Invalid types and unsupported armor cannot create enemies")
	game.player.global_position = original_position
	shortcut.echo = true
	Input.parse_input_event(shortcut.duplicate())
	check(menu.is_open, "Holding the shortcut does not repeatedly toggle the menu")
	shortcut.echo = false
	Input.parse_input_event(shortcut.duplicate())
	check(not menu.is_open and not paused and game.player.active, "Shortcut closes the menu and restores gameplay")
	game.waves.start(1)
	game.spawn_zombie("shambler", Vector2(30, 30), 1.0)
	game.spawn_zombie("brute", Vector2(35, 30), 1.0)
	var victims: Array = game.zombies_root.get_children().filter(func(node): return node is Zombie)
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
