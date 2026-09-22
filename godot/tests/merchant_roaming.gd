extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.waves.wave = 5
	game.player.set_physics_process(false)
	game.player.global_position = Vector3(0, -100, 0)
	var market = game.progression.rare_market
	market.set_physics_process(false)
	market.random.seed = 431
	var cells := {}
	var visited := {}
	var greatest_step := 0.0
	for i in 18000:
		var before: Vector3 = market.npc.global_position
		var was_active: bool = market.active
		market._physics_process(0.25)
		if was_active: greatest_step = maxf(greatest_step, before.distance_to(market.npc.global_position))
		cells[market.roam_cell(market.npc.global_position)] = true
		if i % 100 == 0:
			visited[Vector2i(Vector2(market.npc.position.x, market.npc.position.z) / 10)] = true
		if i % 1000 == 0:
			print("ROAM ", i, " position=", market.npc.position, " cells=", cells.size(), " stops=", market.visit_clock)
		if i % 200 == 0: await physics_frame
	var ok: bool = cells.size() == 9 and visited.size() >= 80 and greatest_step <= 0.414
	print("PASS: " if ok else "FAIL: ", "Merchant physically visits all nine sectors without teleporting")
	print("ROAM_DONE cells=", cells.size(), " tiles=", visited.size(), " stops=", market.visit_clock, " max_step=", greatest_step, " failures=", 0 if ok else 1)
	quit(0 if ok else 1)
