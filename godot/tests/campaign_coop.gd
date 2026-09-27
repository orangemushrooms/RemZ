extends SceneTree
var game: Node
var role := "host"
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var folder := "res://../artifacts/campaign-coop/"
var online := false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--campaign-role="): role = arg.get_slice("=", 1)
		if arg == "--campaign-online": online = true
	if online: folder = "res://../artifacts/campaign-coop-eos/"
	call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 210000:
		print("CAMPAIGN_COOP_TIMEOUT ", role)
		quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)
func write(id: String, value: String = "ready") -> void:
	FileAccess.open(folder + id, FileAccess.WRITE).store_string(value)
func wait_for(id: String) -> void:
	while not FileAccess.file_exists(folder + id): await create_timer(0.1).timeout
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if role == "host": await host_run()
	else: await client_run()
	print("CAMPAIGN_COOP_DONE role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(1 if failures else 0)
func host_run() -> void:
	var result: int
	if online: result = await NetSession.host_online("Campaign host")
	else: result = NetSession.host("Campaign host", 24762)
	check(result == OK, "Co-op host opens")
	if result != OK: return
	if online: check(NetSession.is_online(), "Host uses the real EOS transport")
	write("ready", NetSession.join_code if online else "ready")
	while NetSession.roster.size() < 2 or false in NetSession.ready_peers.values(): await create_timer(0.1).timeout
	game.hud.primary_action()
	check(game.hud.map_selection.visible and NetSession.phase == "lobby", "Host chooses map before team launch")
	game.hud.map_selection.choose("forest")
	check(game.started and NetSession.phase == "running", "Forest launches the team")
	game.waves.set_process(false)
	game.waves.wave = 24
	game.waves.phase = "spawning"
	game.waves._complete_wave()
	await wait_for("round24")
	await host_cervids()
	game.spawn_zombie("zombie_dog", Vector2(13, 106), 1, "east")
	var dog: ZombieBeast = game.zombies_root.get_children().back()
	dog.set_physics_process(false)
	dog.agent.avoidance_enabled = false
	# Move the authoritative animal; the client must drive its rig from the
	# interpolated snapshots, without local AI or animation-state RPCs.
	while not FileAccess.file_exists(folder + "dog_running"):
		dog.position.x += 7.2 * 0.05
		dog.position.y = Map.ground_height(dog.position.x, dog.position.z)
		dog._update_animation(0.05)
		await create_timer(0.05).timeout
	dog.play("attack")
	await wait_for("dog_biting")
	dog.die(Vector3.ZERO)
	await wait_for("dog_dead")
	game.spawn_zombie("titan", Vector2(13, 106), 1, "east")
	var titan: Titan = game.zombies_root.get_children().back()
	titan.set_physics_process(false)
	titan.agent.avoidance_enabled = false
	titan.hp = titan.max_hp * 0.3
	titan.damage(1.0, Vector3.ZERO)
	await wait_for("titan_ready")
	titan.die(Vector3.ZERO)
	await wait_for("titan_dead")
	game.waves.wave = 25
	game.waves.phase = "spawning"
	game.waves._complete_wave()
	check(game.victory and NetSession.phase == "over", "Team wins after final round")
	await wait_for("victory")
	write("finish")
	await create_timer(0.8).timeout
func client_run() -> void:
	await wait_for("ready")
	var result: int
	if online: result = await NetSession.join_online(FileAccess.get_file_as_string(folder + "ready").strip_edges(), "Campaign client")
	else: result = NetSession.join("127.0.0.1", "Campaign client", 24762)
	check(result == OK, "Client joins")
	if result != OK: return
	if online: check(NetSession.is_online(), "Client joins by code over EOS")
	while not game.started or game.waves.completed < 24: await create_timer(0.1).timeout
	check(not game.victory and game.campaign.best_wave("forest") == 24, "Client saves intermediate progress without claiming victory")
	game.hud.show_map_selection()
	check(not game.hud.map_selection.visible, "Client cannot independently select a region")
	write("round24")
	await client_cervids()
	var dog: ZombieBeast
	while not dog:
		for zombie in game.zombies_root.get_children():
			if zombie is ZombieBeast and zombie.net_kind == "zombie_dog": dog = zombie
		await create_timer(0.05).timeout
	check(dog.replica and dog.anim != null and dog.model_path.ends_with("zombie_dog_animated.glb"), "Client loads the host's articulated Farmdog model")
	while dog.anim.current_animation != "run": await process_frame
	var rig := dog.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var leg := rig.find_bone("FrontLeftUpper")
	var first_pose := rig.get_bone_pose_rotation(leg)
	var swing := 0.0
	for frame in 24:
		await process_frame
		swing = maxf(swing, first_pose.angle_to(rig.get_bone_pose_rotation(leg)))
	check(dog._ground_speed > 2.0 and swing > 0.1, "Replicated displacement visibly animates the dog's leg")
	write("dog_running")
	while dog.state != "attack": await process_frame
	check(dog.anim.current_animation == "attack", "Client plays the replicated bite")
	write("dog_biting")
	while dog.alive: await process_frame
	await create_timer(0.6).timeout
	check(not dog.anim.is_playing() and absf(dog.model.rotation.z) > 1.5, "Client dog stops running and falls on death")
	write("dog_dead")
	var titan: Titan
	while not titan:
		for zombie in game.zombies_root.get_children():
			if zombie is Titan and zombie.crawling: titan = zombie
		await create_timer(0.1).timeout
	await create_timer(0.6).timeout
	check(titan.replica and titan.alive and titan.crawling, "Client receives the living titan's final phase")
	write("titan_ready")
	while titan.alive: await process_frame
	check(titan.anim.is_playing(), "Replicated death starts an active collapse")
	await create_timer(2.8).timeout
	for bone: String in ["Hips", "Head"]:
		var point := titan.skeleton.to_global(titan.skeleton.get_bone_global_pose(titan.skeleton.find_bone(bone)).origin)
		check(point.y - Map.ground_height(point.x, point.z) < titan.height * 0.16, "Client corpse rests on the terrain: " + bone)
	check(not game.hud.menu_map._crows.playing and not game.hud.map_selection.atlas._crows.playing, "Client has no map crow playback during gameplay")
	write("titan_dead")
	while not game.over: await create_timer(0.1).timeout
	check(game.victory and game.waves.phase == "complete", "Client receives successful outcome")
	check(game.campaign.cleared("forest"), "Client records Forest completion locally")
	check(game.hud.overlay.visible and not game.hud.overlay_button.disabled and Lang.text(game.hud.overlay_title.text) == "REGION SECURED", "Client sees victory with an enabled map return")
	write("victory")
	await wait_for("finish")

func host_cervids() -> void:
	var animals: Array = NetSession.world.deer.slice(0, 2)
	for animal: Deer in animals:
		animal.set_physics_process(false)
		animal.state = "flee"
	game.spawn_zombie("zombie_stag", Vector2(13, 106), 1, "east")
	var stag: ZombieBeast = game.zombies_root.get_children().back()
	stag.set_physics_process(false)
	stag.agent.avoidance_enabled = false
	stag._charge_t = 1.0
	while not FileAccess.file_exists(folder + "cervids_running"):
		for animal: Deer in animals:
			animal.position.x += (10.8 if animal.kind == "stag" else 9.0) * 0.05
			animal.position.y = Map.ground_height(animal.position.x, animal.position.z)
		stag.position.x += 11.5 * 0.05
		stag.position.y = Map.ground_height(stag.position.x, stag.position.z)
		stag._update_animation(0.05)
		await create_timer(0.05).timeout
	for animal: Deer in animals: animal.state = "graze"
	stag.die(Vector3.ZERO)
	await wait_for("cervids_stopped")

func leg_swing(model: Node3D) -> float:
	# First finish the 0.28 s graze/run blend, then sample a complete cycle.
	# A fixed frame count is too short when settings raise the render FPS.
	await create_timer(0.35).timeout
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var joint := rig.find_bone("Knee3")
	var first_pose := rig.get_bone_pose_rotation(joint)
	var bend := 0.0
	var elapsed := 0.0
	while elapsed < 0.6:
		await process_frame
		elapsed += root.get_process_delta_time()
		bend = maxf(bend, first_pose.angle_to(rig.get_bone_pose_rotation(joint)))
	return bend

func client_cervids() -> void:
	var animals: Array = NetSession.world.deer.slice(0, 2)
	for animal: Deer in animals:
		while animal.state != "flee" or animal.animation.current_animation != "run": await process_frame
		var bend := await leg_swing(animal.model)
		check(animal._ground_speed > 3.0 and bend > 0.4, "EOS %s bends its legs while fleeing (speed %.2f, bend %.2f)" % [animal.kind, animal._ground_speed, bend])
	var stag: ZombieBeast
	while not stag:
		for zombie in game.zombies_root.get_children():
			if zombie is ZombieBeast and zombie.net_kind == "zombie_stag": stag = zombie
		await process_frame
	while stag.anim.current_animation != "run": await process_frame
	var bend := await leg_swing(stag.model)
	check(stag.replica and stag._ground_speed > 3.0 and bend > 0.4, "EOS zombie stag bends its legs while charging (speed %.2f, bend %.2f)" % [stag._ground_speed, bend])
	write("cervids_running")
	for animal: Deer in animals:
		while animal.animation.current_animation != "graze": await process_frame
		check(animal._ground_speed < 0.15, "EOS %s stops stepping when stationary" % animal.kind)
	while stag.alive: await process_frame
	await create_timer(0.6).timeout
	check(not stag.anim.is_playing() and absf(stag.model.rotation.z) > 1.5, "EOS zombie stag stops its gait on death")
	write("cervids_stopped")
