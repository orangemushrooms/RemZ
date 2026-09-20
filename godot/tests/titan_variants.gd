extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.weapons.set_process(false)
	game.player.set_physics_process(false)
	game.player.max_hp = 1000
	game.player.hp = 1000
	game.player.global_position = Map.ground_pos(0, 90)
	check(Waves.lesser_titan_count(7) == 0 and Waves.lesser_titan_count(8) == 1 and Waves.lesser_titan_count(24) == 3, "Smaller titan groups scale from wave eight to three per wave")
	var seen := {}
	for n in range(1, 31):
		var plan: Array = game.waves.plan(n)
		var small := 0
		for entry in plan:
			if Zombie.is_titan_kind(entry.type) and entry.type != "titan":
				small += 1
				seen[entry.type] = true
				check(not entry.get("forest", false) and entry.point.y > 100, "Variant enters through an open field")
		check(small == Waves.lesser_titan_count(n) and plan.size() == game.waves.preview_count(n), "Wave %d includes variants in exact preview" % n)
	check(seen.size() == 3, "Wave schedule uses all three new variants")
	var variants: Array[Titan] = []
	for kind in ["titan_hunter", "titan_siege", "titan_ash", "titan"]:
		var index := variants.size()
		game.spawn_zombie(kind, Vector2(-24 + index * 16, 120), 1, "east")
		var titan: Titan = game.zombies_root.get_children().back()
		titan.set_physics_process(false)
		titan.agent.avoidance_enabled = false
		variants.append(titan)
		check(titan.anim.has_animation("walk") and titan.anim.has_animation("attack") and titan.anim.has_animation("death"), kind + " has complete animations")
		check(not titan._hitboxes.is_empty() and titan.height == Zombie.TYPES[kind].height, kind + " retains animated hitboxes at its own scale")
		game.player.global_position = Map.ground_pos(20, 105)
		titan.strike_point = game.player.global_position
		game.player.hp = 1000
		titan.resolve_strike()
		check(is_equal_approx(game.player.hp, 1000 - float(titan.type.damage)), kind + " applies its actual strike damage")
		game.player.global_position += Vector3(titan.blast_radius() + 1, 0, 0)
		game.player.hp = 1000
		titan.resolve_strike()
		check(game.player.hp == 1000, kind + " respects its individual blast radius")
		titan.begin_strike(titan.global_position + Vector3(0, 0, -3))
		check(is_equal_approx(titan.strike_time, titan.windup()) and titan.warning.visible, kind + " advertises its own windup and warning")
	check(not game.waves._try_spawn({"type": "titan_hunter", "lane": "east"}), "Four active titans prevent additional titan spawns")
	check(variants[0].blast_radius() < variants[1].blast_radius() and variants[1].blast_radius() < variants[2].blast_radius(), "Variants have genuinely different attack footprints")
	check(variants[0].windup() < variants[1].windup() and variants[1].windup() < variants[2].windup(), "Faster attacks retain shorter but visible warnings")
	var count: int = game.progression.team.titans
	variants[0].damage(100000, Vector3.ZERO)
	check(game.progression.team.titans == count + 1, "New variants count toward titan quests")
	var proxy := Titan.new()
	proxy.replica = true
	proxy.setup("titan_siege", game.player, game.barricades, 1, Callable())
	game.add_child(proxy)
	proxy.set_physics_process(false)
	proxy.apply_boss_state(variants[1].boss_state(), true)
	check(proxy.strike_point == variants[1].strike_point and proxy.blast_radius() == 6 and proxy.height == 14, "Replica reconstructs variant telegraph and scale")
	proxy.queue_free()
	if "--render-titan-variants" in OS.get_cmdline_user_args():
		game.spawn_zombie("titan_hunter", Vector2(-24, 120), 1, "east")
		var replacement: Titan = game.zombies_root.get_children().back()
		replacement.set_physics_process(false)
		replacement.agent.avoidance_enabled = false
		game.player.global_position = Map.ground_pos(0, 63) + Vector3.UP * 3
		game.player.camera.look_at(Map.ground_pos(0, 120) + Vector3.UP * 10)
		game.achievements._toast.hide()
		game.hud.message("", 0)
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/titan-variants"))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/titan-variants/lineup.png"))
	print("TITAN_VARIANTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
