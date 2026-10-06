extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
var releases := 0
var starts := 0
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	call_deferred("run")
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",description)
func reset_intro() -> void:
	game.waves.wave = 0
	game.waves.phase = "intro"
	game.waves.queue.clear()
	game.intro.begin()
	game.intro.phase = "walk"
	game.intro._black.hide()
	game.intro._logo.hide()
	game.intro._text.show()
	game.player.active = true
	releases = 0
	starts = 0
func move_to(point: Vector2) -> void:
	game.player.global_position = Map.ground_pos(point.x,point.y)+Vector3.UP*0.3
	game.player.velocity = Vector3.ZERO
	game.intro._process(0.016)
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	while is_instance_valid(BootScreen.find(self)): await process_frame
	game._on_start(false)
	game.player.set_physics_process(false)
	game.waves.set_process(false)
	game.intro.set_process(false)
	game.intro.road_reached.connect(func(): releases += 1)
	game.waves.wave_started.connect(func(_n): starts += 1)
	reset_intro()
	move_to(Intro.START)
	check(game.waves.wave==0 and releases==0,"Spawn does not trigger zombies")
	move_to(Intro.START+Vector2(0,15))
	check(game.waves.wave==0,"Walking away from the hut does not trigger zombies")
	move_to(Intro.START)
	game.intro._update_guidance()
	check(game.intro._dist_label.text=="87 m","Arrow distance refers to the marked junction, not the distant hut")
	check(game.intro._target_marker.visible,"The first gold destination marker is on screen from spawn")
	game._pause()
	check(not game.intro._layer.visible,"Pause menu hides the destination marker and briefing")
	game._on_start(false)
	check(game.intro._layer.visible,"Resuming restores destination guidance")
	if "--render-guidance" in OS.get_cmdline_user_args():
		game.intro._type(10)
		await create_timer(1.0).timeout
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../artifacts/intro/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder+"gold-marker.png")
	for route: Array in [[Vector2(136,70),Intro.WAYPOINTS[0]], [Vector2(110,88),Vector2(83,63)], [Vector2(60,100),Vector2(-20,75)]]:
		reset_intro()
		for point: Vector2 in route: move_to(point)
		check(game.waves.wave==1 and starts==1 and releases==1,"Road or field shortcut starts the real first wave exactly once")
		move_to(Intro.START)
		move_to(route.back())
		check(starts==1 and releases==1,"Recrossing the approach does not restart the wave")
	check(game.intro.distance_to_road(Map.ground_pos(83,63))>5,"Direct-hut regression route bypasses the old narrow road trigger")
	reset_intro()
	move_to(Vector2(136,30))
	check(game.waves.wave==1 and game.intro._wp==0,"Road approach keeps guidance at the nearby junction instead of cutting the corner")
	reset_intro()
	move_to(Vector2(83,63))
	check(game.intro._wp>0,"A field shortcut advances guidance beyond the junction behind the player")
	reset_intro()
	move_to(Intro.WAYPOINTS.back())
	check(game.waves.wave==1 and not game.intro.active,"Jumping past the line to the hut starts zombies before the intro ends")
	check(not game.intro._target_marker.visible,"Arrival removes the marker")
	# Exercise the host's actual tick with a teammate taking the shortcut.
	reset_intro()
	var world = load("res://scripts/coop_world.gd").new()
	world.game = game
	var previous_world = NetSession.world
	var previous_roster: Dictionary = NetSession.roster
	NetSession.roster = {1:"Host",2:"Guest"}
	NetSession.world = world
	NetSession.enabled = true
	# Register the actual player/weapon pairs needed by expedition wave preparation.
	world.add_player(1)
	world.add_player(2)
	var guest: Player = world.actor(2)
	guest.set_physics_process(false)
	guest.global_position = Map.ground_pos(83,63)
	world.intro_lock = 1.0
	world.tick(0.1)
	check(game.waves.wave==0,"Co-op opening card still blocks early triggers")
	world.intro_lock = 0.0
	guest.alive = false
	world.tick(0.1)
	check(game.waves.wave==0,"A dead teammate cannot start the opening wave")
	guest.alive = true
	world.tick(0.1)
	check(game.waves.wave==1 and starts==1,"Host releases wave one for a teammate's direct-hut shortcut")
	game.intro._process(0.016)
	check(game.intro._road_done and game.intro._briefing==Intro.BRIEFING_ROAD,"Host guidance advances when the teammate starts the wave")
	check(game.intro._wp==0,"Waiting host keeps the junction marker when a teammate triggers the wave")
	world.tick(0.1)
	check(starts==1,"Repeated host ticks do not restart the opening wave")
	NetSession.enabled = false
	NetSession.world = previous_world
	NetSession.roster = previous_roster
	guest.queue_free()
	print("INTRO_GUIDANCE_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
