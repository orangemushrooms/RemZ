extends SceneTree
## Loaded externally by Godot with --main-pack; game resources come from the release PCK.
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("test")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began > 300000: quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func press(logical: Key, physical: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = logical
	event.physical_keycode = physical
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func test() -> void:
	var region := "forest"
	for flag in OS.get_cmdline_user_args():
		if flag.begins_with("--test-region="): region = flag.trim_prefix("--test-region=")
	check(not FileAccess.file_exists("res://tests/run.gd"), "Production pack excludes development test suites")
	var game = load("res://scenes/planes.tscn" if region == "planes" else "res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if region == "planes":
		while not game.ready_for_exploration or game.preparing_survival: await process_frame
	else: game._on_start(false)
	paused = false
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.expedition.set_process(false)
	var run = game.expedition
	check(run.enabled and run.book != null and run.structures != null, "Packed scene installs all expedition systems")
	check(run.configure({"seed": 72531, "region": region}), "Packed run can be configured before wave one")
	check(game.waves.plan(8) == game.waves.plan(8) and not game.waves.plan(8).is_empty(), "Packed wave plans are populated and deterministic")
	game.player.class_combat.configure({"id":"gunslinger", "level":1, "choices":[-1,-1,-1,-1,-1,-1]})
	game.defences.input_grace = 0
	root.gui_release_focus()
	for i in 5: await process_frame
	check(not run.book.status.visible and not run.book.launch.visible, "Packed start has no permanent expedition shortcut banner")
	await press(KEY_Z, KEY_Y)
	check(game.player.class_combat.active("exp_focus"), "Packed QWERTZ Z activates the actual class action")
	var ammo: Rect2 = game.hud.ammo_panel.get_global_rect()
	check(ammo.end.y >= root.get_visible_rect().end.y-20 and not ammo.intersects(game.hud.minimap.get_global_rect()), "Packed weapon panel is at the bottom without covering the map")
	game._pause()
	for i in 3: await process_frame
	check(game.hud.fieldbook_button.visible and not game.quickbar.bar.visible, "Packed pause menu offers the fieldbook and hides quick slots")
	await press(KEY_M, KEY_M)
	check(not game.hud.minimap.expanded, "Packed pause menu blocks hidden map input")
	game.hud.fieldbook_button.pressed.emit()
	check(run.book.is_open and paused, "Packed pause-menu button opens the fieldbook")
	await press(KEY_ESCAPE, KEY_ESCAPE)
	check(not run.book.is_open and paused and game.hud.overlay.visible, "Packed Escape returns to the paused menu")
	if region == "planes": game.set_menu(false)
	else: game._on_start(false)
	game.waves.wave = 3
	game.waves.completed = 3
	game.waves.phase = "idle"
	run.wave_cleared(3)
	check(run.person(1).offers.size() == 3, "Packed run offers three personal augments")
	run.book.open()
	check(paused and run.book.panel.visible, "Packed fieldbook opens and pauses solo play")
	run.book.close()
	game.player.global_position = run.camp()+Vector3(2, 0.3, 2)
	game.player.score = 389
	run.checkpoints.override_path = "user://packed_%s.save" % region
	check(run.checkpoints.save_run() == "Checkpoint saved.", "Packed game writes a validated checkpoint")
	game.player.score = 1
	check(run.checkpoints.load_run() == "Expedition continued." and game.player.score == 389, "Packed game restores its checkpoint")
	for site in run.sites:
		var visual: Node3D = run._markers[site.id]
		check(not visual.has_node("Caption") and not visual.find_children("Model_*", "Node3D", true, false).is_empty(), "Packed discovery site uses textured assets: "+site.id)
		check(run.map_points().any(func(point): return point.at == site.at) == (site.kind == "outpost"), "Packed minimap discovery visibility: "+site.id)
	var cache: Dictionary = run.sites.filter(func(site): return site.kind == "record")[0]
	await physics_frame
	var target: Vector3 = cache.at+Vector3.UP*0.3
	var ray := PhysicsRayQueryParameters3D.create(target+Vector3(0, 0, 2), target, 8)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and run._markers[cache.id].is_ancestor_of(hit.collider), "Packed crate has physical collision")
	cache.done = true
	run._sync_markers()
	await physics_frame
	hit = game.get_world_3d().direct_space_state.intersect_ray(ray)
	check(hit.is_empty() or not run._markers[cache.id].is_ancestor_of(hit.collider), "Packed collected crate leaves no invisible obstacle")
	if region == "planes":
		var site: Dictionary = run.sites[0]
		site.timer = 35.0
		site.pending = 0
		game.player.global_position = site.at+Vector3.UP*0.2
		run._tick = 0.25
		run._process(1.0)
		run.book._refresh_t = 0
		run.book._process(0.3)
		check(site.timer == 34.0 and run.book.status.visible and Lang.text(run.book.status.text).contains("34"), "Packed German HUD counts down the occupied outpost")
		site.timer = 0.0
	check(run.begin_finale() and game.waves.phase == "finale", "Packed game installs its region finale")
	if region == "planes":
		game.stop_survival()
		var records: Array = game.stats.table.duplicate(true)
		game.player.revive_protection = 0
		game.player.damage(1000000)
		game.player._bleed_out()
		check(game.waves == null and game.over and game.menu.visible, "Packed exploration death opens recovery after stopping survival")
		check(game.stats.table == records and not game.stats._finished, "Packed exploration recovery does not save a spurious survival record")
		game.hud.overlay_button.pressed.emit()
		check(game.player.alive and game.player.active and not game.over and not paused, "Packed exploration recovery restores playable controls")
	else:
		for asset in ["zombie_earthworm", "zombie_earthworm_ancient"]:
			var model: Node3D = load("res://assets/models/%s.glb" % asset).instantiate()
			var animation := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var attack := animation.get_animation("attack")
			var recovery := animation.get_animation("recovery")
			var seamless := true
			for track in attack.get_track_count():
				if attack.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
				var next := recovery.find_track(attack.track_get_path(track), Animation.TYPE_ROTATION_3D)
				seamless = seamless and next >= 0
				if next >= 0: seamless = seamless and attack.rotation_track_interpolate(track, attack.length).is_equal_approx(recovery.rotation_track_interpolate(next, 0))
			check(seamless, "Packed worm attack/recovery transition is seamless: " + asset)
			model.free()
	paused = false
	game.queue_free()
	await process_frame
	await physics_frame
	print("EXPEDITION_PACK_DONE region=%s checks=%d failures=%d" % [region, checks, failures])
	quit(1 if failures else 0)
