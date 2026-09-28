extends SceneTree
var role := "host"
var game: Node
var checks := 0
var failures := 0
var folder := "res://../artifacts/planes-coop-late/"
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>600000: print("FAIL: PLANES_LATE_TIMEOUT"); quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",description)
func mark(id: String) -> void: FileAccess.open(folder+id,FileAccess.WRITE).store_string("ready")
func wait_file(id: String) -> void:
	while not FileAccess.file_exists(folder+id): await create_timer(0.2).timeout
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-role="): role=arg.trim_prefix("--test-role=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var late := role in ["c2","c3"]
	if late: set_meta("planes_lobby",true)
	game=load("res://scenes/planes.tscn" if late else "res://scenes/main.tscn").instantiate()
	root.add_child(game); current_scene=game
	while not game.navigation_ready: await process_frame
	if role=="host":
		check(NetSession.host("Field host",24732)==OK,"Forest lobby opens")
		mark("host")
		while NetSession.ready_peers.size()<2 or false in NetSession.ready_peers.values(): await create_timer(0.2).timeout
		while not NetSession.class_roster.values().all(func(c): return c.locked): await create_timer(0.2).timeout
		NetSession.select_region("planes")
	else:
		await wait_file("late" if late else "host")
		check(NetSession.join("127.0.0.1",role,24732)==OK,"Client joins lobby")
	while NetSession.phase!="running" or not NetSession.game or not NetSession.game.started: await create_timer(0.2).timeout
	game=NetSession.game
	check(game.campaign.selected_id=="planes","Lobby transfers the team to Planes")
	if role=="host":
		game.waves.set_process(false)
		game.waves.start(7)
		game.defences.create_tower(Map.ground_pos(-100,55),1)
		game.day_night.set_time_hours(23)
		mark("late")
		await wait_file("ready-c2"); await wait_file("ready-c3")
		check(NetSession.world.actors.size()==4 and NetSession.ready_peers.values().all(func(ready): return ready),"Four players share the same running Planes session")
		var c3: int = 0
		for peer in NetSession.roster:
			if NetSession.roster[peer]=="c3": c3=peer
		mark("disconnect")
		while NetSession.roster.has(c3): await create_timer(0.2).timeout
		check(NetSession.world.actors.size()==3 and not game.over,"A disconnect removes the actor and preserves the remaining team")
		mark("done")
		await wait_file("done-c1"); await wait_file("done-c2")
	else:
		await create_timer(1).timeout
		if late:
			check(game.waves.wave==7 and game.defences.towers.size()==1,"Late join receives the existing wave and tower")
			check(game.day_night.is_night() and CharacterProfile.context=="match","Late join receives the world clock and starts its class session")
			mark("ready-"+role)
		if role=="c3":
			await wait_file("disconnect")
		else:
			await wait_file("done")
			mark("done-"+role)
	print("PLANES_LATE_DONE role=%s checks=%d failures=%d" % [role,checks,failures])
	quit(1 if failures else 0)
