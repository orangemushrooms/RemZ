extends SceneTree
var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var rendered := false

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000: quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func shot(name: String) -> void:
	if not rendered: return
	await create_timer(0.8).timeout
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/campaign/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + name + ".png")

func run() -> void:
	rendered = "--render-campaign" in OS.get_cmdline_user_args()
	var state := Campaign.new()
	check(not state.persist, "Test campaign does not read or overwrite player progress")
	check(Campaign.REGIONS.size() == 6 and state.select("forest"), "Six regions; Forest is playable")
	for region: Dictionary in Campaign.REGIONS:
		if not region.available: check(not state.select(region.id), "Construction region cannot launch: " + region.id)
	check(not state.select("unknown") and state.selected_id == "forest", "Invalid selection preserves current map")
	state.record_wave(24, "Normal")
	check(state.best_wave("forest") == 24 and not state.cleared("forest"), "Twenty-four rounds do not clear a region")
	state.record_wave(25, "Normal")
	state.record_wave(3, "Easy")
	check(state.cleared_count() == 1 and state.best_wave("forest") == 25, "Replay cannot erase a victory or personal best")
	state.save_path = "user://campaign-test-%d.json" % OS.get_process_id()
	state.save_progress()
	state.save_progress()
	var restored := Campaign.new()
	restored.save_path = state.save_path
	restored.load_progress()
	check(restored.cleared_count() == 1 and restored.best_wave("forest") == 25, "Atomic save replacement survives a reload")
	DirAccess.remove_absolute(state.save_path)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	await shot("main-menu")
	game.hud.overlay_button.pressed.emit()
	await process_frame
	var selection: MapSelection = game.hud.map_selection
	check(selection.visible and not game.started and paused, "Start game opens the campaign map without starting the world")
	check(selection._selected.is_empty() and selection._preview_id.is_empty() and selection.atlas.selected.is_empty() and not selection._rows[0].has_focus() and selection._join.disabled,"Initial opening neither highlights nor focuses Forest")
	for i in 3: await process_frame
	check(selection.atlas.map_rect.position.is_zero_approx() and selection.atlas.map_rect.size.is_equal_approx(selection.atlas.size), "Selectable map fills its complete panel without side gutters")
	check((selection.get_child(0) as ColorRect).color.a == 1.0 and selection.modulate.a == 1.0, "Opaque campaign backing hides world-space hut labels even during the entrance")
	check(selection._join.get_global_rect().end.y < selection.size.y, "Forest entry button fits within the initial viewport")
	selection.atlas._call_in = 0.0
	selection.atlas._process(0.01)
	check(selection.atlas._crows.playing and selection.atlas._crows.volume_db <= -26.0, "Visible paused map plays a quiet crow recording")
	await shot("selection-forest")
	for entry: Dictionary in Campaign.REGIONS:
		var point: Vector2 = selection.atlas.map_rect.position + entry.anchor / Campaign.ART_SIZE * selection.atlas.map_rect.size
		check(selection.atlas.region_at(point) == entry.id, "Artwork and clickable region agree: " + entry.id)
	selection.choose("core")
	check(not game.started and selection._join.disabled, "Locked region is inspectable but cannot launch")
	selection.refresh()
	check(selection._selected.is_empty() and selection._preview_id.is_empty() and selection.atlas.selected.is_empty() and selection._join.disabled, "Reopening selection has no default region or launch action")
	selection.choose("core")
	selection.atlas._hover("core")
	await shot("selection-locked")
	selection.atlas._hover("")
	selection._selected = "forest"
	selection.atlas.selected = "forest"
	selection.refresh()
	if rendered:
		Lang.set_language("de")
		await shot("selection-de")
		root.size = Vector2i(1280, 720)
		await shot("selection-720p")
		root.size = Vector2i(2560, 1080)
		await shot("selection-ultrawide")
		root.size = Vector2i(1600, 900)
		Lang.set_language("en")
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	root.push_input(escape)
	await process_frame
	check(not selection.visible and game.hud._card.visible and not game.started, "Back returns to the menu")
	check(not selection.atlas._crows.playing, "Hidden atlas stops its crow recording immediately")
	game.hud.primary_action()
	selection.choose("core")
	selection._rows[0].focus_entered.emit()
	check(not selection._join.disabled and selection._preview_id == "forest", "Keyboard focus previews the actionable Forest selection")
	selection._join.pressed.emit()
	check(game.started and game.player.active and not paused and not game.hud.overlay.visible, "Forest launches the existing hut level")
	check(not selection.atlas._crows.playing and not game.hud.menu_map._crows.playing, "Map ambience stops when gameplay begins")
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.waves.wave = 24
	game.waves.phase = "spawning"
	game.waves.queue.clear()
	game.waves._complete_wave()
	check(not game.over and game.waves.phase == "idle" and game.campaign.best_wave("forest") == 24, "Round 24 gives intermission and persists progress")
	game.waves.start(25)
	check(game.waves.wave == 25 and game.waves.phase == "spawning" and not game.waves.queue.is_empty(), "Final round retains its complete boss/horde plan")
	game.waves.spawn_t = 100
	game.waves._process(0.01)
	check(not game.over, "Pending final-round enemies prevent victory")
	game.waves.queue.clear()
	game.spawn_zombie("shambler", Vector2(55, 120), 1.0)
	game.waves._process(0.01)
	check(not game.over, "A living final-round enemy prevents victory")
	for zombie in game.zombies_root.get_children():
		if zombie is Zombie and zombie.alive: zombie.die(Vector3.ZERO)
	game.waves._process(0.01)
	check(game.victory and game.over and paused and game.waves.phase == "complete", "Last enemy of round 25 ends in victory")
	check(game.campaign.cleared("forest") and game.stats._finished, "Victory records campaign completion and run statistics")
	var score: int = game.player.score
	game.waves._complete_wave()
	game.waves.start(26)
	game.waves.skip_current_wave()
	check(game.waves.wave == 25 and game.waves.queue.is_empty() and game.player.score == score, "No round 26 or duplicate rewards after victory")
	check(Lang.text(game.hud.overlay_button.text) == "Map selection", "Victory offers return to the campaign map")
	await shot("victory")
	game.hud.overlay_button.pressed.emit()
	await scene_changed
	game = current_scene
	while not game.navigation_ready: await process_frame
	check(game.hud.map_selection.visible and not game.started, "Victory returns to map selection after rebuilding the level")
	game.campaign.progress = state.progress.duplicate(true)
	game.hud.map_selection.refresh()
	await shot("selection-secured")
	game.hud.hide_map_selection()
	# The same snapshot path used by live co-op clients must retain a successful outcome.
	check(NetSession.host("CampaignHost", 24761) == OK, "Campaign co-op host opens")
	NetSession.choose_class(CharacterProfile.selected(), true)
	game.hud.primary_action()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.hud.map_selection.atlas.map_rect.position + Campaign.region("forest").anchor / Campaign.ART_SIZE * game.hud.map_selection.atlas.map_rect.size
	game.hud.map_selection.atlas._gui_input(click)
	check(game.started and NetSession.phase == "running", "Clicking the Forest polygon starts the host's selected map")
	game.waves.wave = Campaign.ROUNDS
	game.waves.completed = Campaign.ROUNDS
	game._campaign_victory()
	check(NetSession.phase == "over" and game.victory, "Host publishes campaign victory")
	var packet: Dictionary = NetSession.world.snapshot()
	check(packet.get("victory", false) and packet.get("region", "") == "forest", "Co-op snapshot includes outcome and stable region ID")
	print("CAMPAIGN_MAP_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
