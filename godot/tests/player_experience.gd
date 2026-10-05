extends SceneTree
## Real input propagation, keyboard layouts and readable HUD geometry on both maps.
var checks := 0
var failures := 0
var game: Node3D
var director: RunDirector
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began > 600000: quit(2)
	return false
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", title)

func press(logical: Key, physical: Key, shift := false, control := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = logical
	event.physical_keycode = physical
	event.shift_pressed = shift
	event.ctrl_pressed = control
	event.echo = echo
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func run() -> void:
	for region in ["forest", "planes"]: await map_checks(region)
	print("PLAYER_EXPERIENCE_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func reset_action() -> void:
	director.person(game.player.peer_id).cooldown = 0.0
	game.player.class_combat.timers.clear()
	game.defences.input_grace = 0
	if game.get("drones"): game.drones.input_grace = 0
	root.gui_release_focus()

func map_checks(region: String) -> void:
	game = load("res://scenes/%s.tscn" % ("main" if region == "forest" else "planes")).instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if region == "planes":
		while not game.ready_for_exploration or game.preparing_survival or game.boot != null: await process_frame
	else: game._on_start(false)
	paused = false
	director = game.expedition
	director.set_process(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.active = true
	game.hud.hide_overlay()
	game.player.class_combat.configure({"id":"gunslinger", "level":1, "choices":[-1,-1,-1,-1,-1,-1]})
	await create_timer(0.5).timeout
	reset_action()
	check(director.can_use_world_action(), region+": gameplay accepts class actions")
	await press(KEY_M, KEY_M)
	check(game.hud.minimap.expanded, "M expands the map during gameplay")
	await press(KEY_M, KEY_M)
	check(not game.hud.minimap.expanded, "A second M restores the compact map")
	await press(KEY_Z, KEY_Y)
	check(game.player.class_combat.active("exp_focus") and director.person(game.player.peer_id).cooldown > director.elapsed, region+": printed Z on QWERTZ triggers the real class action")
	check(not director.action_status(game.player.peer_id).is_empty(), "An activated class action has duration/cooldown feedback")
	reset_action()
	await press(KEY_Y, KEY_Z)
	check(not game.player.class_combat.active("exp_focus"), "Printed Y on QWERTZ never triggers the Z class action")
	reset_action()
	await press(KEY_Z, KEY_Z)
	check(game.player.class_combat.active("exp_focus"), "Printed Z on QWERTY triggers the same class action")
	reset_action()
	await press(KEY_Z, KEY_Y, true)
	check(game.player.class_combat.active("exp_focus"), "Sprint modifier does not prevent the class action")
	reset_action()
	await press(KEY_Z, KEY_Y, false, true)
	check(not game.player.class_combat.active("exp_focus"), "Ctrl+Z is not treated as a gameplay action")
	await press(KEY_Z, KEY_Y, false, false, true)
	check(not game.player.class_combat.active("exp_focus"), "Held-key repeats cannot trigger an action")
	game.defences.placing = true
	await press(KEY_Z, KEY_Y)
	check(not game.player.class_combat.active("exp_focus"), "Placement mode blocks class actions")
	game.defences.placing = false
	game.player.controlling_drone = true
	await press(KEY_Z, KEY_Y)
	check(not game.player.class_combat.active("exp_focus"), "Drone mode blocks class actions")
	game.player.controlling_drone = false
	game.player.downed = true
	await press(KEY_Z, KEY_Y)
	check(not game.player.class_combat.active("exp_focus"), "Downed actors cannot activate class actions")
	game.player.downed = false
	reset_action()
	await press(KEY_K, KEY_K)
	check(director.book.is_open and paused and not game.player.active, "K opens the real fieldbook and pauses solo play")
	await press(KEY_M, KEY_M)
	check(not game.hud.minimap.expanded, "M does not change the minimap behind the fieldbook")
	await press(KEY_Z, KEY_Y)
	check(not game.player.class_combat.active("exp_focus"), "Fieldbook keyboard input cannot activate class actions")
	await press(KEY_ESCAPE, KEY_ESCAPE)
	check(not director.book.is_open and not paused and game.player.active, "Escape restores gameplay from the fieldbook")
	game._pause()
	await press(KEY_M, KEY_M)
	check(not game.hud.minimap.expanded, "M does not change the minimap behind the pause menu")
	check(game.hud.fieldbook_button.visible, "Pause menu exposes the fieldbook without a permanent HUD button")
	game.hud.fieldbook_button.pressed.emit()
	check(director.book.is_open, "Pause-menu button opens the fieldbook")
	await press(KEY_ESCAPE, KEY_ESCAPE)
	check(paused and game.hud.overlay.visible and not game.player.active, "Closing the fieldbook returns to the existing pause menu")
	game.hud.hide_overlay()
	paused = false
	game.player.active = true
	reset_action()
	await hud_geometry(region)
	game.queue_free()
	await process_frame
	await process_frame
	current_scene = null

func hud_geometry(region: String) -> void:
	var previous_size := root.content_scale_size
	for resolution in [Vector2i(1600,900), Vector2i(1280,720)]:
		root.content_scale_size = resolution
		for text in ["Pistol", "Titanbreaker .50 · Grenades 12 · LMB light / RMB heavy"]:
			game.hud.set_ammo(12,72,Lang.t(text))
			game.hud.set_reload(0,1)
			game.hud.set_charge("",0)
			await layout_frames()
			var ammo: Rect2 = game.hud.ammo_panel.get_global_rect()
			check(root.get_visible_rect().encloses(ammo), "Weapon panel fits %s (%s)" % [resolution,text])
			check(ammo.end.y >= root.get_visible_rect().end.y-20, "Weapon panel sits at the bottom edge")
			check(not ammo.intersects(game.quickbar.bar.get_global_rect()), "Weapon information does not overlap quick slots")
			check(not ammo.intersects(game.hud.minimap.get_global_rect()), "Minimap and weapon information stay separated")
			check(ammo.position.x >= root.get_visible_rect().size.x-320, "Pistol/weapon silhouette retains the clear central viewing area")
			check(not game.hud.reload_label.visible, "Idle weapons have no empty reload line")
		game.hud.set_reload(1.0,2.0)
		game.hud.set_charge(Lang.t("Cooling"),0.5)
		await layout_frames()
		check(not game.hud.ammo_panel.get_global_rect().intersects(game.hud.minimap.get_global_rect()), "Reload and cooling gauges do not overlap the minimap")
		game.hud.set_reload(0,1)
		game.hud.set_charge("",0)
		game.weapons.update_hud()
		if "--expedition-captures" in OS.get_cmdline_user_args():
			await create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			var folder := "res://../artifacts/player-experience/"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
			root.get_texture().get_image().save_png(folder+region+"-hud-"+str(resolution.y)+"-"+Lang.current+".png")
		game._pause()
		await layout_frames()
		check(root.get_visible_rect().encloses(game.hud._card.get_global_rect()), "Entire pause menu fits %s" % resolution)
		check(game.hud.fieldbook_button.is_visible_in_tree(), "Fieldbook remains reachable from the visible pause menu")
		check(not game.quickbar.bar.visible, "Real pause menu hides the quick bar")
		if "--expedition-captures" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../artifacts/player-experience/"+region+"-pause-"+str(resolution.y)+"-"+Lang.current+".png")
		if region == "planes": game.set_menu(false)
		else: game._on_start(false)
	root.content_scale_size = previous_size

func layout_frames() -> void:
	for i in 5: await process_frame
