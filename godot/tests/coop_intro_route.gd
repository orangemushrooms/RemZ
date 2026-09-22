extends SceneTree

var game: Node3D
var role := "host"
var trace: FileAccess

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route-role="): role = arg.trim_prefix("--route-role=")
	var folder := ProjectSettings.globalize_path("res://../logs") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("../../logs")
	trace = FileAccess.open(folder.path_join("intro-route-%s.trace" % role), FileAccess.WRITE)
	create_timer(180.0).timeout.connect(func(): note("TIMEOUT"); quit(2))
	call_deferred("run")

func note(value: String) -> void:
	print(value)
	trace.store_line("%d %s" % [Time.get_ticks_msec(), value])
	trace.flush()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._flags.erase("--smoke-test") # Keep real intro, after bounded test warm-up.
	var net := root.get_node("NetSession")
	if role == "host":
		net.host("RouteHost", 24695)
		net._auto_start = 3
	else:
		net.join("127.0.0.1", role, 24695)
	note("LOBBY")
	while net.phase != "running": await process_frame
	note("RUNNING intro=%s" % game.intro.active)
	var walking := "--route-walk" in OS.get_cmdline_user_args()
	var shooting := "--route-shoot" in OS.get_cmdline_user_args()
	var shot_timer := 0.0
	var shots := 0
	game.player.set_physics_process(walking)
	var waypoints := [Intro.START]
	waypoints.append_array(Intro.WAYPOINTS)
	var waypoint := 1
	var elapsed := 0.0
	var logged := -1
	while elapsed < (100.0 if walking else 75.0):
		await process_frame
		var delta := minf(root.get_process_delta_time(), 0.1)
		elapsed += delta
		if net.phase != "running":
			note("FAIL session ended: " + net.status)
			quit(1)
			return
		if elapsed > 8.0 and waypoint < waypoints.size():
			var pos := Vector2(game.player.global_position.x, game.player.global_position.z)
			var target: Vector2 = waypoints[waypoint]
			if walking:
				var direction := target - pos
				game.player.rotation.y = atan2(-direction.x, -direction.y)
				Input.action_press("move_forward")
			else:
				pos = pos.move_toward(target, delta * 6.0)
				game.player.global_position = Map.ground_pos(pos.x, pos.y) + Vector3.UP * 0.1
			if pos.distance_to(target) < (1.5 if walking else 0.3): waypoint += 1
		else:
			Input.action_release("move_forward")
		shot_timer -= delta
		if shooting and elapsed > 12.0 and shot_timer <= 0.0:
			shot_timer = 0.4
			var target: Zombie
			var distance := INF
			for zombie: Zombie in get_nodes_in_group("shot_targets"):
				if not zombie.alive: continue
				var next: float = game.player.global_position.distance_squared_to(zombie.global_position)
				if next < distance:
					distance = next
					target = zombie
			if target:
				var camera: Camera3D = game.player.camera
				var before := camera.transform
				camera.look_at(target.global_position + Vector3.UP * target.height * 0.6)
				var weapon: Dictionary = game.weapons.cur()
				weapon.ammo = 30
				game.weapons.try_fire()
				if weapon.ammo < 30: shots += 1
				camera.transform = before
		if int(elapsed) != logged:
			logged = int(elapsed)
			note("t=%d point=%d wave=%d zombies=%d pos=%s" % [logged, waypoint, game.waves.wave, game.alive_zombies(), game.player.global_position])
		game.player.hp = game.player.max_hp
	Input.action_release("move_forward")
	var ok: bool = game.waves.wave >= 1 and waypoint == waypoints.size() and net.roster.size() == 3 and (not shooting or shots > 0)
	note("INTRO_ROUTE_DONE passed=%s role=%s shots=%d" % [ok, role, shots])
	if role == "host": await create_timer(3.0).timeout
	quit(0 if ok else 1)
