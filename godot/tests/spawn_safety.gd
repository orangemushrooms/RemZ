extends SceneTree

var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 120000: quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var point: Vector2 = Map.SPAWNS["north"][0]
	var nav: RID = game.nav_region.get_navigation_map()
	var projected := NavigationServer3D.map_get_closest_point(nav, Map.ground_pos(point.x, point.y))
	game.player.global_position = projected + Vector3.UP * 50.0
	var count: int = game.alive_zombies()
	check(not game.spawn_zombie("shambler", point, 1.0, "north", Waves.SPAWN_DISTANCE), "Height cannot bypass horizontal player clearance")
	check(game.alive_zombies() == count, "Rejected spawn does not create or count an enemy")
	check(game.waves._try_spawn({"type": "shambler", "lane": "north"}), "Occupied entrance falls back to a safe spawn")
	var zombie: Zombie = game.zombies_root.get_children().back()
	var offset: Vector3 = zombie.global_position - game.player.global_position
	check(Vector2(offset.x, offset.z).length() >= Waves.SPAWN_DISTANCE, "Final navigation-projected spawn respects clearance")
	zombie.set_physics_process(false)
	var saved_spawns: Dictionary = Map.SPAWNS
	Map.SPAWNS = {"north": [point]}
	game.waves.queue = [{"type": "shambler", "lane": "north"}]
	game.waves.phase = "spawning"
	game.waves.spawn_t = 0.0
	count = game.alive_zombies()
	game.waves._process(0.01)
	check(game.waves.queue.size() == 1 and game.alive_zombies() == count, "Fully blocked entrances retain the queued enemy")
	check(game.waves.spawn_t == Waves.SPAWN_RETRY_DELAY, "Blocked wave retries with a delay")
	game.player.global_position = projected + Vector3(80, 0, 0)
	game.waves._process(Waves.SPAWN_RETRY_DELAY)
	check(game.waves.queue.is_empty() and game.alive_zombies() == count + 1, "Waiting enemy spawns once the entrance clears")
	Map.SPAWNS = saved_spawns
	point = Waves.TITAN_FIELDS[0]
	game.player.global_position = NavigationServer3D.map_get_closest_point(nav, Map.ground_pos(point.x, point.y))
	check(game.waves._try_spawn({"type": "titan", "lane": "east", "point": point}), "Titan uses another field when its planned entrance is occupied")
	zombie = game.zombies_root.get_children().back()
	offset = zombie.global_position - game.player.global_position
	check(zombie is Titan and Vector2(offset.x, offset.z).length() >= Waves.TITAN_SPAWN_DISTANCE, "Titan keeps its larger safety distance")
	# Exercise the host's actor list with a remote player at the entrance.
	var remote := Player.new()
	remote.remote_actor = true
	game.add_child(remote)
	remote.set_physics_process(false)
	remote.global_position = projected
	game.player.global_position = projected + Vector3(80, 0, 0)
	NetSession.world.actors[2] = remote
	NetSession.enabled = true
	point = Map.SPAWNS["north"][0]
	check(not game.spawn_zombie("shambler", point, 1.0, "north", Waves.SPAWN_DISTANCE), "Remote living player blocks spawning even when the host is far away")
	remote.alive = false
	check(game.spawn_zombie("shambler", point, 1.0, "north", Waves.SPAWN_DISTANCE), "Dead players do not permanently block an entrance")
	NetSession.enabled = false
	NetSession.world.actors.erase(2)
	remote.queue_free()
	print("SPAWN_SAFETY_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
