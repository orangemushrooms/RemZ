extends SceneTree
var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_dt: float) -> bool:
	if Time.get_ticks_msec()-began > 210000: quit(1)
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",label)
func settle() -> void:
	await physics_frame
	await physics_frame
func wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	game.add_child(body)
	body.global_position = at
	return body
func point_at(drone: AttackDrone, target: Vector3) -> void:
	for i in 4:
		var dir := drone.camera.global_position.direction_to(target)
		drone.yaw = atan2(-dir.x,-dir.z)
		drone.pitch = atan2(dir.y,Vector2(dir.x,dir.z).length())
		drone.update_view()
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	var s: DroneSystem = game.drones
	s.set_process(false)
	var p: Player = game.player
	p.global_position = s.station.to_global(Vector3(0,0,1.6))
	p.rotation.y = s.station.rotation.y
	p.pitch = 0
	p.head.rotation.x = 0
	await settle()
	var station_feet := p.global_position
	check(s.nearby(p),"Station is reachable inside upper hut floor")
	game.waves.wave = 15
	game.forest_keys.owned.clear()
	check(not s.launch(p,"scout").is_empty(),"Missing hut key blocks launch")
	game.forest_keys.owned.waldhuette = true
	p.global_position.y -= 2.65
	check(not s.nearby(p) and not s.launch(p,"scout").is_empty(),"Cannot use upstairs station from garage")
	p.global_position = station_feet+Vector3(10,0,0)
	check(not s.launch(p,"scout").is_empty(),"Remote station use rejected")
	p.global_position = station_feet
	var console_cover := wall(s.station.to_global(Vector3(0,1.2,0.9)),Vector3(2,1,0.2))
	await settle()
	check(not s.nearby(p),"Console cannot be used through an intervening solid object")
	console_cover.queue_free()
	await settle()
	for kind in AttackDrone.SPECS:
		var wave: int = AttackDrone.SPECS[kind].wave
		game.waves.wave = wave-1
		check(not s.requirement(p,kind).is_empty(),kind+" locked one wave before threshold")
		game.waves.wave = wave
		check(s.requirement(p,kind).is_empty(),kind+" unlocks exactly at wave "+str(wave))
	check(not s.launch(p,"invalid").is_empty(),"Unknown drone rejected")
	var launch_blocks: Array[Node] = []
	for offset in [Vector3(0,8,-5.8),Vector3(0,10,5.8),Vector3(5.5,10,0),Vector3(-5.5,12,0)]:
		launch_blocks.append(wall(game.hut.center+offset.rotated(Vector3.UP,float(Map.BUILDINGS.waldhuette.yaw)),Vector3(3,3,3)))
	await settle()
	check(not s.spawn_position("scout").is_finite() and not s.launch(p,"scout").is_empty() and p.controlling_drone==0,"Blocked launch pads reject without taking control")
	for block in launch_blocks: block.queue_free()
	await settle()
	s.open()
	check(s.is_open and not p.active and s.buttons.size()==3 and s.launch_button.text=="Ready to fly","Station opens three-choice Ready to fly menu")
	s.selected = "scout"
	s.launch_button.pressed.emit()
	check(not s.is_open and p.controlling_drone != 0 and p.active,"Ready to fly launches and closes menu")
	var drone: AttackDrone = s.drones[p.controlling_drone]
	check(drone.motor.playing and drone.motor_start_position==0,"New launch plays recorded spin-up from beginning")
	var motor_stream := AttackDrone.motor_stream()
	check(motor_stream.format==AudioStreamWAV.FORMAT_16_BITS and motor_stream.get_length()>16 and motor_stream.loop_begin==102312,"Motor uses prepared source recording and excludes spin-up from loop")
	check(AttackDrone.motor_position(0.5)==0.5 and AttackDrone.motor_position(1000)>=AttackDrone.MOTOR_LOOP_START and AttackDrone.motor_position(1000)<motor_stream.get_length(),"Motor seek preserves intro once and wraps long flights into steady loop")
	drone.set_physics_process(false)
	check(drone.camera.current and not p.camera.current and not game.weapons.viewmodel.visible,"Flight takes camera and hides personal weapon")
	check(drone.visual.get_child(0).name.begins_with("Model_drone"),"Flight uses imported Meshy model")
	var feet := p.global_position
	Input.action_press("move_forward")
	p._physics_process(0.2)
	Input.action_release("move_forward")
	check(p.global_position==feet,"Pilot body remains at station while flying")
	var ammo: int = game.weapons.cur().ammo
	var grenades: int = game.weapons.grenades
	game.weapons.try_fire()
	game.weapons.throw_grenade()
	check(game.weapons.cur().ammo==ammo and game.weapons.grenades==grenades,"Personal shots and grenades blocked during drone flight")
	game._pause()
	var cancel := InputEventKey.new()
	cancel.physical_keycode = KEY_ESCAPE
	cancel.pressed = true
	s._input(cancel)
	check(p.controlling_drone==drone.drone_id and not s._return_pending,"Pause overlay retains normal Escape handling without recalling drone")
	game._on_start(false)
	check(p.active and drone.camera.current and not paused,"Resume keeps flight camera and re-enables control")
	s._process(0.01)
	game.defences._process(0.01)
	game.weapons._handle_weapon_input(0.01)
	check(not game.weapons.viewmodel.visible and s.reticle.visible and not game.hud.ammo_label.get_parent().visible,"Other systems cannot restore hand weapon or personal ammo during flight")
	check(not s.launch(p,"viper").is_empty(),"One pilot cannot launch a second drone")
	drone.global_position = Map.ground_pos(60,112)+Vector3.UP*8
	drone.yaw = 0
	drone.update_view()
	drone.input_timeout = 0
	s.control(p,drone.drone_id,Vector3(INF,0,0),0,0,true)
	check(drone.input_timeout==0,"Nonfinite movement rejected")
	s.control(p,drone.drone_id,Vector3.ZERO,NAN,0,true)
	check(drone.input_timeout==0,"Nonfinite aim rejected")
	s.control(p,drone.drone_id,Vector3(100,100,100),0,0,false)
	check(drone.input_move.length() <= 1.001,"Oversized movement normalized by host")
	s.control(p,drone.drone_id,Vector3.ZERO,100.0,100.0,false)
	check(absf(drone.yaw)<=PI and drone.pitch<=1.0,"Authority bounds camera angles")
	var stranger := Player.new()
	stranger.remote_actor = true
	stranger.peer_id = 123456
	game.add_child(stranger)
	stranger.controlling_drone = drone.drone_id
	var previous_input := drone.input_move
	s.control(stranger,drone.drone_id,Vector3.DOWN,0,0,true)
	check(drone.input_move==previous_input and not drone.firing,"Forged owner cannot control drone")
	stranger.queue_free()
	s.control(p,999999,Vector3.ONE,0,0,true)
	check(drone.input_move==previous_input,"Unknown drone control is ignored")
	var untouched := drone.hp
	drone.damage(NAN)
	drone.damage(-50)
	check(drone.hp==untouched,"Invalid damage never corrupts hull health")
	var before := drone.global_position
	for i in 60:
		s.control(p,drone.drone_id,Vector3(1,0,0),0,0,false)
		drone._physics_process(1.0/60)
	check(drone.global_position.x > before.x+5 and drone.global_position.distance_to(before) <= float(drone.spec().speed)+0.1,"Drone flies freely with bounded speed")
	s.control(p,drone.drone_id,Vector3.UP,0,0,true)
	drone._physics_process(0.4)
	check(not drone.firing and drone.input_move==Vector3.ZERO,"Missing control packets stop thrust and fire")
	drone.global_position = Map.ground_pos(60,112)+Vector3.UP*80
	drone.velocity = Vector3.ZERO
	drone._physics_process(0.02)
	check(drone.global_position.y<=Map.ground_height(60,112)+45.01,"Flight ceiling keeps drone in playable airspace")
	drone.global_position.x = Map.BOUNDS.end.x+10
	drone._physics_process(0.02)
	check(drone.global_position.x <= Map.BOUNDS.end.x-1,"Map boundary prevents leaving world")
	drone.heat = 1
	drone.overheated = true
	for i in 9: drone._physics_process(0.5)
	check(not drone.overheated and drone.heat<0.25,"Weapon cools and unlocks after overheating")
	drone.velocity = Vector3.ZERO
	drone.global_position = Map.ground_pos(60,112)+Vector3.UP*8
	drone.update_view()
	var block := wall(drone.global_position+Vector3(2,0,0),Vector3(0.25,5,8))
	await settle()
	var hp := drone.hp
	for i in 60:
		s.control(p,drone.drone_id,Vector3.RIGHT,0,0,false)
		drone._physics_process(1.0/60)
	check(drone.hp < hp and hp-drone.hp <= 16,"Swept obstacle collision causes light bounded damage")
	check(drone.global_position.x < block.global_position.x,"Drone cannot tunnel through wall")
	hp = drone.hp
	drone.damage(12)
	check(hp-drone.hp >= 30,"Zombie strike causes substantially heavier damage")
	block.queue_free()
	await settle()
	# Replica snapshots preserve flight state and do not replay historical shots.
	var copy := DroneSystem.new()
	game.add_child(copy)
	copy.game = game
	copy.set_process(false)
	drone.shots = 3
	copy.apply_snapshot(s.snapshot(),true)
	var replica: AttackDrone = copy.drones[drone.drone_id]
	check(replica.replica and replica.hp==drone.hp and replica.kind==drone.kind and replica.position==drone.position,"Late join reconstructs authoritative drone")
	check(not replica.shot_audio.playing,"Late join does not replay old shots")
	check(replica.motor.playing and replica.motor_start_position>=AttackDrone.MOTOR_LOOP_START,"Late join starts motor in flight loop without replaying spin-up")
	var motor_before := replica.motor_elapsed
	var saved := replica.hp
	replica.damage(50)
	replica.shoot()
	check(replica.hp==saved and replica.shots==3,"Replica cannot apply damage or generate shots")
	drone.shots += 1
	drone.shot_origin = drone.muzzle.global_position
	drone.impact = drone.shot_origin+Vector3.FORWARD*8
	copy.apply_snapshot(s.snapshot(),false)
	check(replica.motor_elapsed==motor_before,"Repeated snapshots do not restart motor playback")
	check(replica.shot_audio.playing and replica.flash.visible,"Replicated new shot has sound and muzzle flash")
	for d: AttackDrone in copy.drones.values(): d.queue_free()
	copy.queue_free()
	s.recall(p)
	check(p.controlling_drone==0 and p.camera.current and s.drones.is_empty(),"Recall restores body camera and clears ownership")
	check(p.global_position==feet and float(s.refit.scout)>0,"Recall preserves pilot position and imposes refit")
	check(not s.launch(p,"scout").is_empty(),"Refit cannot be bypassed by relaunch")
	await settle()
	# Every tier must shoot actual animated hitboxes, respect cover, and have functioning effects.
	game.spawn_zombie("shambler",Vector2(60,102),1)
	var enemy: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count()-1)
	enemy.set_physics_process(false)
	enemy.agent.avoidance_enabled = false
	await settle()
	var last_damage := 0.0
	for kind in AttackDrone.SPECS:
		var d := s.create_drone(s.next_id,kind,p.peer_id,enemy.global_position+Vector3(0,1.0,8))
		s.next_id += 1
		d.set_physics_process(false)
		enemy.hp = 10000
		await settle()
		point_at(d,enemy.global_position+Vector3.UP*1.0)
		d.shoot()
		var dealt := 10000-enemy.hp
		check(dealt > last_damage,kind+" inflicts increasing real damage per tier")
		last_damage = dealt
		check(d.shots==1 and d.flash.visible and d.tracer.visible and d.shot_audio.playing,kind+" shot produces flash tracer and positional sound")
		check(enemy.killer_peer==p.peer_id and enemy.killer_weapon=="drone",kind+" credits pilot kills correctly")
		var shot_count := d.shots
		d.shoot()
		check(d.shots==shot_count,kind+" rate limit cannot be bypassed")
		d.cooldown = 0
		d.overheated = true
		d.shoot()
		check(d.shots==shot_count,kind+" overheating prevents fire")
		d.overheated = false
		var cover := wall(enemy.global_position+Vector3(0,1,4),Vector3(5,6,0.3))
		await settle()
		d.shoot()
		check(enemy.hp==10000-dealt,kind+" cannot shoot through solid cover")
		cover.queue_free()
		s.finish(d.drone_id,false)
		await settle()
	# Real zombie attack, not just a direct damage call.
	var low := s.create_drone(s.next_id,"scout",p.peer_id,enemy.global_position+Vector3(0,0.8,-0.9))
	s.next_id += 1
	low.set_physics_process(false)
	enemy.player = p
	enemy.hunting = false
	enemy.state = "walk"
	enemy._decision_time = 0
	enemy.attack_t = 0
	enemy._stagger = 0
	await settle()
	check(enemy._choose_defence(enemy.global_position,false)==low,"Zombie acquires low exposed drone")
	for i in 65: enemy._physics_process(1.0/60)
	check(low.hp < float(low.spec().hp),"Animated zombie strike actually damages flying drone")
	s.finish(low.drone_id,false)
	await settle()
	s.refit.clear()
	p.global_position = station_feet
	check(s.launch(p,"tempest").is_empty(),"Heavy drone can launch after recall")
	var heavy: AttackDrone = s.drones[p.controlling_drone]
	heavy.damage(10000)
	check(p.controlling_drone==0 and p.camera.current and float(s.refit.tempest)==30,"Destruction restores control with 30 second rebuild")
	await settle()
	s.refit.clear()
	s.launch(p,"scout")
	p.alive = false
	s._process(0.01)
	check(p.controlling_drone==0 and s.drones.is_empty(),"Pilot death releases drone and camera")
	p.alive = true
	var shop: Progression = game.progression
	game.waves.completed = 14
	p.global_position = shop.npcs.mechanic.global_position + Vector3(0,0.1,2.3)
	p.head.rotation.x = 0
	await settle()
	var purse := p.score
	shop.transact(p,"mechanic","quest","drone_training")
	check(shop.local_data().accepted.get("drone_training",false) and p.score==purse,"Mechanic accepts flight quest without paying prematurely")
	shop.team.drone_scout_meters = 150.0
	shop.team.drone_scout_kills = 5
	shop.transact(p,"mechanic","quest","drone_training")
	check(shop.has_claim(p.peer_id,"drone_training") and p.score==purse+150,"Mechanic pays completed drone quest exactly")
	shop.transact(p,"mechanic","quest","drone_training")
	check(p.score==purse+150,"Repeated drone quest turn-in cannot duplicate reward")
	game.queue_free()
	await settle()
	print("DRONES_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
