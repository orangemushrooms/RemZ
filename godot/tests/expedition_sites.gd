extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", title)

func run() -> void:
	var game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready or not game.ready_for_exploration or game.preparing_survival or game.boot != null: await process_frame
	paused = false
	game.started = true
	game.player.active = true
	game.player.set_physics_process(false)
	game.waves.set_process(false)
	game.waves.timer = 100
	game.hud.hide_overlay()
	var director: RunDirector = game.expedition
	director.set_process(false)
	check(director.sites.size() == 8, "Planes discovery sites exist")
	for site in director.sites:
		var visual: Node3D = director._markers[site.id]
		check(not visual.has_node("Caption"), "No floating billboard: "+site.id)
		check(visual.find_children("Model_*", "Node3D", true, false).size() > 0, "Textured mesh present: "+site.id)
		var marked := director.map_points().any(func(point): return point.at == site.at)
		check(marked == (site.kind == "outpost"), "Only outposts appear on minimap: "+site.id)
	var site: Dictionary = director.sites[0]
	game.player.global_position = site.at+Vector3.UP*0.2
	check(director.transact(1, "interact", [site.id]) == "Hold the outpost for 35 seconds.", "Outpost activates")
	site.pending = 0
	check(Lang.text(director.objective_status()).contains("35"), "Initial countdown is visible")
	director._tick = 0.25
	director._process(1.0)
	check(is_equal_approx(float(site.timer), 34.0), "One occupied second reduces timer")
	director.book._refresh_t = 0
	director.book._process(0.3)
	check(director.book.status.visible and Lang.text(director.book.status.text).contains("34"), "HUD displays updated countdown")
	game.player.global_position = site.at+Vector3(30, 1, 0)
	director._tick = 0.25
	director._process(1.0)
	check(is_equal_approx(float(site.timer), 34.0), "Countdown pauses outside capture area")
	check(director.objective_status() == Lang.t("Return to outpost: %d s remaining | Health %d", [34, 160]), "Paused countdown explains return requirement")
	site.timer = 0.1
	check(director.objective_status().contains(Lang.t("Outpost: clear remaining attackers | Health %d", [160])), "Enemy clearance does not display a stuck one-second timer")
	site.timer = 12
	var state := director.snapshot()
	director.apply_snapshot(state)
	check(Lang.text(director.objective_status()).contains("12"), "Snapshot supplies current countdown")
	check(director.map_points().size() == 2, "Snapshot does not restore hidden discovery pins")
	game.player.global_position = director.sites[0].at+Vector3.UP*0.2
	director.sites[0].timer = 0.1
	director.sites[0].pending = 0
	director._tick = 0.25
	director._process(1.0)
	check(director.sites[0].done, "Outpost completes when countdown and attackers are finished")
	check(director.objective_status().is_empty(), "Completed outpost clears countdown")
	var cache: Dictionary = director.sites[2]
	cache.done = true
	director._sync_markers()
	check(not director._markers[cache.id].visible, "Collected cache disappears")
	for body in director._markers[cache.id].find_children("*", "StaticBody3D", true, false):
		check(body.collision_layer == 0, "Collected cache leaves no invisible collider")
	cache.done = false
	director._sync_markers()
	var plants: Array = game.cornfield._site_plants
	check(not plants.is_empty(), "Crops around discovery props are flattened")
	var plant_count := plants.size()
	game.cornfield.clear_discovery_sites(director.sites)
	check(game.cornfield._site_plants.size() == plant_count, "Repeated snapshots do not accumulate crop changes")
	if not plants.is_empty():
		var plant: Array = plants[0]
		check(plant[0].get_instance_transform(plant[1]).basis.y.length() < plant[2].basis.y.length()*0.2, "Flattened crops expose props")
		game.cornfield.clear_discovery_sites([])
		check(plant[0].get_instance_transform(plant[1]).is_equal_approx(plant[2]), "Changed site layout restores previous crops")
	game.cornfield.clear_discovery_sites(director.sites)
	if "--expedition-captures" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.make_current()
		for index in [0, 2, 5]:
			var target: Vector3 = director.sites[index].at
			game.player.global_position = target+Vector3(0, 0.2, 2.5)
			if index == 0:
				director.sites[0].done = false
				director.sites[0].timer = 24.0
			else: director.sites[0].done = true
			camera.global_position = target+Vector3(4, 2.8, 5)
			camera.look_at(target+Vector3.UP*0.8)
			await create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			var folder := "res://../artifacts/expansion-tests/screenshots/"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
			check(root.get_texture().get_image().save_png(folder+"site-%d-%s.png" % [index, Lang.current]) == OK, "Rendered site screenshot")
	print("EXPEDITION_SITES_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
