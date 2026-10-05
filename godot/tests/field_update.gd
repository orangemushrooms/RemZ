extends SceneTree

var game: Node3D
var checks := 0
var failures := 0
var started := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 240000: quit(1)
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func clear_enemies() -> void:
	for z in game.zombies_root.get_children():
		if z is Zombie: z.queue_free()
	await process_frame

func run() -> void:
	seed(270926)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.hp = 100000
	var trials: FieldTrials = game.field_trials
	trials.set_process(false)
	for point in FieldTrials.SPAWNS:
		check(trials.FIELD.has_point(point) and Map.leaf_weight(point.x, point.y) < 0.2 and Map.meadow_weight(point.x, point.y) > 0.65, "Boss entrance on open field: %s" % point)
	for n in [10, 15, 20]:
		game.waves.wave = n - 1
		game.waves.completed = n - 1
		game.waves.start(n)
		check(trials.active and trials.next_wave == n and game.waves.phase == "field_trial" and game.waves.wave == n - 1, "Wave %d waits for its intermission" % n)
		check(trials.permits(game.player.global_position) and absf(game.day_night.clock_seconds / 3600.0 - 6.7) < 0.05, "Team arrives on the field at dawn")
		check(not trials.begin(n) and not trials.begin(10), "Repeated starts cannot reset a running fight")
		game.player.global_position = Map.ground_pos(0, 0)
		game.player.velocity = Vector3(0, 10, -100)
		trials.confine(game.player)
		check(trials.permits(game.player.global_position) and game.player.velocity == Vector3.ZERO, "Field boundary blocks escape and shove")
		trials.countdown = 0
		var expected: Array = trials.pending.duplicate()
		for i in FieldTrials.ROSTERS[n].size(): trials._process(0.7)
		var kinds: Array = []
		for z in trials.enemies:
			kinds.append(z.net_kind)
			z.set_physics_process(false)
			check(trials.FIELD.has_point(Vector2(z.global_position.x, z.global_position.z)), "Projected spawn remains inside the arena")
		check(kinds == expected and trials.pending.is_empty(), "All %d seeded encounter bosses present together" % kinds.size())
		check(trials.remaining == kinds.size(), "No completion while bosses live")
		var snap := trials.snapshot()
		var mirror := FieldTrials.new()
		game.add_child(mirror)
		mirror.setup(game)
		mirror.set_process(false)
		mirror.apply_snapshot(snap)
		check(mirror.active and mirror.remaining == kinds.size() and mirror.border.visible and mirror.teleport_serial == trials.teleport_serial, "Late-join state restores arena, phase and teleport generation")
		mirror.queue_free()
		if n == 10:
			var kills: int = game.stats.kills
			var money: int = game.player.score
			trials.finish(true)
			await process_frame
			check(game.stats.kills == kills and game.player.score == money and game.alive_zombies() == 0, "Cheat skip removes bosses without kill or reward farming")
		else:
			for z in trials.enemies: z.die(Vector3.ZERO)
			var money: int = game.player.score
			game.player.global_position = Map.ground_pos(FieldTrials.ARRIVAL.x, FieldTrials.ARRIVAL.y)
			for second in 31:
				if not trials.active: break
				trials._process(1)
			trials._process(0.1)
			check(not trials.active and game.player.score == money + n * 35, "Final boss death grants the team reward once")
			trials.finish()
			check(game.player.score == money + n * 35, "Repeated completion cannot duplicate rewards")
		check(trials.completed.has(n) and not trials.border.visible and game.waves.phase == "idle" and trials.permits(Vector3.ZERO), "Completing/skipping releases the field and resumes the wave countdown")
		game.waves.start(n)
		check(game.waves.wave == n and game.waves.phase == "spawning" and not trials.active, "Wave %d starts after its trial, without replaying it" % n)
		game.waves.queue.clear()
		await clear_enemies()

	game.waves.phase = "idle"
	for i in 2:
		var spec: Dictionary = FieldTrials.SECRETS[i]
		game.waves.completed = spec.wave
		game.player.global_position = trials.shrines[i].global_position + Vector3(0, 0.3, 1.8)
		await physics_frame
		trials.interact(game.player)
		check(trials.active and trials.secret == i and trials.stage == 0, "Hidden grove %d starts from its physical shrine" % i)
		trials.interact(game.player)
		check(trials.stage == 0, "Missing offering cannot start the ritual")
		game.brewing.stock(game.player.peer_id).flowers[spec.flower] = 3
		trials.interact(game.player)
		check(trials.stage == 1 and game.brewing.stock(game.player.peer_id).flowers[spec.flower] == 0, "Offering consumed exactly once")
		while not trials.pending.is_empty(): trials._process(0.7)
		for z in trials.enemies: z.die(Vector3.ZERO)
		trials._process(0.1)
		check(trials.stage == 2 and trials.active, "Ritual requires returning to claim its reward")
		trials.interact(game.player)
		check(trials.secret_done.has(i) and not trials.active and int(game.brewing.stock(game.player.peer_id).drinks.get(spec.drink, 0)) == 2, "Hidden quest grants two potions and completes once")
		await clear_enemies()

	# Lightning uses a different update path on worms. Test the actual reveal/reset.
	game.spawn_zombie("earthworm_ancient", Vector2(50, 110), 1.0)
	var worm := game.zombies_root.get_child(game.zombies_root.get_child_count() - 1) as Earthworm
	worm.set_physics_process(false)
	worm.lightning_reveal(0.1)
	worm._physics_process(0.2)
	var dark := true
	for material in worm._materials: dark = dark and material.emission == Color.BLACK
	check(dark and worm._reveal_t == 0, "Grave Wyrm's lightning whiteness expires")
	await clear_enemies()
	game.spawn_zombie("titan", Vector2(50, 110), 1.0)
	var titan := game.zombies_root.get_child(game.zombies_root.get_child_count() - 1) as Titan
	titan.set_physics_process(false)
	titan.hp = titan.max_hp * 0.3
	titan.damage(1, Vector3.ZERO)
	titan.anim.play("crawl", 0)
	titan.anim.seek(titan.anim.get_animation("crawl").length * 0.2, true)
	titan.anim.pause()
	await process_frame
	titan._process(0.1)
	var hip_bone := titan.skeleton.find_bone("Hips")
	var crawl_hip := titan.skeleton.to_global(titan.skeleton.get_bone_global_pose(hip_bone).origin)
	var crawl_height := crawl_hip.y - Map.ground_height(crawl_hip.x, crawl_hip.z)
	titan.play("attack")
	check(titan.crawling and titan.clip == "crawl_attack" and not titan.can_throw(), "Crawler attacks with its grounded clip and never uses a standing throw")
	for time in [0.0, 0.6, 1.0, 1.6]:
		titan.anim.seek(time, true)
		titan.anim.pause()
		await process_frame
		titan._process(0.1)
		var hip := titan.skeleton.find_bone("Hips")
		var world_hip := titan.skeleton.to_global(titan.skeleton.get_bone_global_pose(hip).origin)
		var above := world_hip.y - Map.ground_height(world_hip.x, world_hip.z)
		check(above <= crawl_height + titan.height * 0.025, "Attack stays at crawl height at %.1f s: %.2f / %.2f m" % [time, above, crawl_height])
	titan.die(Vector3.ZERO)
	check(titan.clip == "crawl_death" and titan.anim.is_playing(), "Crawler actively collapses from its attack pose")
	await clear_enemies()
	for phase in [0, SecretNight.GUESTS, SecretNight.RETURN, SecretNight.WAKING]:
		game.secret_night.completed = false
		game.secret_night.begin()
		game.secret_night.step = phase
		if phase == SecretNight.GUESTS: game.secret_night._spawn_ravers()
		var money: int = game.player.score
		game.hud.hallucinate(180)
		check(game.waves.skip_current_wave(), "Goa can be skipped at stage %d" % phase)
		await process_frame
		check(not game.secret_night.active and not game.secret_night.song.playing and game.alive_zombies() == 0 and game.player.score == money and game.hud._trip_t <= 1.5, "Goa skip clears presentation/enemies/trip without rewards")

	var f: FortuneWheels = game.fortune
	var bag: Dictionary = game.brewing.stock(game.player.peer_id)
	var before := 0
	for value in bag.flowers.values(): before += int(value)
	f.grant(game.player, {"kind": "flower"})
	var after := 0
	for value in bag.flowers.values(): after += int(value)
	check(after - before == 3, "Wheel flower prize grants a useful bundle")
	for id in game.brewing.Recipes.DRINKS: bag.drinks[id] = game.brewing.Recipes.DRINK_LIMIT
	var money: int = game.player.score
	f.grant(game.player, {"kind": "potion"})
	check(game.player.score == money + FortuneWheels.COST, "Full potion inventory refunds the spin")
	for id in ["cash500", "cash1000"]:
		money = game.player.score
		f.grant(game.player, {"kind": id})
		check(game.player.score == money + int(id.trim_prefix("cash")), "Large cash prize pays its advertised value")
	check(Sfx.get_stream("dog_growl") != null, "Dog recording loads as an audio event")
	print("FIELD_UPDATE_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
