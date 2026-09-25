extends SceneTree

var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var game: Node3D

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000:
		push_error("EARTHWORM_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	else: print("PASS: ", label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.weapons.set_process(false)
	game.player.set_physics_process(false)
	game.player.global_position = Map.ground_pos(10, 90)
	game.player.max_hp = 10000
	game.player.hp = 10000
	var schedule_ok := true
	var report: Array = []
	for n in range(1, 121):
		var plan: Array = game.waves.plan(n)
		var worms := 0
		var titans := 0
		for entry in plan:
			if Zombie.is_worm_kind(entry.type):
				worms += 1
				schedule_ok = schedule_ok and entry.point.y > 100 and not entry.get("forest", false)
			if Zombie.is_titan_kind(entry.type): titans += 1
		schedule_ok = schedule_ok and plan.size() == game.waves.preview_count(n)
		schedule_ok = schedule_ok and worms == EncounterBalance.worm_count(n) and (worms == 0 or titans == 0)
		schedule_ok = schedule_ok and (n >= 12 or worms == 0)
		if n <= 40: report.append({"wave": n, "type": EncounterBalance.title(n), "enemies": plan.size(), "worms": worms, "titans": titans, "regular": game.waves.regular_count(n)})
	check(schedule_ok, "120 wave plans: exact previews, field-only worms, no worms before 12, no titan pile-ups")
	check(EncounterBalance.worm_count(12) == 1 and EncounterBalance.worm_count(24) == 2 and EncounterBalance.worm_count(40) == 3, "Worm escalation: one at 12, two at 24, three at 40")
	check(EncounterBalance.heavy_hp(10000, 4) <= 6.5 and EncounterBalance.heavy_speed(100) <= 1.25, "Very late and four-player boss scaling remains bounded")
	for i in range(1, 4):
		var stream := Sfx._file("Earthworm_%d" % i) as AudioStreamMP3
		check(stream != null and stream.get_length() > 1 and not stream.loop, "Earthworm_%d is the imported non-looping user recording" % i)
	game.waves.wave = 12
	check(game.spawn_zombie("earthworm", Vector2(10, 126), 1.5, "south", 30), "First worm spawns on the actual field")
	var worm: Earthworm = game.zombies_root.get_children().back()
	worm.set_physics_process(false)
	await process_frame
	# the difficulty's health multiplier (Normal 1.25 since 25 Sep 2026) rides on the worm's health
	check(worm.height == 14 and is_equal_approx(worm.hp, 2600 * float(game.difficulty.hp)) and is_equal_approx(worm.speed_mul, 1.25), "Wave 12 normal worm has intended size, HP and bounded speed")
	check(worm.cue_serial == 1 and worm._heard_cue == 1 and worm._voice.stream is AudioStreamMP3, "Spawn plays exactly one supplied worm recording")
	var saved_player: Vector3 = game.player.global_position
	var saved_worm := worm.global_position
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	for field: Vector2 in Waves.TITAN_FIELDS:
		worm.global_position = Map.ground_pos(field.x, field.y)
		var approach := worm._choose_destination()
		check(approach.distance_to(worm.global_position) > 10 and worm.safe_surface(approach), "Field entrance %s finds a real safe approach to the defended camp" % field)
	worm.global_position = saved_worm
	game.player.global_position = saved_player
	check(worm.warning.visible and not worm.targetable() and not worm.model.visible, "Arrival warns before revealing the worm")
	check(worm._hitboxes.size() + worm._shot_volumes.size() >= 12, "Worm has animated body hit zones, not a humanoid capsule")
	for clip in ["walk", "burrow", "emerge", "attack", "recovery", "dive", "death"]:
		check(worm.anim.has_animation(clip), "Rig includes " + clip)
	var health := worm.hp
	worm.damage(100, Vector3.FORWARD)
	check(worm.hp == health, "Fully underground worm cannot take invisible hits")
	worm._advance_phase()
	check(worm.phase == "emerge" and worm.targetable() and worm.model.visible, "Arrival transitions to visible emergence")
	worm._advance_phase()
	worm.damage(100, Vector3.FORWARD)
	check(is_equal_approx(worm.hp, health - 100) and worm._stagger == 0, "Exposed worm takes damage without automatic-fire stun lock")
	check(worm.phase_time >= 7, "Each attack cycle leaves a generous shooting window")
	worm.anim.pause()
	await physics_frame
	await physics_frame
	var aim := worm.global_position + Vector3.UP * 7
	if not worm._shot_volumes.is_empty(): aim = worm._shot_volumes[8].to_global(worm._shot_volumes[8].center)
	var ray := PhysicsRayQueryParameters3D.create(aim + Vector3.BACK * 25, aim - Vector3.BACK * 25, Zombie.SHOT_MASK)
	ray.collide_with_areas = true
	check(Zombie.from_hit(Zombie.cast_ray(worm, ray)) == worm, "Real ballistic ray intersects the exposed animated worm")
	var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(10, 110), 1, 0, false, "standard")
	tower.rotation.y = PI
	tower.set_physics_process(false)
	await physics_frame
	check(tower.can_see(worm), "Automatic tower can acquire the exposed body")
	worm._set_phase("burrow", 9)
	await physics_frame
	check(Zombie.from_hit(Zombie.cast_ray(worm, ray)) != worm and not tower.can_see(worm), "Burrowing disables ballistic hits and automatic tower targeting")
	worm._set_phase("exposed", 7)
	var rig: Skeleton3D = worm.model.find_children("*", "Skeleton3D", true, false)[0]
	worm.anim.play("attack")
	worm.anim.seek(0.0, true)
	await process_frame
	var head_before := rig.get_bone_global_pose(rig.get_bone_count() - 1).origin
	worm.anim.seek(2.5, true)
	await process_frame
	check(rig.get_bone_global_pose(rig.get_bone_count() - 1).origin.distance_to(head_before) > 0.2, "Attack clip deforms the actual skinned head")
	worm.play("walk")
	tower.queue_free()
	game.player.global_position = worm.global_position + Vector3(0, 0, 4)
	game.player.global_position.y = Map.ground_height(game.player.global_position.x, game.player.global_position.z)
	worm._advance_phase()
	var locked := worm.strike_point
	game.player.global_position += Vector3(20, 0, 0)
	worm._physics_process(0.1)
	check(worm.strike_point == locked and worm.warning.visible, "Attack marker is locked; it cannot chase a dodging player")
	var player_hp: float = game.player.hp
	worm.resolve_strike()
	check(game.player.hp == player_hp, "Player outside the marked radius takes no damage")
	game.player.global_position = locked
	worm.resolve_strike()
	check(is_equal_approx(game.player.hp, player_hp - 48 * worm.damage_mul), "Player inside unoccluded impact takes exactly one intended hit")
	check(not worm.safe_surface(Map.ground_pos(Map.FIRE.x, Map.FIRE.y)), "Worm cannot surface inside the camp")
	check(not worm._safe_tunnel(Map.ground_pos(Map.FIRE.x, Map.FIRE.y)), "Worm cannot tunnel through the camp")
	worm._set_phase("dive", Earthworm.DIVE_TIME)
	worm._advance_phase()
	var before := worm.global_position
	worm.destination = before + Vector3(0, 0, 8)
	worm._physics_process(0.5)
	check(worm.phase == "burrow" and worm.global_position.distance_to(before) > 1 and not worm.targetable(), "Underground body actually travels through the field")
	check(worm._trail.any(func(mound: MeshInstance3D): return mound.visible), "Moving earth trail reveals buried travel")
	worm.phase_time = 0.01
	worm._physics_process(0.02)
	check(worm.phase == "warning" and worm.phase_time == Earthworm.WARNING_TIME, "Burrow timeout always produces a new full emergence warning")
	var proxy := Earthworm.new()
	proxy.replica = true
	proxy.setup("earthworm", game.player, game.barricades, 1, Callable())
	proxy.appearance_seed = worm.appearance_seed
	game.add_child(proxy)
	proxy.set_physics_process(false)
	proxy.global_position = worm.global_position
	worm._set_phase("windup", Earthworm.WINDUP_TIME)
	worm.phase_time = 0.8
	proxy.apply_boss_state(worm.boss_state(), true)
	check(proxy.phase == worm.phase and proxy.strike_point == worm.strike_point and is_equal_approx(proxy.phase_time, 0.8), "Late join reconstructs attack target and remaining warning time")
	check(proxy._heard_cue == worm.cue_serial and not proxy._voice.playing and proxy._shown_impact == worm.impact_serial, "Late join does not replay past roar/impact effects")
	proxy.apply_boss_state(worm.boss_state(), false)
	check(not proxy._voice.playing, "Repeated snapshots do not duplicate audio")
	health = proxy.hp
	proxy.damage(100, Vector3.ZERO)
	check(proxy.hp == health, "Replica cannot author damage")
	proxy.queue_free()
	game.waves.wave = 24
	game.spawn_zombie("earthworm_ancient", Vector2(-10, 130), 1.8, "south")
	var ancient: Earthworm = game.zombies_root.get_children().back()
	ancient.set_physics_process(false)
	await process_frame
	check(ancient.height == 19 and ancient.max_hp > worm.max_hp and ancient.radius() > worm.radius(), "Ancient variant is larger and tougher with a distinct attack footprint")
	check(ancient.model_path != worm.model_path and ancient.anim.has_animation("attack"), "Ancient uses its own Meshy model and rig")
	game.waves._heavy_spawn_t = 10
	check(not game.waves._try_spawn({"type": "earthworm", "lane": "south", "point": Vector2(-42, 126)}), "Heavy reinforcements respect separation cooldown")
	if "--render-worms" in OS.get_cmdline_user_args():
		await render_worms(worm, ancient)
	var living: int = game.alive_zombies()
	worm._set_phase("exposed", 7)
	worm.damage(100000, Vector3.ZERO)
	check(not worm.alive and game.alive_zombies() == living - 1 and not worm.warning.visible, "Worm death scores exactly once and releases the wave counter")
	worm.damage(100000, Vector3.ZERO)
	check(game.alive_zombies() == living - 1, "Dead worm cannot be scored again")
	ancient._set_phase("burrow", 9)
	game.waves.phase = "spawning"
	check(game.waves.skip_current_wave() and not ancient.alive, "Skip-wave also completes with a fully underground worm")
	game.waves.set_process(false)
	var report_path := ProjectSettings.globalize_path("res://../artifacts/earthworm-balance.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	check(report_file != null, "Balance report directory exists in editor and exported test harness")
	if report_file: report_file.store_string(JSON.stringify(report, "  "))
	print("EARTHWORMS_DONE checks=%d failures=%d" % [checks, failures])
	await process_frame
	quit(1 if failures else 0)

func render_worms(worm: Earthworm, ancient: Earthworm) -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game.day_night.clock_seconds = 17.5 * 3600
	game.day_night.advance(1)
	game.day_night.set_process(false)
	game.achievements._toast.hide()
	game.hud.message("", 0)
	game.player.global_position = Map.ground_pos(4, 92)
	worm.global_position = Map.ground_pos(14, 122)
	ancient.global_position = Map.ground_pos(-9, 132)
	for actor: Earthworm in [worm, ancient]:
		actor.rotation.y = PI
		actor._set_phase("exposed", 7)
	game.player.camera.look_at(Map.ground_pos(3, 126) + Vector3.UP * 7)
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/earthworms-field.png"))
	worm.strike_point = Map.ground_pos(10, 111)
	worm._set_phase("windup", Earthworm.WINDUP_TIME)
	worm.phase_time = 0.7
	worm.anim.seek(1.9, true)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/earthworms-attack.png"))
