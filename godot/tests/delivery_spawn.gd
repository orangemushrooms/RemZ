extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var shop: Progression = game.progression
	check(shop.cache_ready and shop.cache_node.visible, "Round starts with a placed delivery")
	var original := shop.cache_node.global_position
	check(shop.place_cache() and shop.cache_node.global_position == original, "Repeated setup never relocates an active delivery")
	var positions: Array[Vector3] = []
	var nav: RID = game.nav_region.get_navigation_map()
	var start := NavigationServer3D.map_get_closest_point(nav, Map.ground_pos(Map.PLAYER_START.x,Map.PLAYER_START.y))
	for n in 16:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7001 + n * 319
		var point := shop.choose_cache_position(rng)
		check(point.is_finite(), "Round sample %d finds a valid package location" % n)
		if not point.is_finite(): continue
		positions.append(point)
		var at := Vector2(point.x,point.z)
		var end := NavigationServer3D.map_get_closest_point(nav,point)
		var route := NavigationServer3D.map_get_path(nav,start,end,true)
		check(Map.BOUNDS.has_point(at) and not Map.in_building(at.x,at.y,3) and not game.perimeter.excludes_spawn(at) and not route.is_empty() and route[route.size()-1].distance_to(end)<0.8, "Package %d is outdoors and reachable from camp" % n)
		shop.cache_node.global_position = point
		game.player.global_position = point + Vector3(0,0.1,2.0)
		check(shop.close_enough(game.player,"cache"), "Package %d can actually be interacted with" % n)
	var spread := Rect2(Vector2(positions[0].x,positions[0].z),Vector2.ZERO)
	for point in positions: spread = spread.expand(Vector2(point.x,point.z))
	check(spread.size.x > 100 and spread.size.y > 100, "Packages vary across the map instead of clustering at the old site")
	shop.cache_node.global_position = original
	var state := shop.snapshot()
	shop.cache_node.global_position = Vector3.ZERO
	shop.cache_ready = false
	shop.apply_snapshot(state)
	check(shop.cache_ready and shop.cache_node.visible and shop.cache_node.global_position == original, "Late join restores the host's exact package position")
	state.team.cache = true
	shop.apply_snapshot(state)
	check(not shop.cache_node.visible and not shop.close_enough(game.player,"cache"), "Collected delivery stays hidden and cannot be collected again after synchronization")
	print("DELIVERY_SPAWN_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
