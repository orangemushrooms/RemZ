# Context priority and advertised build/repair quotes; optional real-world HUD captures.
extends SceneTree

var game: Node3D
var checks := 0
var failures := 0
var capture := false
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func prompt() -> String:
	game._process(0.01)
	game.hud._update_prompt()
	return Lang.text(game.hud.prompt_label.text)

func settle() -> void:
	await physics_frame
	await physics_frame
	for i in 5: await process_frame

func shot(name: String) -> void:
	if not capture: return
	Lang.set_language("de")
	prompt()
	await settle()
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://../artifacts/interactions/")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir + name + ".png")
	Lang.set_language("en")

func run() -> void:
	capture = "--render-interactions" in OS.get_cmdline_user_args()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.set_process(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	game.defences.set_process(false)
	if capture:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
		game.day_night.set_time_hours(12)
		await create_timer(2.0).timeout
	var p: Player = game.player
	var card: InteractionPrompt = game.hud.prompt_card
	p.score = 10000
	p.global_position = Map.ground_pos(100, 100)
	game._process(30.0)
	check(prompt().contains("[T] Build menu"), "Build shortcut remains discoverable after the old 12-second limit")
	await shot("01-build-shortcut")
	p.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 2.5)
	p.camera.look_at(game.brewing.stations[0] + Vector3.UP * 0.6)
	await settle()
	var source := prompt()
	check(source.contains("[E] Grill") and source.contains("[C]") and source.contains("[T]"), "Grill, drinks and construction advertised together")
	await shot("02-campfire")
	check(not game.progression.tutorial.get_global_rect().intersects(card.get_global_rect()), "Tutorial guidance does not overlap nearby actions")
	var flower := Loot.new()
	game.add_child(flower)
	flower.setup("flower", "ember_lily", "Ember Lily")
	flower.global_position = p.global_position + Vector3(0, 0.8, -0.6)
	game.loots.append(flower)
	await settle()
	source = prompt()
	check(source.contains("[E] Collect Ember Lily") and source.contains("[C]") and source.contains("[T]") and not source.contains("[E] Grill"), "Brewing preserves the actual E pickup target without advertising a conflicting grill action")
	game.loots.erase(flower)
	flower.queue_free()
	game.brewing.menu.open()
	game.hud._update_prompt()
	check(game.brewing.menu.is_open and not card.visible, "Opening brewing hides world action prompts")
	game.brewing.menu.close()
	check(prompt().contains("[C]") and card.visible, "Closing brewing restores nearby actions")
	game.inventory.open()
	game.hud._update_prompt()
	check(not card.visible, "Inventory suppresses stale world actions even without clearing their text")
	game.inventory.close()
	p.global_position = game.hut.attack_point(game.hut.center + Vector3(20, 0, 0))
	game.hut.hp -= 500
	p.camera.look_at(game.hut.center + Vector3.UP * 2)
	await settle()
	source = prompt()
	check(source.contains("[E] Repair forest hut") and source.contains("[T] Forest hut"), "House repair and roof build menu remain visible together: " + source)
	check(source.contains("%d R" % game.hut.repair_quote().cost), "House prompt quotes the authoritative repair cost")
	await shot("03-hut")
	var wall: Barricade = game.barricades[0]
	p.global_position = wall.center + Vector3(wall.normal2.x, 0, wall.normal2.y) * 4.0
	p.global_position.y = Map.ground_height(p.position.x, p.position.z) + 0.1
	p.camera.look_at(wall.center + Vector3.UP)
	await settle()
	check(prompt().contains("[E] Build Timber palisade · 50 R"), "Unbuilt wall advertises its actual first tier and price")
	await shot("04-wall-build")
	wall.purchase(p, "build")
	check(prompt().contains("[E] Upgrade to Iron-banded wall · 120 R"), "Healthy wall advertises the next tier and upgrade price")
	await shot("05-wall-upgrade")
	wall.damage(50)
	check(prompt().contains("[E] Repair wall · 25 R"), "Damaged wall advertises repair before upgrade, matching E dispatch")
	await shot("06-wall-repair")
	wall.purchase(p, "repair")
	wall.purchase(p, "build")
	check(prompt().contains("[E] Upgrade to Steel bulwark · 220 R"), "Second-tier wall quotes the steel upgrade price")
	wall.purchase(p, "build")
	check(not Lang.text(wall.prompt_text()).contains("[E]") and prompt().contains("fully upgraded"), "Maximum wall tier stops advertising an impossible upgrade")
	var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(70, 40), 1)
	tower.set_physics_process(false)
	tower.hp -= 50
	p.global_position = tower.global_position + Vector3(0, 0, 3)
	p.camera.look_at(tower.global_position + Vector3.UP * 3)
	await settle()
	source = prompt()
	check(source.contains("[E] Operate") and source.contains("[R]") and source.contains("[F] Repair tower · 35 R") and source.contains("[T]"), "Tower offers operation, alignment, repair cost and build menu together")
	await shot("07-tower")
	root.size = Vector2i(1280, 720) if capture else root.size
	await shot("08-tower-720p")
	check(card.get_global_rect().end.y < root.get_visible_rect().size.y - 100 and card.size.y < 320, "Combined tower actions leave the quickbar visible")
	tower.operator_peer = 2
	source = prompt()
	check(source.contains("Tower occupied") and not source.contains("[R]") and not source.contains("[F]"), "Occupied tower hides unavailable repair and alignment shortcuts")
	tower.operator_peer = 0
	game.defences.begin_rotation(tower)
	game.defences._process(0.01)
	game.hud._update_prompt()
	check(not card.visible and game.defences.hint.visible, "Placement uses one action card without stale world prompts")
	await shot("09-align")
	game.defences.cancel_placement()
	game.defences.input_grace = 0
	game.defences.planner.open()
	game.defences.planner.hover_point = tower.global_position
	game.defences.planner._process(0.01)
	await shot("10-planner")
	game.defences.planner.close()
	p.active = false
	game.hud._update_prompt()
	check(not card.visible, "Inactive player cannot retain interaction prompts")
	print("INTERACTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
