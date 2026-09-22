extends SceneTree

var game: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func shot(id: String) -> void:
	if "--render-scope" not in OS.get_cmdline_user_args(): return
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/sniper-scope/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + id + ".png")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	p.set_physics_process(false)
	w.set_process(false)
	game.achievements.hide()
	game.day_night.set_time_hours(10.0)
	# Every scoped weapon in the catalogue, at its own magnification - a new optic is covered the
	# moment it carries "scope_zoom" in Weapons.DEFS.
	var scoped_weapons: Array = []
	for id in Weapons.ORDER:
		if Weapons.DEFS[id].has("scope_zoom"): scoped_weapons.append(id)
	check(scoped_weapons.size() >= 2, "Catalogue offers scoped weapons: " + ", ".join(PackedStringArray(scoped_weapons)))
	for weapon in scoped_weapons:
		p.active = true
		w.unlock(weapon)
		w.set_weapon(weapon)
		p.global_position = Map.ground_pos(0, -23) + Vector3.UP * 0.2
		p.camera.look_at(Map.ground_pos(0, 0) + Vector3.UP * 1.6)
		w._handle_weapon_input(1.0)
		var centre := p.camera.global_position - p.camera.global_basis.z * 40.0
		var edge := centre + p.camera.global_basis.x * 3.0
		var hip_width := p.camera.unproject_position(edge).distance_to(p.camera.unproject_position(centre))
		check(is_equal_approx(p.camera.fov, 75.0) and not w.viewmodel.scope.visible, "Hip fire uses normal world view")
		await shot(weapon + "-hip")
		Input.action_press("aim")
		w._handle_weapon_input(1.0)
		var aimed_width := p.camera.unproject_position(edge).distance_to(p.camera.unproject_position(centre))
		var zoom := float(Weapons.DEFS[weapon].scope_zoom)
		check(is_equal_approx(aimed_width / hip_width, zoom), "%s magnifies actual projected world geometry by %.1fx" % [weapon, zoom])
		check(w.viewmodel.scope.visible and not w.viewmodel.image.visible, "Scope lens replaces obstructing weapon model")
		check(str(w.viewmodel.scope.style) == str(Weapons.DEFS[weapon].get("scope_style", "mil")), weapon + " draws its own reticle style")
		check(not game.hud.crosshair_parts[0].visible, "Normal crosshair is hidden behind scope reticle")
		await shot(weapon + "-scope")
		Input.action_release("aim")
		w._handle_weapon_input(1.0)
		check(is_equal_approx(p.camera.fov, 75.0) and not w.viewmodel.scope.visible and w.viewmodel.image.visible, "Releasing aim restores world view and weapon")
		Input.action_press("aim")
		w._handle_weapon_input(1.0)
		w.cur().ammo = 0
		w.reload()
		w._handle_weapon_input(1.0)
		check(not w.viewmodel.scope.visible and is_equal_approx(p.camera.fov, 75.0), "Reload exits scope despite held aim")
		w.cur().reloading = 0.0
		w._handle_weapon_input(1.0)
		check(w.viewmodel.scope.visible, "Held aim returns to scope after reload")
		w.set_weapon("pistol")
		check(not w.viewmodel.scope.visible and is_equal_approx(p.camera.fov, 75.0), "Switching weapon immediately clears scope and zoom")
		w._handle_weapon_input(1.0)
		check(is_equal_approx(p.camera.fov, 52.0) and not w.viewmodel.scope.visible, "Normal pistol aiming retains its own field of view")
		w.set_weapon(weapon)
		w._handle_weapon_input(1.0)
		p.active = false
		w._process(0.1)
		check(not w.viewmodel.scope.visible and is_equal_approx(p.camera.fov, 75.0), "Inactive player clears scope")
		Input.action_release("aim")
	print("SNIPER_SCOPE_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
