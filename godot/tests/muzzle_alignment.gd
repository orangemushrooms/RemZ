extends SceneTree

var checks := 0
var failures := 0
var game: Node
var capture := false

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	capture = "--render-muzzle" in OS.get_cmdline_user_args()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.day_night.set_time_hours(12)
	game.player.global_position = Map.ground_pos(60,112) + Vector3.UP * 0.3
	game.player.rotation.y = 0
	game.player.pitch = 0
	game.player.head.rotation.x = 0
	var w: Weapons = game.weapons
	# The two heavies are in here because their muzzles are the hardest to measure: a six barrel
	# cluster and a wide emitter mouth.
	for weapon in ["pistol", "smg", "ak47", "minigun", "graviton_cannon"]:
		w.unlock(weapon)
		w.set_weapon(weapon)
		for aimed in [false, true]:
			if aimed: Input.action_press("aim")
			else: Input.action_release("aim")
			for i in 60: w._process(1.0/60.0)
			var mode := "ads" if aimed else "hip"
			var local_tip := w.muzzle_transform().origin
			var visible_pixel := w.viewmodel.camera.unproject_position(w.viewmodel.camera.to_global(local_tip)) / Vector2(w.viewmodel.viewport.size)
			var world_pixel := w.camera.unproject_position(w.visual_muzzle_world()) / w.camera.get_viewport().get_visible_rect().size
			check(visible_pixel.distance_to(world_pixel) < 0.00001, weapon + " " + mode + " trail and visible muzzle share the same screen pixel")
			var data: Dictionary = game.progression.rare_market.data(game.player.peer_id)
			data.ammo.frost = 20
			data.mode = "frost"
			w.cur().cooldown = 0
			w.try_fire()
			var tracer = get_nodes_in_group("elemental_tracer").back()
			var end: Vector3 = tracer.endpoint
			for i in 3:
				w._process(1.0/120.0)
				tracer._process(1.0/120.0)
			check(tracer.start.distance_to(w.visual_muzzle_world()) < 0.0001, weapon + " " + mode + " real frost shot stays attached during recoil")
			check(tracer.endpoint == end, weapon + " " + mode + " attachment never moves the authoritative impact")
			if capture and weapon == "pistol":
				await RenderingServer.frame_post_draw
				var folder := ProjectSettings.globalize_path("res://../artifacts/muzzle-alignment")
				DirAccess.make_dir_recursive_absolute(folder)
				root.get_texture().get_image().save_png(folder + "/pistol-" + mode + ".png")
			for node in get_nodes_in_group("elemental_tracer"): node.queue_free()
			await process_frame
	Input.action_release("aim")
	print("MUZZLE_ALIGNMENT_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
