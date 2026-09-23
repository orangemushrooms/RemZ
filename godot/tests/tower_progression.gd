extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func settle() -> void:
	await physics_frame
	await physics_frame

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	var defence: DefenceSystem = game.defences
	defence.set_process(false)
	var p: Player = game.player
	p.score = 100000
	var point := Map.ground_pos(60, 112)
	var builder := Map.ground_pos(60, 117) + Vector3.UP * 0.1
	game.waves.wave = 99
	game.waves.completed = 0
	defence.begin_building()
	check(not defence.kind_buttons.standard.disabled, "Starter tower available without a quest")
	for kind in ["flame", "mortar", "mg42", "tesla"]:
		check(defence.kind_buttons[kind].disabled, kind + " locked despite money and a high current wave")
	defence.select_kind("tesla")
	check(defence.is_open and not defence.placing, "Direct selection cannot bypass the lock")
	defence.select_kind("unknown")
	check(defence.is_open and not defence.placing, "Unknown type cannot start placement")
	defence.close()
	for kind in DefenceTower.TYPES:
		var required: int = defence.unlock_waves(kind)
		p.global_position = builder
		await settle()
		if required > 0:
			game.waves.completed = required - 1
			var before := p.score
			var reason := defence.purchase(p, point, 0.0, kind)
			check(not reason.is_empty() and p.score == before and defence.towers.is_empty(), kind + " rejects premature purchase without charging or spawning")
		game.waves.completed = required
		defence._refresh_build_menu()
		check(not defence.kind_buttons[kind].disabled, kind + " menu unlocks at completed-wave boundary")
		var before := p.score
		check(defence.purchase(p, point, 0.0, kind).is_empty(), kind + " can be built at its unlock")
		check(p.score == before - int(DefenceTower.SPECS[kind].cost), kind + " charges exactly the listed price")
		if defence.towers.is_empty(): continue
		var tower: DefenceTower = defence.towers.values()[0]
		tower.set_physics_process(false)
		p.global_position = game.progression.npcs.mechanic.global_position + Vector3(0, 0.1, 2.3)
		await settle()
		for level in [2, 3]:
			var threshold: int = defence.unlock_waves(kind, level)
			game.waves.completed = threshold - 1
			before = p.score
			tower.hp -= 10
			var hp := tower.hp
			var reason: String = game.progression.transact(p, "mechanic", "tower_upgrade", str(tower.tower_id))
			check(not reason.is_empty() and tower.level == level - 1 and tower.hp == hp and p.score == before, "%s level %d blocks early shop upgrade atomically" % [kind, level])
			game.waves.completed = threshold
			var cost := tower.upgrade_cost()
			game.progression.transact(p, "mechanic", "tower_upgrade", str(tower.tower_id))
			check(tower.level == level and p.score == before - cost and tower.hp == tower.max_hp(), "%s level %d unlocks and charges once" % [kind, level])
		before = p.score
		check(not defence.maintain(p, tower.tower_id, "upgrade", true).is_empty() and p.score == before, kind + " retains maximum level")
		defence.towers.erase(tower.tower_id)
		tower.queue_free()
		await settle()
	game.waves.completed = 8
	p.score = 0
	defence._refresh_build_menu()
	check(defence.kind_buttons.tesla.disabled, "Unlocked tower still requires money")
	p.score = 100000
	defence._refresh_build_menu()
	check(not defence.kind_buttons.tesla.disabled, "Open menu updates after money changes")
	game.waves.completed = 0
	defence._refresh_build_menu()
	check(defence.kind_buttons.tesla.disabled and not defence.kind_buttons.standard.disabled, "New-round progress restores starter-only selection")
	print("TOWER_PROGRESSION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
