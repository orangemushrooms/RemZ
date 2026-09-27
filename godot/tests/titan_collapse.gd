extends SceneTree
var checks := 0
var failures := 0
var rendered := false
var game: Node

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func above(titan: Titan, bone: String) -> float:
	var point := titan.skeleton.to_global(titan.skeleton.get_bone_global_pose(titan.skeleton.find_bone(bone)).origin)
	return point.y - Map.ground_height(point.x, point.z)

func shot(name: String) -> void:
	if not rendered: return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/titan-collapse/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + name + ".png")

func run() -> void:
	rendered = "--render-collapse" in OS.get_cmdline_user_args()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.hud.hide()
	game.achievements.hide()
	game.day_night.clock_seconds = 13 * 3600
	game.day_night.advance(1)
	game.day_night.set_process(false)
	for kind: String in ["titan", "titan_hunter", "titan_siege", "titan_ash", "titan_elder"]:
		game.spawn_zombie(kind, Vector2(13, 106), 1, "east")
		var titan: Titan = game.zombies_root.get_children().back()
		titan.set_physics_process(false)
		titan.agent.avoidance_enabled = false
		titan.lost = Titan.LOST_ARM | Titan.LOST_LEG
		titan._apply_lost(Titan.LOST_ARM, Vector3.UP)
		titan._apply_lost(Titan.LOST_LEG, Vector3.UP)
		game.player.global_position = Map.ground_pos(13 + titan.height * 0.8, 106 - titan.height * 1.15) + Vector3.UP * titan.height * 0.35
		game.player.camera.look_at(titan.global_position + Vector3.UP * titan.height * 0.18)
		await create_timer(0.7).timeout
		# Include a kill during the remaining arm's sweep.
		if kind == "titan_siege":
			titan.play("attack")
			await create_timer(0.4).timeout
		var initial := above(titan, "Hips")
		await shot(kind + "-crawl")
		titan.die(Vector3.ZERO)
		var peak := initial
		var t := 0.0
		var middle := false
		while t < 2.8:
			await process_frame
			t += root.get_process_delta_time()
			peak = maxf(peak, above(titan, "Hips"))
			if not middle and t > 0.85:
				middle = true
				await shot(kind + "-fall")
		await shot(kind + "-dead")
		check(peak < titan.height * 0.4, "%s falls without standing up (hips %.2f -> peak %.2f)" % [kind, initial, peak])
		check(above(titan, "Hips") < titan.height * 0.16 and above(titan, "Head") < titan.height * 0.16, "%s finishes lying down (hips %.2f head %.2f)" % [kind, above(titan, "Hips"), above(titan, "Head")])
		check(not titan.anim.is_playing() and titan.anim.get_animation("crawl_death").loop_mode == Animation.LOOP_NONE, kind + " holds its final corpse pose")
		titan.queue_free()
		await process_frame
	print("TITAN_COLLAPSE_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
