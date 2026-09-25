# The top-down tower planner (T): opening, placing anywhere within reach, dragging a tower, roof slots,
# rotation, refusals and closing.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=tower_planner --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("TOWER_PLANNER_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String, detail := "") -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description + ("" if detail.is_empty() else " (" + detail + ")"))

# a valid building site between min_d and max_d metres from the player (the terrain around the fire has
# trees, the ring and the huts, so the test looks instead of guessing coordinates)
func find_site(d, player: Player, min_d: float, max_d: float, avoid: Array = []) -> Vector3:
	for step in 720:
		var angle := float(step) * 0.35
		var radius := min_d + fmod(float(step) * 1.7, max_d - min_d)
		var candidate := Map.ground_pos(player.global_position.x + cos(angle) * radius, player.global_position.z + sin(angle) * radius)
		var clear := true
		for other: Vector3 in avoid:
			if candidate.distance_to(other) < 6.0: clear = false
		if clear and d.placement_error(player, candidate, "standard", true).is_empty(): return candidate
	return Vector3.INF

# --render-planner (windowed): artifacts/tower_planner/planner.png with a ghost hovering and one tower placed
func screenshot(label: String) -> void:
	if not "--render-planner" in OS.get_cmdline_user_args(): return
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/tower_planner")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))

func run() -> void:
	if "--render-planner" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var player: Player = game.player
	var d = game.defences
	var planner: TowerPlanner = d.planner
	player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 6)
	await create_timer(0.6, false).timeout
	await physics_frame
	check(planner != null and not planner.is_open, "The planner exists and starts closed")
	planner.open()
	await process_frame
	check(planner.is_open and d.is_open and not player.active and paused, "T opens the planner, pauses the round and takes the player out of the fight")
	check(root.get_camera_3d() == planner.overview and planner.overview.projection == Camera3D.PROJECTION_ORTHOGONAL and planner.overview.rotation.x < -1.5, "The planner looks straight down from above the hut")
	check(not game.hud.visible and planner.roof_markers.size() == 6 and planner.roof_markers[0].visible, "HUD hidden, six roof markers shown")
	# the mouse hits the ground through the overview camera
	var centre := get_root().get_visible_rect().size * 0.5
	var point := planner.point_at(centre)
	check(point.is_finite() and absf(point.y - Map.ground_height(point.x, point.z)) < 3.0, "The screen centre maps onto the terrain", str(point))
	# placing far beyond the old 8 m rule
	player.add_score(2000)
	planner.select_kind("standard")
	var site := find_site(d, player, 18.0, 40.0)
	check(site.is_finite() and player.global_position.distance_to(site) > 8.0, "A valid site beyond the old 8 m reach exists", str(site))
	var before: int = d.towers.size()
	var error: String = planner.place_at(site)
	check(error.is_empty() and d.towers.size() == before + 1, "The planner places a tower far beyond arm's reach", error)
	if d.towers.size() == 0:
		print("TOWER_PLANNER_DONE checks=%d failures=%d" % [checks, failures + 1])
		quit(1)
		return
	var tower: DefenceTower = d.towers.values()[d.towers.size() - 1]
	check(tower.global_position.distance_to(site) < 0.5 and not tower.rooftop, "The tower stands where the map was clicked")
	var too_far := Map.ground_pos(Map.FIRE.x + 60, Map.FIRE.y + 30)
	error = planner.place_at(too_far)
	check(not error.is_empty() and Lang.text(error).contains("45"), "Beyond the planner's reach the site is refused", error)
	# dragging: move it, refuse an occupied spot, refuse while operated
	var moved := find_site(d, player, 18.0, 40.0, [site])
	planner.hover_point = moved
	planner._process(0.3)
	await screenshot("planner")
	error = planner.move_tower(tower, moved)
	check(error.is_empty() and tower.global_position.distance_to(moved) < 0.5, "Dragging relocates the tower for free", error)
	var score_after := player.score
	error = planner.move_tower(tower, tower.global_position + Vector3(0.2, 0, 0))
	check(error.is_empty() and player.score == score_after, "A short drag keeps the tower's own footprint out of the 'too close' rule", error)
	planner.place_at(find_site(d, player, 18.0, 40.0, [site, moved]))
	var other: DefenceTower = d.towers.values()[d.towers.size() - 1]
	error = planner.move_tower(tower, other.global_position + Vector3(1.0, 0, 0))
	check(not error.is_empty() and tower.global_position.distance_to(moved) < 0.5, "A drop onto another tower is refused and the tower stays", error)
	tower.operator_peer = 1
	error = planner.move_tower(tower, find_site(d, player, 18.0, 40.0, [site, moved, other.global_position]))
	check(not error.is_empty(), "An operated tower cannot be dragged")
	tower.operator_peer = 0
	# rotation from the planner
	planner.hover_tower = tower
	var yaw_before := tower.rotation.y
	planner.rotate_hovered(2)
	check(absf(angle_difference(tower.rotation.y, yaw_before + deg_to_rad(30.0))) < 0.01, "R turns the hovered tower by 15 degree steps")
	planner.hover_tower = null
	var ghost_before := planner.ghost_yaw
	planner.rotate_hovered(1)
	check(absf(angle_difference(planner.ghost_yaw, ghost_before + deg_to_rad(15.0))) < 0.01, "Without a hovered tower the ghost turns instead")
	# roof slots need the player at the hut
	player.global_position = Map.ground_pos(Map.FIRE.x - 30, Map.FIRE.y + 30)
	await physics_frame
	planner.place_roof(0)
	check(d.roof_tower(0) == null and Lang.text(planner.status.text).contains("forest hut"), "A roof slot from afar is refused with the reason")
	player.global_position = game.hut.center + Vector3(-5, 0, 0)
	player.global_position.y = Map.ground_height(player.global_position.x, player.global_position.z) + 0.1
	await physics_frame
	if d.roof_access(player):
		planner.place_roof(0)
		check(d.roof_tower(0) != null and d.roof_tower(0).rooftop, "At the hut a roof slot takes the turret")
		error = planner.move_tower(d.roof_tower(0), moved)
		check(not error.is_empty(), "Roof turrets cannot be dragged off the roof")
	# close restores everything
	planner.close()
	check(not planner.is_open and not d.is_open and not paused and player.active and root.get_camera_3d() == player.camera and game.hud.visible, "Closing restores camera, HUD and the round")
	check(not planner.roof_markers[0].visible and not d.ghost.visible, "Markers and ghost disappear with the planner")
	print("TOWER_PLANNER_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
