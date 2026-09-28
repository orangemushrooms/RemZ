extends SceneTree
const Classes = preload("res://scripts/character_classes.gd")
var game: Node
var checks := 0
var failures := 0
var folder := "res://../artifacts/teleport/"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func shot(id: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + id + ".png")

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame

func choice(menu: Control, mode: String) -> Button:
	for pick: Button in menu.body.find_children("*", "Button", true, false):
		if pick.get_meta("teleport_mode", "") == mode: return pick
	return null

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	CharacterProfile.persist = false
	CharacterProfile.data = CharacterProfile.empty_profile("Assassin")
	CharacterProfile.data.selected = "assassin"
	CharacterProfile.data.classes.assassin.total_xp = Classes.threshold(14)
	game = load("res://scripts/main.gd").new()
	game.player = Player.new()
	game.player.remote_actor = true
	root.add_child(game.player)
	game.player.set_physics_process(false)
	game.player.position = Map.ground_pos(12,12) + Vector3.UP * 0.1
	game.zombies_root = Node3D.new()
	root.add_child(game.zombies_root)
	game.hud = Hud.new()
	game.hud.game = game
	root.add_child(game.hud)
	game.hud.set_process(false) # The UI fixture has no world interaction systems.
	game.player.hud = game.hud
	game.hud.minimap.setup(game.player,game)
	game.hud.show_overlay("REMZ", "", "Start game", "", "start")
	await shot("menu-v3")
	check(game.hud.overlay_wordmark.texture.resource_path.ends_with("remz_logo_v3.png"), "Approved logo is displayed in the real menu")
	var menu: Control = game.hud.overlay.get_node("CharacterMenu")
	menu.open_page("skills")
	for i in 12: await process_frame
	menu.feedback.text = ""
	await click(choice(menu,"map"))
	check(CharacterProfile.data.classes.assassin.teleport == "" and menu.feedback.text == menu._requirement(2), "Clicking the locked ability explains its level requirement")
	await shot("locked-en")
	CharacterProfile.data.classes.assassin.total_xp = Classes.threshold(15)
	CharacterProfile.changed.emit()
	for i in 12: await process_frame
	await click(choice(menu,"forward"))
	check(CharacterProfile.data.classes.assassin.teleport == "forward", "Forward can be equipped with a real menu click")
	for i in 12: await process_frame
	await click(choice(menu,"map"))
	check(CharacterProfile.data.classes.assassin.teleport == "map", "A map choice replaces the forward choice through the UI")
	Lang.set_language("de")
	await shot("skills-de")
	root.size = Vector2i(1280,720)
	await shot("skills-720p")
	check(menu.modal.get_global_rect().encloses(choice(menu,"map").get_global_rect()), "The active ability cards fit at 720p")
	menu.close()
	game.hud.hide_overlay()
	game.started = true
	game.player.active = true
	game.player.class_combat.configure(CharacterProfile.loadout())
	game.teleport = AssassinTeleport.new()
	root.add_child(game.teleport)
	game.teleport.setup(game)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var trigger := InputEventKey.new()
	trigger.physical_keycode = KEY_J
	trigger.keycode = KEY_J
	trigger.pressed = true
	root.push_input(trigger, true)
	check(game.teleport.is_open, "J opens the map through the configured input action")
	await shot("target-map-de")
	check(game.teleport.is_open and not game.player.active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Map targeting releases the cursor and suspends local controls")
	check(root.get_visible_rect().encloses(game.teleport.map_view.get_global_rect()), "Target map fits at 720p")
	var cancel: Button = game.teleport.panel.find_children("*", "Button", true, false)[0]
	await click(cancel)
	check(not game.teleport.is_open and game.player.active and game.player.teleport_cooldown == 0.0, "Cancel button closes the map without cooldown")
	game.teleport.open()
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	check(not game.teleport.is_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Escape cancels targeting and restores mouse capture")
	game.player.teleport_cooldown = 20
	await shot("cooldown-de")
	game.teleport.free()
	game.hud.free()
	game.player.free()
	game.zombies_root.free()
	game.free()
	print("TELEPORT_VISUAL_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
