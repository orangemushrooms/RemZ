extends SceneTree

var checks := 0
var failures := 0
var game: Node
var capture := false
var started_at := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 180000:
		push_error("BARRICADES_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	capture = "--render-barricades" in OS.get_cmdline_user_args()
	if capture:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready:
		await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var player: Player = game.player
	var menu: BarricadeMenu = game.barricade_menu
	var bar: Barricade = game.barricades[0]
	var normal := Vector3(bar.normal2.x, 0, bar.normal2.y)
	player.global_position = bar.center + normal * 4.0
	player.global_position.y = Map.ground_height(player.position.x, player.position.z) + 0.1
	await physics_frame
	await physics_frame
	check(bar.level == 0 and bar.visual.get_child_count() == 0, "Unbuilt line has no physical models")
	check(not bar.purchase(player, "build") and player.score == 0 and bar.level == 0, "Unaffordable line creates nothing and charges nothing")
	player.add_score(200)
	var planner_key := InputEventKey.new()
	planner_key.pressed = true
	planner_key.physical_keycode = KEY_V
	Input.parse_input_event(planner_key)
	await process_frame
	check(menu.is_open and menu.selected == bar, "V opens the nearest defence line")
	check(menu.is_open and paused and not player.active, "Planner pauses combat")
	check(root.get_camera_3d() == menu.overview and not game.hud.visible and not game.weapons.viewmodel.visible, "Planner frames the whole line and clears the combat HUD")
	check(bar.preview.visible and bar.preview.get_child_count() == int(bar.slot.segments), "Red preview covers every segment")
	check(game.weapons.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Planner stops the hidden weapon viewport")
	check(bar.footprint.get_child_count() == 1, "Terrain markers share one batched draw")
	check(not menu.primary.disabled and not menu.repair_button.visible, "New line offers one complete purchase")
	await screenshot("01-whole-line-plan")
	var start_score := player.score
	menu.primary.pressed.emit()
	await process_frame
	check(bar.level == 1 and player.score == start_score - 50, "One click builds the complete line for 50 total points")
	check(bar.visual.get_child_count() == int(bar.slot.segments), "Every planned model is built together")
	check(not bar.preview.visible and bar.footprint.visible, "Built line replaces the ghost and retains its green outline")
	for shape: CollisionShape3D in bar.body.get_children():
		check(not shape.disabled, "Built segment collision is active")
	check(menu.status.text.contains("Gesamte Linie gebaut"), "Build confirmation stays in the planner")
	await screenshot("02-built-line")
	# Raycast across the joins as well as both ends: no invisible opening on sloped ground.
	for along in [-bar.half_len + 0.2, -0.05, 0.0, 0.05, bar.half_len - 0.2]:
		var point := bar.point_at(along) + Vector3.UP * 0.7
		var query := PhysicsRayQueryParameters3D.create(point - normal * 2, point + normal * 2, 8)
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == bar.body, "Physical line covers position %.2f m" % along)
	var first: Node3D = bar.visual.get_child(0)
	var second: Node3D = bar.visual.get_child(1)
	var a := Barricade._bounds(first)
	var b := Barricade._bounds(second)
	check(a.end.x >= b.position.x - 0.05, "Adjacent visual segments meet without a gap")
	var instance_id := first.get_instance_id()
	bar.damage(70)
	menu._last_message = ""
	menu._refresh()
	await screenshot("03-damaged-line")
	menu._purchase("repair")
	check(bar.hp == 150 and player.score == start_score - 75, "Repair restores the whole line for exactly 25 points")
	check(bar.visual.get_child(0).get_instance_id() == instance_id, "Damage and repair reuse the existing geometry")
	menu._purchase("repair")
	check(player.score == start_score - 75, "Repeated repair cannot waste points")
	bar.damage(30)
	menu._purchase("build")
	check(bar.level == 2 and bar.hp == 300 and player.score == start_score - 125, "Upgrade restores and strengthens all segments together")
	menu._purchase("build")
	check(bar.level == 3 and bar.hp == 450 and player.score == start_score - 175, "Final upgrade reaches 450 HP at the advertised cost")
	menu._purchase("build")
	check(bar.level == 3 and player.score == start_score - 175, "Maximum level cannot be purchased twice")
	await screenshot("04-reinforced-line")
	menu.site_buttons[3].pressed.emit()
	check(menu.selected == game.barricades[3], "Site buttons select their own complete line")
	check(menu.primary.disabled and menu.status.text.contains("entfernt"), "Remote preview cannot purchase beyond build reach")
	await screenshot("05-distant-site")
	menu.select_site(bar)
	var original_position := player.global_position
	var original_basis := player.global_basis
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(event)
	await process_frame
	check(not menu.is_open and not paused and player.active, "Escape closes construction and resumes combat")
	check(root.get_camera_3d() == player.camera and game.hud.visible and game.weapons.viewmodel.visible, "Closing restores the player camera, hands and HUD")
	check(game.weapons.viewmodel.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Returning resumes weapon rendering")
	check(player.global_position == original_position and player.global_basis.is_equal_approx(original_basis), "Planning never teleports or rotates the player")
	bar.damage(10000)
	await process_frame
	for shape: CollisionShape3D in bar.body.get_children():
		check(shape.disabled, "Destruction removes every segment collider")
	player.add_score(200)
	player.global_position = bar.center + Vector3.UP * 0.1
	await physics_frame
	await physics_frame
	menu.open(bar)
	check(menu.primary.disabled and menu.status.text.contains("belegt"), "Player inside the line blocks construction")
	var score_before := player.score
	menu._purchase("build")
	check(bar.level == 0 and player.score == score_before, "Blocked build leaves points and all segments untouched")
	await screenshot("06-occupied-line")
	menu.close()
	player.global_position = original_position
	# Use a physics body on the enemy layer so the test isolates occupancy from AI movement.
	var enemy := StaticBody3D.new()
	enemy.collision_layer = 2
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	enemy.add_child(collision)
	game.add_child(enemy)
	enemy.global_position = bar.center + Vector3.UP * 0.9
	await physics_frame
	await physics_frame
	check(bar.action_error(player, "build").contains("belegt"), "Enemy occupying any segment blocks construction")
	enemy.queue_free()
	await physics_frame
	await physics_frame
	var endpoint := bar.point_at(bar.half_len - 0.1)
	player.global_position = endpoint + normal * 2.0
	player.global_position.y = Map.ground_height(player.position.x, player.position.z) + 0.1
	await physics_frame
	await physics_frame
	check(bar.distance_to_line(player.global_position) < 2.5, "Interaction uses the entire line, including its ends")
	check(bar.purchase(player, "build"), "Destroyed line can be rebuilt from an endpoint")
	game.skills.open()
	menu.open(bar)
	check(game.skills.is_open and not menu.is_open and paused, "Construction cannot open over another modal menu")
	game.skills.close()
	game.inventory.open()
	Input.parse_input_event(event)
	await process_frame
	check(not game.inventory.is_open and player.active and not paused, "Escape also closes inventory without leaving a stale modal")
	for other: Barricade in game.barricades:
		player.global_position = other.center + Vector3(other.normal2.x, 0, other.normal2.y) * 4.0
		player.global_position.y = Map.ground_height(player.position.x, player.position.z) + 0.1
		await physics_frame
		await physics_frame
		menu.open(other)
		await screenshot("site-" + str(other.slot.id))
		menu.close()
	if capture:
		root.size = Vector2i(1280, 720)
		await process_frame
		menu.open(bar)
		await process_frame
		check(menu.primary.get_global_rect().end.y < root.get_visible_rect().end.y, "Build action remains on screen at 1280x720")
		await screenshot("07-menu-1280x720")
		menu.close()
	print("BARRICADES_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func screenshot(label: String) -> void:
	if not capture:
		return
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/barricades")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "Saved " + label)
