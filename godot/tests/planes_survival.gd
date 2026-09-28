extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>300000:
		print("FAIL: Planes survival timeout")
		quit(1)
	return false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)
func clear_enemies() -> void:
	for node in game.zombies_root.get_children(): node.queue_free()
	await process_frame
	await physics_frame
func press_pause() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	root.push_input(event)
	await process_frame
	event.pressed = false
	root.push_input(event)
func run() -> void:
	game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	check(not game.survival_active and game.weapons==null,"Entry remains peaceful exploration")
	await game.start_survival()
	check(game.survival_active and game.player.active and game.waves!=null,"Survival starts explicitly after loading")
	await process_frame
	check(game.hud.cross.get_global_rect().get_center().distance_to(root.get_visible_rect().get_center())<20 and game.hud.health_text.get_global_rect().position.y>root.size.y*0.6,"Combat HUD anchors the crosshair centrally and health above the bottom edge")
	check(game.nav_region.navigation_mesh.get_polygon_count()>100,"Surveyed terrain has a connected navigation mesh")
	check(game.progression==null and game.get("defences")==null and get_nodes_in_group("barricade").is_empty(),"No quests, NPCs, towers or barricades are created")
	if not game.survival_active:
		quit(1)
		return
	game.waves.set_process(false)
	var slots_ok := true
	for slot in [[KEY_1,"pistol"],[KEY_3,"shotgun"],[KEY_2,"ak47"]]:
		var key := InputEventKey.new()
		key.physical_keycode = slot[0]
		key.pressed = true
		root.push_input(key)
		await process_frame
		key.pressed = false
		root.push_input(key)
		slots_ok = slots_ok and game.weapons.current==slot[1]
	check(slots_ok,"Physical keys 1, 2 and 3 select the available guns")
	var spawns_ok := true
	for i in 10:
		var enemy: Zombie = game.spawn_enemy("runner",1)
		print("SPAWN ",i," ",enemy.position if enemy else "unavailable")
		spawns_ok = spawns_ok and enemy!=null
		if enemy: spawns_ok = spawns_ok and enemy.position.distance_to(game.player.position)>27
	check(spawns_ok,"Enemies spawn on reachable terrain at least 28 m away")
	await clear_enemies()
	# A real actor must descend the surveyed route and damage the player.
	var at: Vector3 = game.player.position+Vector3(8,0,0)
	at = Map.ground_pos(at.x,at.z)
	var chaser: Zombie = game.create_enemy("runner",at,1)
	var distance := chaser.position.distance_to(game.player.position)
	for i in 150: await physics_frame
	check(chaser.position.distance_to(game.player.position)<distance-2,"Zombie pathfinding advances towards the player")
	for i in 180:
		if game.player.hp<game.player.max_hp: break
		await physics_frame
	check(game.player.hp<game.player.max_hp,"A zombie reaches and damages the player")
	await clear_enemies()
	if game.player.downed: game.player.revive(game.player.max_hp)
	game.player.hp = game.player.max_hp
	game.set_view(0)
	for i in 8: await physics_frame
	var forward: Vector3 = -game.player.camera.global_basis.z
	var aim_at: Vector3 = game.player.position+forward*5
	aim_at = Map.ground_pos(aim_at.x,aim_at.z)
	var target: Zombie = game.create_enemy("shambler",aim_at,1)
	target.set_physics_process(false)
	for i in 5: await physics_frame
	game.player.camera.look_at(target.position+Vector3.UP*1.15)
	game.weapons.spread_mul = 0.0
	var old_hp := target.hp
	var old_ammo: int = game.weapons.cur().ammo
	game.weapons._switch_t = 0
	game.weapons.try_fire()
	check(game.weapons.cur().ammo==old_ammo-1 and target.hp<old_hp,"Actual firearm ray hits an enemy and consumes ammunition")
	game.weapons.reload()
	for i in 240: await physics_frame
	check(game.weapons.cur().ammo==game.weapons.cur().def.mag,"Reload restores the magazine")
	game.player.camera.rotation = Vector3.ZERO
	await clear_enemies()
	# Pause must freeze live world state, including grenades attached to the root.
	game.weapons.throw_grenade()
	await physics_frame
	var grenade: Grenade
	for child in game.get_children():
		if child is Grenade: grenade = child
	game.waves.set_process(true)
	await press_pause()
	var timer: float = game.waves.timer
	var weather_time: float = game.weather.elapsed
	var fuse := grenade._t if grenade else -1.0
	await create_timer(0.3,true).timeout
	check(paused and game.menu.visible and grenade!=null and grenade._t==fuse and game.waves.timer==timer and game.weather.elapsed==weather_time,"Escape pauses grenades, weather and the wave countdown")
	await press_pause()
	check(not paused and game.player.active,"Escape resumes the survival run")
	game.waves.set_process(false)
	var blast_target: Zombie = game.create_enemy("shambler",Map.ground_pos(game.player.position.x+15,game.player.position.z),1)
	for i in 2: await physics_frame
	grenade.position = blast_target.position+Vector3.UP
	grenade._explode()
	check(not blast_target.alive,"Grenade explosion damages enemies without Forest subsystems")
	await clear_enemies()
	game.player.damage(10000)
	check(game.player.downed,"Lethal damage enters the downed state")
	game.player.self_revive()
	check(not game.player.downed and game.player.alive and game.player.self_revives==0,"Self revive returns to combat")
	# All 25 real controller transitions, accelerated by removing queued test actors.
	# Each wave still spawns and kills an actual zombie before it can complete.
	var plans_ok := true
	var transitions_ok := true
	for number in range(1,26):
		game.waves.start(number)
		if game.waves.queue.is_empty():
			transitions_ok = false
			break
		plans_ok = plans_ok and game.waves.total==roundi((10+number*4)*game.difficulty.count)
		if number%5==0: plans_ok = plans_ok and game.waves.queue.has("brute")
		game.waves.complete_wave()
		transitions_ok = transitions_ok and game.waves.completed==number-1
		var actor: Zombie = game.spawn_enemy(game.waves.queue[0],number)
		if not actor:
			transitions_ok = false
			break
		game.waves.queue.clear()
		game.waves.complete_wave()
		transitions_ok = transitions_ok and game.waves.completed==number-1
		actor.damage(100000,Vector3.UP)
		game.waves.complete_wave()
		transitions_ok = transitions_ok and game.waves.completed==number
		await process_frame
	check(plans_ok,"All 25 wave plans scale correctly with a brute wave every fifth round")
	check(transitions_ok,"Waves wait for queued and living enemies; all 25 completion transitions work")
	check(game.victory and game.over and game.waves.phase=="complete" and game.campaign.cleared("planes"),"Wave 25 ends the run and records only Planes as secured")
	game.waves.start(26)
	check(game.waves.wave==25 and not game.campaign.cleared("forest"),"There is no wave 26 or Forest progress leakage")
	await game.start_survival()
	game.waves.set_process(false)
	check(not game.over and not game.victory and game.alive_zombies()==0 and game.waves.wave==0,"Retry resets enemies, equipment and the wave controller")
	for spec in [[0,"clear"],[270,"fog"],[450,"rain"],[690,"storm"],[840,"clear"]]:
		game.weather.elapsed = spec[0]
		check(game.weather.scheduled_state(0)==spec[1],"Weather schedule: "+str(spec[1]))
	game.weather.force("rain")
	for i in 90: game.weather._process(0.2)
	check(game.weather._rain.emitting and game.weather.wetness>0.1,"Rain particles and wet ground become active")
	game.weather.force("storm")
	game.weather._next_bolt = 0
	game.weather._process(0.2)
	check(game.weather.lightning_serial>0 and game.weather.flash>0,"Storm produces lightning and a queued thunder cue")
	game.weather.force("clear")
	for i in 150: game.weather._process(0.2)
	check(not game.weather._rain.emitting and game.weather.intensity==0,"Clear weather fades out rain")
	game.player.damage(10000)
	game.player._bleed_out()
	check(game.over and not game.victory and paused,"Bleeding out ends and pauses the run")
	# Leave deferred gore effects alive before the scene change; their callbacks
	# must disconnect or resolve weak references after their owners disappear.
	var residual: Zombie = game.create_enemy("shambler",game.player.position+Vector3(4,0,0),1)
	residual.sever("LeftArm",Vector3.RIGHT)
	game.stop_survival()
	await process_frame
	check(not paused and game.player.active and not game.survival_active and game.waves==null and game.alive_zombies()==0 and not game.hud.health_text.visible and not game.hud.overlay.visible,"Return to exploration clears combat readouts while preserving shared pause menus")
	check(game.weapons.viewmodel.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Exploration stops the unused weapon render pass")
	game._pause()
	check(paused and game.menu.visible,"Focus-loss pause uses the Planes menu")
	game.set_menu(false)
	var old_id := game.get_instance_id()
	game.return_to_map()
	while current_scene==null or current_scene.get_instance_id()==old_id: await process_frame
	game = current_scene
	while not game.navigation_ready: await process_frame
	check(Map.active_region=="forest" and game.hud.map_selection.visible and game.hud.map_selection._selected.is_empty() and not game.started,"Leaving a completed survival session restores Forest and an unselected campaign map")
	print("PLANES_SURVIVAL_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
