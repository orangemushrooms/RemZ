extends SceneTree
# Rendered regression: real pointer/key events must leave each menu detail without a scene reload.
var game: Node
var hud: Hud
var checks := 0
var failures := 0
var home_signals := 0
var began := Time.get_ticks_msec()
const FOLDER := "res://../artifacts/survival-menu/"

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 120000: quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)
func settle() -> void:
	for i in 5: await process_frame
func click(control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await settle()
func escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event, true)
	await settle()
func shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FOLDER + name + ".png")
func texts(node: Node) -> String:
	var result := ""
	if node is Label or node is Button: result += str(node.text) + "\n"
	for child in node.get_children(): result += texts(child)
	return result

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	game = load("res://scripts/main.gd").new()
	game.hud = Hud.new()
	hud = game.hud
	hud.game = game
	root.add_child(hud)
	hud.set_process(false)
	game.settings = GameSettings.new()
	root.add_child(game.settings)
	game.settings.main = game
	game.settings.add_controls(hud.settings_box, false)
	hud.set_difficulties(GameSettings.DIFFICULTIES, 1, func(_i: int): pass)
	hud.main_menu_pressed.connect(func(): home_signals += 1)
	hud.show_overlay("REMZ", Hud.SURVIVAL_BRIEFING, "Start game", "", "start")
	paused = true
	await settle()
	check(not hud._menu_detail.visible, "Launch shows the main menu")
	check(not texts(hud.overlay).to_lower().contains("heitersberg"), "Main menu has no Heitersberg subtitle or single-map briefing")
	check(Hud.SURVIVAL_BRIEFING.contains("25 waves") and Hud.SURVIVAL_BRIEFING.contains("campaign map"), "Briefing explains the campaign and survival objective")
	for locale in ["en", "de"]:
		Lang.set_language(locale)
		for tab in ["briefing", "multiplayer", "difficulty", "controls", "settings", "records", "achievements"]:
			await click(hud._tab_buttons[tab])
			check(hud._menu_detail.visible and hud._detail_back.is_visible_in_tree(), "%s/%s exposes the return button" % [locale, tab])
			await click(hud._detail_back)
			check(not hud._menu_detail.visible and hud.overlay.visible and not game.started and paused, "%s/%s returns to home without starting the game" % [locale, tab])
			await click(hud._tab_buttons[tab])
			await escape()
			check(not hud._menu_detail.visible, "%s/%s also returns with Escape" % [locale, tab])
		hud.show_tab("briefing")
		await shot("briefing-" + locale)
		check(TranslationServer.translate(Hud.SURVIVAL_BRIEFING).contains("Zombie-Survival" if locale == "de" else "zombie survival"), "Briefing follows the language setting")
		hud.return_to_menu_home()
		await shot("home-" + locale)
	check(home_signals == 0, "Returning from a start-menu detail never requests a scene reload")
	var character_menu: Control = hud.overlay.get_node("CharacterMenu")
	hud.show_tab("briefing")
	character_menu.open_page("skills")
	await settle()
	await escape()
	check(not character_menu.modal.visible and hud._menu_detail.visible, "Escape closes a character dialog before the underlying detail")
	await escape()
	check(not hud._menu_detail.visible, "The next Escape returns to home")
	hud.show_map_selection()
	await settle()
	await escape()
	check(not hud.map_selection.visible and hud._card.visible, "Escape still exits map selection")
	root.size = Vector2i(1280, 720)
	hud.show_tab("briefing")
	await shot("briefing-720p")
	check(root.get_visible_rect().encloses(hud._detail_back.get_global_rect()), "The return button is fully reachable at 720p")
	await click(hud._detail_back)
	check(not hud._menu_detail.visible, "The actual return button works at 720p")
	game.started = true
	hud.show_overlay("PAUSED", "", "Continue", "", "pause")
	await settle()
	check(not hud._detail_back.visible and hud._home_button.visible, "Pause keeps the existing leave-round navigation")
	await click(hud._home_button)
	check(home_signals == 1, "Pause return still requests the normal main-menu transition")
	print("SURVIVAL_MENU_DONE checks=%d failures=%d" % [checks, failures])
	game.settings.queue_free()
	hud.queue_free()
	await process_frame
	game.free()
	quit(1 if failures else 0)
