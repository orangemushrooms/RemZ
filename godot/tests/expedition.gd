extends SceneTree
const Checkpoint = preload("res://scripts/expedition_checkpoint.gd")
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var game: Node3D
var run: RunDirector

func _initialize() -> void: call_deferred("test")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began > 600000:
		print("FAIL: expedition timeout")
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func test() -> void:
	_rules()
	_profiles()
	_save_format()
	await _map("planes")
	await _map("forest")
	Node.print_orphan_nodes()
	print("EXPEDITION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _rules() -> void:
	for region in ["forest", "planes"]:
		for mode in RunRules.MODES:
			for difficulty in GameSettings.DIFFICULTIES.size():
				for run_seed in [1, 97521, 2147483647]:
					var config := RunRules.clean({"seed": run_seed, "region": region, "mode": mode, "difficulty": difficulty})
					var code := RunRules.encode(config)
					check(RunRules.decode(code) == config, "Run code round trip %s" % code)
					check(RunRules.decode(code.left(-1)+("0" if code[-1] != "0" else "1")).is_empty(), "Run code checksum detects corruption")
	for invalid in ["", "RZ1", "RZ1-X-00000001-0-0-12345678", "RZ1-P-FFFFFFFF-0-0-12345678", "RZ1-P-00000001--1-0-12345678", "x".repeat(100)]:
		check(RunRules.decode(invalid).is_empty(), "Malformed code refused")
	var a := RunRules.clean({"seed": 98121})
	check(RunRules.weather_plan(a) == RunRules.weather_plan(a), "Seeded weather is deterministic")
	check(RunRules.weather_plan(a) != RunRules.weather_plan(RunRules.clean({"seed": 98122})), "Different seed varies weather")
	var weather := RunRules.weather_plan(a)
	for i in range(1, weather.size()): check(weather[i].state != weather[i-1].state and weather[i].seconds >= 90, "Weather has distinct consecutive states and bounded durations")
	check(RunRules.rounds(RunRules.clean({"mode": "sprint"})) == 10, "Sprint ends after ten waves")
	check(not RunRules.weapon_allowed(RunRules.clean({"mode": "pistols"}), "ak47") and RunRules.weapon_allowed(RunRules.clean({"mode": "pistols"}), "magnum"), "Pistol challenge enforces its weapon rules")
	check(RunRules.tower_limit(RunRules.clean({"mode": "fortress"})) == 4 and RunRules.tower_limit(a) == 40, "Tower challenge preserves the normal forty-tower limit")
	var campaign := Campaign.new()
	campaign.selected_id = "planes"
	campaign.record_wave(25, "Normal", false)
	check(campaign.best_wave("planes") == 25 and not campaign.cleared("planes"), "Surviving wave 25 records progress while leaving the finale required")
	campaign.progress.clear()
	campaign.record_victory(10, "Normal")
	check(campaign.best_wave("planes") == 10 and campaign.cleared("planes"), "Ten-wave extraction victory secures its region with truthful wave progress")

func _profiles() -> void:
	var profile: Node = root.get_node("CharacterProfile")
	var previous: Dictionary = profile.data.duplicate(true)
	profile.data = profile.empty_profile("Test")
	profile.data.classes.gunslinger.total_xp = 1000000
	var old_build: Dictionary = profile.loadout()
	profile.add_xp(5000, "Test")
	check(profile.data.mastery.classes.gunslinger == 5000 and profile.data.cosmetics.has("mastery:gunslinger:1"), "Level thirty XP unlocks cosmetic class mastery")
	check(profile.loadout().level == old_build.level, "Cosmetic mastery leaves the combat level unchanged")
	for i in 100: profile.discover_enemy("runner", "pistol")
	profile.collect_record(2)
	profile.range_record("sequence", 70)
	profile.range_record("sequence", 20)
	var sanitized: Dictionary = profile.sanitize(profile.data)
	check(sanitized.mastery.weapons.pistol == 100 and sanitized.cosmetics.has("weapon_mastery:pistol:1"), "Weapon mastery persists its cosmetic badge")
	check(sanitized.journal.runner and sanitized.journal.record_2, "Bestiary and world records survive sanitisation")
	check(sanitized.mastery.range.sequence == 70, "Range record never decreases")
	check(profile.sanitize(previous).classes.gunslinger.total_xp == previous.classes.gunslinger.total_xp, "Version migration preserves existing XP")
	profile.data = previous

func _save_format() -> void:
	var state := {"version": Checkpoint.VERSION, "point": Vector3(2, 3, 4), "nested": {1: [true, 1.5, "text"]}}
	var bytes := Checkpoint.pack(state)
	check(Checkpoint.unpack(bytes) == state, "Checkpoint format preserves vectors and integer peer IDs")
	var names := {"version": Checkpoint.VERSION, &"supplies": {&"brew_meadow": 2}}
	check(Checkpoint.plain(names) and Checkpoint.unpack(Checkpoint.pack(names)) == names, "Safe Godot StringName inventory keys survive checkpoint serialisation")
	bytes[bytes.size()-1] = bytes[-1]^1
	check(Checkpoint.unpack(bytes).is_empty(), "Modified checkpoint rejected before deserialisation")
	check(Checkpoint.unpack(PackedByteArray([1, 2])).is_empty(), "Truncated checkpoint rejected")
	check(not Checkpoint.plain({"bad": NAN}) and not Checkpoint.plain({"bad": self}), "Nonfinite values and executable objects rejected")
	check(Checkpoint.unpack(Checkpoint.pack({"version": 999})).is_empty(), "Unknown save version rejected")

func _map(region: String) -> void:
	game = load("res://scenes/%s.tscn" % ("planes" if region == "planes" else "main")).instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if region == "planes":
		while not game.ready_for_exploration or game.preparing_survival or game.boot != null: await process_frame
	if region == "forest": game._on_start(false)
	paused = false
	run = game.expedition
	run.set_process(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.active = true
	game.day_night.set_process(false)
	game.weather.set_process(false)
	check(run != null and run.enabled and run.book != null, region+" installs all expedition systems")
	check(run.configure({"seed": 48151, "region": region}), "Run is configurable before wave one")
	var first: Array = game.waves.plan(8)
	check(first == game.waves.plan(8), "Wave composition survives repeated queries without consuming its seed")
	run.prepare_wave(8)
	check(run.profile == run.wave_profile(8).profile, "Wave start applies the announced profile")
	game.waves.wave = 3
	game.waves.completed = 3
	run.wave_cleared(3)
	var offers: Array = run.person(1).offers.duplicate()
	check(offers.size() == 3 and offers[0] != offers[1] and offers[1] != offers[2], "Three distinct augments offered")
	check(run.transact(1, "augment", [offers[0]]) == "Augment selected.", "One offered augment can be selected")
	check(run.person(1).offers.is_empty() and run.person(1).augments.size() == 1, "Augment choice consumes the entire offer")
	check(run.transact(1, "augment", [offers[1]]) != "Augment selected.", "Second choice from the same offer is refused")
	var xp_before: int = CharacterProfile.data.classes[CharacterProfile.active_class()].total_xp
	run.support(1, "repairs", "same-repair")
	run.support(1, "repairs", "same-repair")
	check(game.stats.repairs == 1 and CharacterProfile.data.classes[CharacterProfile.active_class()].total_xp == xp_before+75, "Duplicate support event grants statistics and XP once")
	run.book.open()
	check(run.book.is_open and paused and not game.player.active, "Solo fieldbook pauses combat")
	run.book.close()
	check(not paused and game.player.active, "Closing fieldbook restores gameplay")
	await _captures(region, "fieldbook")
	await _abilities(region)
	await _combat(region)
	await _checkpoint(region)
	await _operations(region)
	if region == "planes": await _planes()
	else:
		game.secret_night.configure_variant()
		var sequence: Array = game.secret_night.run_sequence.duplicate()
		game.secret_night.configure_variant()
		check(sequence == game.secret_night.run_sequence and game.secret_night.totem_order.size() == 3, "Secret Night variants are seeded and complete")
		check(game.secret_night.dance_goal >= 12 and game.secret_night.dance_goal <= 20, "Secret Night objective duration stays achievable")
		check(run.structure_grade() in ["A", "B", "C", "D"], "Forest ending grades structure health")
	await _finale(region)
	await _captures(region, "summary")
	game.over = false
	game.victory = false
	run.finale.stage = "defend"
	run.finale.health = 0.0
	run._tick_finale(0.25)
	check(game.over and not game.victory and run.finale.stage == "failed", "Destroyed final objective ends the solo run without awarding victory")
	paused = false
	game.queue_free()
	await process_frame
	await physics_frame
	current_scene = null

func _captures(region: String, screen: String) -> void:
	if "--expedition-captures" not in OS.get_cmdline_user_args(): return
	# BootScreen's fade lasts 350 ms after the map relinquishes its reference.
	await create_timer(0.5, true).timeout
	if screen == "fieldbook": run.book.open()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://../artifacts/expansion-tests/screenshots/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var texture := root.get_texture().get_image()
	check(texture.save_png(folder+region+"-"+screen+"-"+Lang.current+".png") == OK, "Rendered "+screen+" screenshot is saved")
	if screen == "fieldbook":
		check(root.get_visible_rect().encloses(run.book.panel.get_global_rect()), "Fieldbook fits the rendered viewport")
		var previous_size := root.content_scale_size
		root.content_scale_size = Vector2i(1280, 720)
		for i in 4: await process_frame
		for tab in run.book.pages.get_tab_count():
			run.book.pages.current_tab = tab
			for i in 3: await process_frame
			check(root.get_visible_rect().encloses(run.book.panel.get_global_rect()), "Fieldbook tab %d fits a 720p canvas" % tab)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder+region+"-fieldbook-720p-"+Lang.current+".png") == OK, "720p fieldbook screenshot is saved")
		root.content_scale_size = previous_size
		run.book.close()

func _enemy(at: Vector3, kind := "soldier") -> Zombie:
	var z := Zombie.new()
	z.setup(kind, game.player, game.barricades, 1, Callable())
	z.position = at
	game.zombies_root.add_child(z)
	z.set_physics_process(false)
	return z

func _clear_enemies() -> void:
	for z: Zombie in run._enemies(): z.free()
	for node in game.get_children():
		if node is Pickup: node.free()

func _combat(region: String) -> void:
	var p: Player = game.player
	var original: Dictionary = p.class_combat.build.duplicate(true)
	p.global_position = run._safe_point(Vector2(62, 47) if region == "planes" else Vector2(45, 45))+Vector3.UP*0.2
	p.rotation.y = 0
	p.pitch = 0
	p.head.rotation.x = 0
	var z := _enemy(p.global_position+Vector3(0, 0, -5))
	await physics_frame
	p.class_combat.configure({"id": "breacher", "level": 1})
	run.person(1).cooldown = 0.0
	var hp := z.hp
	check(run.transact(1, "ability", []) == "Class action activated." and z.hp == hp-65 and z.class_slow_time >= 4, "Breacher damages and slows an actual nearby enemy")
	p.class_combat.configure({"id": "marksman", "level": 1})
	run.person(1).cooldown = 0.0
	check(run.transact(1, "ability", []) == "Class action activated." and z.rare_status == "marked", "Marksman marks a visible enemy in the camera cone")
	hp = z.hp
	z.killer_peer = 1
	z.killer_weapon = "pistol"
	z.damage(20, Vector3.FORWARD)
	check(is_equal_approx(hp-z.hp, 25), "Marked damage is applied through the real damage pipeline")
	p.class_combat.configure({"id": "assault", "level": 1})
	run.person(1).cooldown = 0.0
	run.transact(1, "ability", [])
	z.class_slow_time = 0
	z.damage(1, Vector3.FORWARD)
	check(z.class_slow_time >= 2, "Actual suppressive hits slow the enemy")
	if "frost" not in run.person(1).augments: run.person(1).augments.append("frost")
	check(run.grenade_effect(p.global_position+Vector3(0, 1, -4), 1) and z.frost_mul < 1, "Frost grenade applies actual freeze status")
	p.class_combat.configure(original)
	_clear_enemies()
	var tower := DefenceTower.new()
	tower.game = game
	tower.owner_peer = 1
	tower.position = p.global_position+Vector3(8, 0, 0)
	game.add_child(tower)
	tower.set_process(false)
	if "overdrive" not in run.person(1).augments: run.person(1).augments.append("overdrive")
	tower.fire_at(tower.global_position+Vector3(0, 2, -15))
	check(is_equal_approx(tower.cooldown, float(tower.spec().rate)/1.25) and is_equal_approx(tower.heat, float(tower.spec().heat)*1.4), "Tower overdrive changes actual firing rate and heat together")
	tower.free()
	var old_mode: String = run.config.mode
	run.config.mode = "pistols"
	game.weapons.unlock("ak47")
	game.weapons.set_weapon("ak47")
	check(game.weapons.current != "ak47", "Pistol challenge blocks a real rifle equip request")
	check(not game.defences.build_requirement(p, "standard").is_empty(), "Pistol challenge blocks an attacking tower")
	run.config.mode = "fortress"
	for id in 4:
		var built := DefenceTower.new()
		built.game = game
		built.position = p.global_position+Vector3(id*8+8, 0, 0)
		game.add_child(built)
		built.set_process(false)
		game.defences.towers[id+1] = built
	check(game.defences.build_requirement(p, "standard") == "This challenge permits four towers.", "Four real towers enforce the fortress team's shared limit")
	for built in game.defences.towers.values(): built.free()
	game.defences.towers.clear()
	run.config.mode = "sprint"
	check(game.waves.plan(11).is_empty(), "Sprint does not generate an eleventh wave")
	run.config.mode = old_mode
	game.stats.kills = 7
	game.stats.headshots = 2
	var score: int = game.stats.performance_score(3)
	p.add_score(-100)
	check(game.stats.performance_score(3) == score, "Buying equipment never lowers the performance score")

func _operations(region: String) -> void:
	var p: Player = game.player
	game.waves.phase = "idle"
	game.waves.timer = 99999
	for kind in ["drone", "radio", "escort"]:
		run.operation.clear()
		run.operation = {"kind": kind, "at": run._safe_point(Vector2(run.camp().x+8, run.camp().z+6)), "stage": "offered", "done": false, "health": 120.0, "timer": 0.0, "wave": 50+checks, "peer": 0, "expires": run.elapsed+600}
		p.global_position = run.operation.at+Vector3.UP*0.2
		check(run.transact(1, "interact", ["operation"]) == "Operation started." and run.operation.pending > 0, kind+" operation accepts and queues real guards")
		var spawned := 0
		for step in 180:
			if run.operation.done: break
			p.global_position = run.operation.at+Vector3.UP*0.2
			run._process(1.0)
			spawned += game.alive_zombies()
			_clear_enemies()
			if kind == "drone": run.transact(1, "interact", ["operation"])
			await physics_frame
		check(spawned >= (6 if kind == "drone" else 8), kind+" mission spawns its complete reinforcement budget")
		check(run.operation.stage == "complete", kind+" objective completes by playing its full state machine")
		var money := p.score
		run._finish_operation(1)
		check(p.score == money, kind+" completed objective cannot pay out twice")
	run.operation.clear()
	run._sync_markers()
	if region == "planes":
		var site: Dictionary = run.sites[0]
		p.global_position = site.at+Vector3.UP*0.2
		check(run.transact(1, "interact", [site.id]) == "Hold the outpost for 35 seconds.", "Outpost starts with its defensive objective")
		var guards := 0
		for step in 160:
			if site.done: break
			run._process(1)
			guards += game.alive_zombies()
			_clear_enemies()
			await physics_frame
		check(site.done and guards >= 6, "Outpost completes after its guards and entire hold duration")
		check(run.transact(1, "interact", [site.id]) == "Outpost supplies received.", "Secured outpost restocks its defender")
		check(run.transact(1, "interact", [site.id]) == "Outpost supplies are replenished next wave.", "Outpost restocking cannot be spammed")

func _abilities(region: String) -> void:
	var p: Player = game.player
	var build: Dictionary = p.class_combat.build.duplicate(true)
	p.class_combat.configure({"id": "gunslinger", "level": 1})
	run.person(1).cooldown = 0.0
	check(run.transact(1, "ability", []) == "Class action activated." and p.class_combat.modifier("spread", "pistol") < 0.5, "Gunslinger action improves precision")
	check(run.transact(1, "ability", []) == "Class action is cooling down.", "Action cannot be spammed during its cooldown")
	p.class_combat.tick(7, p, game.weapons, game.zombies_root)
	check(not p.class_combat.active("exp_focus"), "Focus expires after its duration")
	p.class_combat.configure({"id": "assault", "level": 1})
	run.person(1).cooldown = 0.0
	run.transact(1, "ability", [])
	check(p.class_combat.active("exp_suppression") and p.class_combat.modifier("rate", "ak47") == 0.8, "Assault activates suppressive fire")
	p.class_combat.configure({"id": "marksman", "level": 1})
	run.person(1).cooldown = 0.0
	check(run.transact(1, "ability", []) == "Aim at a visible enemy to mark it." and run.person(1).cooldown == 0, "Failed mark consumes no cooldown")
	p.class_combat.configure({"id": "assassin", "level": 1})
	check(run.transact(1, "ability", []) == "Use your chosen teleport with [V].", "Assassin keeps its selected teleport")
	p.class_combat.configure(build)
	var state := run.person(1)
	if "swap" not in state.augments: state.augments.append("swap")
	game.weapons.unlock("magnum")
	game.weapons.set_weapon("magnum")
	check(p.class_combat.active("exp_swap"), "Changing weapon starts the augment window")
	p.class_combat.timers.exp_swap = 0.0
	game.weapons.set_weapon("pistol")
	check(not p.class_combat.active("exp_swap"), "Swap window has an eight second cooldown")
	var before := p.effective_speed_mul()
	run.cargo_peer = 1
	check(is_equal_approx(p.effective_speed_mul(), before*0.8), "A carried crate slows the carrier")
	run.cargo_peer = 0
	var dummy := Zombie.new()
	dummy.killer_peer = 1
	dummy.killer_weapon = "pistol"
	dummy.set_meta("exp_mark_until", run.elapsed+10)
	check(run.incoming_damage(dummy, 100) == 125, "Team mark increases incoming damage")
	dummy.free()
	check(run.transact(1, "ammo", [999]) == "Move within three metres of a living teammate.", "Unknown supply recipient cannot receive inventory")
	check(run.transact(1, "heal", [1]) == "Move within three metres of a living teammate.", "Self-healing does not farm support XP")
	check(run.transact(1, "drink", [1, "invented"]) != "Supplies transferred.", "Malformed supply request is refused")

func _checkpoint(region: String) -> void:
	var was_processing: bool = game.weapons.is_processing()
	game.weapons.set_process(false)
	game.waves.phase = "idle"
	game.waves.queue.clear()
	run.operation.clear()
	run.finale.clear()
	game.player.global_position = run.camp()+Vector3(2, 0.3, 2)
	game.player.score = 374
	game.player.hp = 63.0
	game.weapons.state.pistol.reserve = 41
	game.weapons.unlock("plasma_sniper")
	game.weapons.set_weapon("plasma_sniper")
	game.weapons.state.plasma_sniper.heat = 0.82
	game.weapons.state.plasma_sniper.vent = true
	game.weapons.state.plasma_sniper.reloading = 2.0
	run.checkpoints.override_path = "user://expedition_test_%s.save" % region
	check(run.checkpoints.eligibility().is_empty(), "Quiet intermission is eligible for saving")
	var saved: Dictionary = run.checkpoints.capture()
	check(run.checkpoints.validate(saved).is_empty(), "Captured checkpoint passes schema validation")
	if not get_nodes_in_group("checkpoint_pickups").is_empty():
		var collectible: Loot = get_nodes_in_group("checkpoint_pickups")[0]
		var at := collectible.global_position
		collectible.taken = not collectible.taken
		collectible.global_position += Vector3(7, 0, 4)
		run.checkpoints.restore(saved)
		check(collectible.global_position == at and collectible.taken == saved.loots[run.checkpoints._key(collectible)][0], "Checkpoint restores collectible availability and moved positions")
	if not game.pumpkins.is_empty():
		game.pumpkins[0].shatter(false)
		run.checkpoints.restore(saved)
		check(not game.pumpkins[0].broken and game.pumpkins[0].model.visible, "Loading an earlier save restores pumpkin visuals and collision")
	if not run.checkpoints.windows.is_empty():
		var key: String = run.checkpoints.windows.values()[0].path
		var pane := game.get_node_or_null(key)
		if pane:
			pane.free()
			run.checkpoints.restore(saved)
			check(game.get_node_or_null(run.checkpoints.windows.values()[0].path) is Breakable, "Loading an earlier save rebuilds a shattered window")
	check(run.checkpoints.save_run() == "Checkpoint saved.", "Checkpoint writes successfully")
	game.player.score = 1
	game.player.hp = 99
	game.weapons.state.pistol.reserve = 1
	game.weapons.state.plasma_sniper.heat = 0.0
	game.weapons.state.plasma_sniper.vent = false
	game.weapons.state.plasma_sniper.reloading = 0.0
	game.weapons.set_weapon("pistol")
	var xp: int = CharacterProfile.data.classes[CharacterProfile.active_class()].total_xp
	check(run.checkpoints.load_run() == "Expedition continued.", "Checkpoint loads successfully")
	check(game.player.score == 374 and game.player.hp == 63 and game.weapons.state.pistol.reserve == 41 and game.waves.completed == 3, "Load restores money, health, ammunition and completed waves")
	check(game.weapons.current == "plasma_sniper" and is_equal_approx(game.weapons.state.plasma_sniper.heat, 0.82) and game.weapons.state.plasma_sniper.vent and game.weapons.state.plasma_sniper.reloading == 2.0, "Checkpoint preserves weapon heat locks and remaining reload time")
	check(CharacterProfile.data.classes[CharacterProfile.active_class()].total_xp == xp, "Continuing a checkpoint does not repeat XP rewards")
	game.waves.phase = "spawning"
	check(not run.checkpoints.eligibility().is_empty(), "Mid-wave saves are blocked")
	game.waves.phase = "idle"
	var damaged := saved.duplicate(true)
	damaged.players[1].hp = -5
	check(not run.checkpoints.validate(damaged).is_empty(), "Invalid player state is rejected before restoration")
	for section in ["people", "sites", "puzzle_order", "structures", "operation"]:
		damaged = saved.duplicate(true)
		damaged.director[section] = "invalid"
		check(not run.checkpoints.validate(damaged).is_empty(), "Malformed director section rejected: "+section)
	damaged = saved.duplicate(true)
	damaged.world.pumpkins = ["invalid"]
	check(not run.checkpoints.validate(damaged).is_empty(), "Malformed world state rejected before changing gameplay")
	var f := FileAccess.open(run.checkpoints.path(), FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3]))
	f.close()
	check(run.checkpoints.load_run() == "Checkpoint is damaged or incompatible." and game.player.score == 374, "Corrupt disk save leaves the active run unchanged")
	check(run.checkpoints.save_run() == "Checkpoint saved.", "A valid save can replace a corrupt slot safely")
	game.weapons.set_weapon("pistol")
	game.weapons.set_process(was_processing)

func _planes() -> void:
	var p: Player = game.player
	p.global_position = run.sites[2].at+Vector3.UP*0.3
	var dollars := p.score
	check(run.transact(1, "interact", ["site_2"]) == "Cache and journal record collected.", "Exploration cache grants its record and supplies")
	check(run.transact(1, "interact", ["site_2"]) != "Cache and journal record collected." and p.score == dollars+60, "Cache cannot be collected twice")
	for index in run.puzzle_order:
		p.global_position = run.sites[5+index].at+Vector3.UP*0.3
		run.transact(1, "interact", ["site_%d" % (5+index)])
	check(run.puzzle_done and run.puzzle_step == 3, "Three-step Planes transmitter puzzle completes in the seeded order")
	p.global_position = run.camp()+Vector3.UP*0.3
	check(run.transact(1, "contract", []) == "Eliminate five elite enemies from at least 60 metres.", "Sniper contract is accepted at camp")
	var elite := _enemy(p.global_position+Vector3(20, 0, 0))
	elite.killer_peer = 1
	elite.killer_weapon = "marksman"
	elite.global_position = p.global_position+Vector3(20, 0, 0)
	run.killed(elite)
	check(run.person(1).longshots == 0, "Short-range elite kills do not advance the sniper contract")
	elite.global_position = p.global_position+Vector3(75, 0, 0)
	elite.killer_weapon = "pistol"
	run.killed(elite)
	check(run.person(1).longshots == 0, "A pistol kill cannot satisfy the sniper contract")
	elite.killer_weapon = "marksman"
	var money := p.score
	for i in 5: run.killed(elite)
	check(run.person(1).contract == 2 and run.person(1).longshots == 5 and p.score == money+350, "Five eligible long-range kills award the contract exactly once")
	run.killed(elite)
	check(p.score == money+350, "Completed sniper contract cannot pay again")
	elite.free()
	check(run.transact(1, "cargo", []) == "Deliver the crate to the marked supply destination.", "Supply route begins with collecting the crate")
	p.global_position = run.cargo_destination()+Vector3.UP*0.3
	check(run.transact(1, "interact", ["delivery"]) == "Supplies delivered. Ammunition restocked." and run.cargo_deliveries == 1, "Supply delivery requires arrival at the destination")
	var fire: Node3D = game.cornfield.fires
	game.weather.force("clear")
	var cell: Vector2i = fire.wheat.keys()[0]
	fire.ignite(fire.wheat[cell], 2, 1, "grenade")
	check(not fire.active.is_empty(), "Crop ignition creates an active fire")
	check(fire.extinguish(fire.wheat[cell], 6) > 0 and not fire.burned.is_empty(), "Extinguishing removes fire while preserving charred crops")
	game.weather.wind = Vector2.LEFT
	check(fire.spread_directions()[0] == Vector2i.LEFT, "Wind determines the preferred spread direction")
	check(fire.smoke.size() == fire.MAX_ACTIVE, "Smoke uses a bounded particle pool")
	await _pursuit()
	game.shooting_range.opened = true
	p.global_position = game.shooting_range.house.to_global(Vector3(0, 0.3, 0))
	check(run.start_range(p, "sequence") == "Thirty second range session started.", "Timed range sequence starts inside the range")
	var target := int(run.range_game.sequence[0])
	run.range_hit(1, (target+1)%6, 10)
	check(run.range_game.scores.is_empty(), "Out-of-order range hits do not score")
	run.range_hit(1, target, 10)
	check(run.range_game.scores[1] == 10 and run.range_game.progress[1] == 1, "Correct target advances the range sequence")
	run.range_game.timer = 0.0
	game.waves.wave = 12
	game.waves.queue.assign(["earthworm"])
	check(game.waves.is_boss_fight(), "A queued boss on a non-fifth wave triggers boss music")
	game.waves.queue.clear()
	check(not game.waves.is_boss_fight(), "Boss music ends after the last boss")
	await _structures()

func _pursuit() -> void:
	var p: Player = game.player
	var found := false
	var at := Vector3.ZERO
	for x in range(-120, 130, 20):
		for z in range(60, 250, 20):
			p.global_position = Map.ground_pos(x, z)+Vector3.UP*0.2
			at = run._safe_point(Vector2(x+35, z))
			if not game.near_building(Vector2(x, z)) and run._visible(at+Vector3.UP, p.global_position+Vector3.UP):
				found = true
				break
		if found: break
	check(found, "An open field provides a clear line of sight for pursuit")
	if not found: return
	var z: Zombie = game.create_enemy("runner", at, 1)
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	for step in 80:
		z.global_position = at
		z._physics_process(0.5)
	check(z.expedition_pursuit == 30, "Sustained open-field pursuit reaches its bounded twenty percent acceleration")
	p.global_position = at+Vector3(5, 0, 0)
	z.global_position = at
	z._physics_process(1)
	check(z.expedition_pursuit < 30, "Closing the distance releases the pursuit acceleration")
	z.free()
	var helmets := 0
	var spawns := 0
	p.global_position = run.camp()+Vector3.UP*0.3
	game._spawn_rng = RunRules.rng(run.config, "armour-test", 10)
	for i in 32:
		var enemy: Zombie = game.spawn_enemy("soldier", 10)
		if enemy:
			spawns += 1
			if enemy.armored: helmets += 1
			enemy.free()
	check(spawns >= 10 and helmets > 0, "Regular wave-ten spawns actually include helmeted humanoids")

func _structures() -> void:
	var p: Player = game.player
	p.score = 2000
	var found := false
	for x in range(-120, 150, 15):
		for z in range(60, 250, 15):
			p.global_position = Map.ground_pos(x, z)+Vector3.UP*0.3
			p.rotation.y = 0
			var at := Map.ground_pos(x, z-5)
			if run.structures.placement_error(p, "gate", at, 0).is_empty():
				found = true
				break
		if found: break
	check(found, "Surveyed Planes terrain has a legal gate building site")
	if not found: return
	check(run.structures.build(p, "gate") == "Fortification built.", "Gate is built with physical collision")
	await physics_frame
	var item: Dictionary = run.structures.items.values()[0]
	var ray := PhysicsRayQueryParameters3D.create(item.at+Vector3(0, 1, -3), item.at+Vector3(0, 1, 3), 8)
	check(not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Closed gate blocks passage")
	p.global_position = item.at+Vector3(0, 0.3, 2.5)
	run.structures.interact(p, item.id, "use")
	await physics_frame
	check(game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Open gate clears its centre passage")
	p.global_position = item.at+Vector3.UP*0.2
	await physics_frame
	check(run.structures.interact(p, item.id, "use") == "Keep the gate opening clear before closing it." and item.open, "Occupied gate cannot close through a player")
	p.global_position = item.at+Vector3(0, 0.3, 2.5)
	run.structures.items[item.id].hp = 50.0
	check(run.structures.interact(p, item.id, "repair") == "Fortification repaired." and run.structures.items[item.id].hp == 600, "Paid repairs restore a damaged structure")
	for kind in ["embrasure", "observation"]:
		found = false
		for x in range(-120, 150, 15):
			for z in range(60, 250, 15):
				p.global_position = Map.ground_pos(x, z)+Vector3.UP*0.3
				p.rotation.y = 0
				var at := Map.ground_pos(x, z-(8.5 if kind == "observation" else 5.0))
				if run.structures.placement_error(p, kind, at, 0).is_empty():
					found = true
					break
			if found: break
		check(found and run.structures.build(p, kind) == "Fortification built.", "Surveyed terrain permits building "+kind)
		if not found: continue
		await physics_frame
		item = run.structures.items.values()[-1]
		if kind == "embrasure":
			ray = PhysicsRayQueryParameters3D.create(item.at+Vector3(0, 0.5, -3), item.at+Vector3(0, 0.5, 3), 8)
			check(not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Firing wall blocks low incoming shots")
			ray.from.y = item.at.y+1.5
			ray.to.y = item.at.y+1.5
			check(game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Firing wall leaves its firing opening clear")
		else:
			p.global_position = Map.ground_pos(item.at.x, item.at.z-7)+Vector3.UP*0.2
			p.velocity = Vector3.ZERO
			for step in 240:
				p.velocity = Vector3(0, p.velocity.y-20.0/60.0, 3.6)
				p.move_and_slide()
				await physics_frame
				if p.global_position.z > item.at.z+1: break
			print("DECK_WALK position=", p.global_position-item.at, " floor=", p.is_on_floor(), " velocity=", p.velocity)
			check(p.global_position.y > item.at.y+1.9 and p.global_position.z > item.at.z+1, "Player walks from ground to the observation deck without jumping")
	var saved: Array = run.structures.snapshot()
	run.structures.clear()
	await physics_frame
	run.structures.apply_snapshot(saved)
	await physics_frame
	check(run.structures.items.size() == 3 and run.structures.nodes.size() == 3, "All three physical structures survive snapshot reconstruction")

func _finale(region: String) -> void:
	game.campaign.progress.clear()
	game.waves.wave = run.round_limit()
	game.waves.completed = run.round_limit()-1
	game.waves.phase = "spawning"
	game.waves.queue.clear()
	run.finale.clear()
	if region == "planes": game.waves.complete_wave()
	else: game.waves._complete_wave()
	check(not game.over and game.waves.phase == "finale" and run.finale.stage == "prepare", "Last wave starts the map finale instead of ending immediately")
	check(game.campaign.best_wave(region) == run.round_limit() and not game.campaign.cleared(region), "Actual final wave completion cannot grant an early campaign victory")
	game.player.global_position = run.finale.at+Vector3.UP*0.3
	check(run.transact(1, "interact", ["finale"]) == "Final defence is active.", "Player activates the final radio or extraction transport")
	var timer: float = run.finale.timer
	game.player.global_position += Vector3(45, 0, 0)
	run._tick_finale(1)
	check(run.finale.timer == timer, "Leaving the final objective does not advance the hold timer")
	_clear_enemies()
	game.player.global_position = run.finale.at+Vector3.UP*0.2
	var budget: int = run.finale.remaining
	var spawned := 0
	for step in 600:
		if game.over: break
		run._tick_finale(0.75)
		spawned += game.alive_zombies()
		_clear_enemies()
		await physics_frame
	check(spawned == budget and run.finale.remaining == 0, "Final defence spawns the complete reinforcement budget")
	check(game.over and game.victory and run.finale.stage == "complete", "Completing the final defence secures the region")
	check(game.campaign.cleared(region), "Successful final defence records the region victory")
	check(game.stats._finished and not game.stats.records().is_empty(), "Both maps finish with a performance record")
	check(game.day_night.clock_seconds >= 6.6*3600 and game.day_night.clock_seconds < 7*3600, "Victory reaches dawn")
