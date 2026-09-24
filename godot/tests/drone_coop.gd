extends "res://tests/multiplayer.gd"

func _initialize() -> void:
	folder = ProjectSettings.globalize_path("res://../artifacts/drone-coop/")
	super._initialize()

func host_run() -> void:
	check(NetSession.host("Host",test_port)==OK,"Drone host opens ENet socket")
	write_json("host-ready",{"port":test_port})
	while NetSession.roster.size()<2 or false in NetSession.ready_peers.values(): await wait_seconds(0.1)
	NetSession.start_game()
	game.waves.set_process(false)
	game.waves.timer = 10000
	game.player.set_physics_process(false)
	game.forest_keys.owned.waldhuette = true
	game.waves.wave = 4
	var c1 := find_peer("c1")
	var p: Player = NetSession.world.actor(c1)
	var at: Vector3 = game.drones.station.to_global(Vector3(0,0,1.6))
	await teleport(c1,at)
	await command_clients("launch",["c1"],["scout"])
	check(game.drones.drones.is_empty(),"Host rejects early remote launch")
	game.waves.wave = 5
	await command_clients("launch",["c1"],["scout"])
	check(p.controlling_drone>0 and game.drones.drones.size()==1,"Remote pilot launches through authority")
	if not p.controlling_drone:
		write_json("result",{"checks":checks,"failures":failures+1})
		quit(1)
		return
	var d: AttackDrone = game.drones.drones[p.controlling_drone]
	await command_clients("inspect",["c1"])
	var report: Dictionary = read_json("done-c1")
	check(report.piloting and report.camera and report.replica,"Client receives own drone and flight camera")
	var body_before := p.global_position
	var from := d.global_position
	await command_clients("fly",["c1"])
	check(d.global_position.distance_to(from)>0.5 and p.global_position==body_before,"Real network input moves drone but leaves pilot at console")
	check(game.progression.goal_value("drone_scout_meters")>0,"Authoritative remote flight advances quest distance")
	var input_before := d.input_move
	game.drones.control(game.player,d.drone_id,Vector3.ONE,2,1,true)
	check(d.input_move==input_before,"Another peer cannot steer the pilot's drone")
	game.player.global_position = at
	check(not game.drones.launch(game.player,"scout").is_empty(),"Team cannot duplicate an occupied drone")
	# Teleport only the test fixture, then let the remote pilot aim/fire through real input.
	d.global_position = Map.ground_pos(60,112)+Vector3.UP*1.1
	d.velocity = Vector3.ZERO
	game.spawn_zombie("shambler",Vector2(60,102),1)
	var enemy: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count()-1)
	enemy.set_physics_process(false)
	enemy.agent.avoidance_enabled = false
	enemy.hp = 1
	await wait_seconds(0.8)
	var target: Vector3 = enemy.global_position+Vector3.UP*1.0
	await command_clients("fire",["c1"],[[target.x,target.y,target.z]])
	check(d.shots>0 and not enemy.alive,"Remote drone fire damages authoritative enemy")
	check(game.progression.goal_value("drone_scout_kills")==1,"Remote fatal shot counts exactly once for drone quest")
	check(enemy.killer_peer==c1,"Network drone damage credits remote pilot")
	await command_clients("inspect",["c1"])
	report = read_json("done-c1")
	check(int(report.shots)==d.shots and report.hp==d.hp,"Client receives shots and exact hull health")
	check(report.quest_kills==1 and report.quest_meters>0,"Pilot receives authoritative quest counters")
	write_json("join-late",true)
	while NetSession.roster.size()<3 or false in NetSession.ready_peers.values(): await wait_seconds(0.1)
	await command_clients("inspect",["c2"])
	report = read_json("done-c2")
	check(report.count==1 and not report.piloting and not report.old_sound,"Late join sees active drone without taking camera or replaying gunfire")
	check(report.quest_kills==1 and report.quest_meters>0,"Late join receives drone quest progress")
	await command_clients("pause",["c1"])
	check(not paused and p.controlling_drone==d.drone_id,"Coop pause preserves flight ownership while world runs")
	game.player.alive = false
	NetSession.world._update_local_life()
	check(game.drones.drones.has(d.drone_id) and p.controlling_drone==d.drone_id,"Downed host does not recall another player's drone")
	game.player.alive = true
	NetSession.world._update_local_life()
	d.damage(10000)
	await command_clients("inspect",["c1","c2"])
	for label in ["c1","c2"]:
		report = read_json("done-"+label)
		check(report.count==0 and not report.piloting and report.player_camera,label+" receives destruction and safe camera restoration")
	game.waves.wave = 10
	await command_clients("launch",["c1"],["viper"])
	check(p.controlling_drone>0,"Second tier launches remotely at wave ten")
	await command_clients("disconnect",["c1"])
	await wait_seconds(0.8)
	check(game.drones.drones.is_empty(),"Disconnect removes abandoned drone")
	await command_clients("finish",["c2"])
	write_json("result",{"checks":checks,"failures":failures})
	print("DRONE_COOP_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

func client_run() -> void:
	while not read_json("host-ready"): await wait_seconds(0.1)
	if role=="c2":
		while not read_json("join-late"): await wait_seconds(0.1)
	check(NetSession.join("127.0.0.1",role,test_port)==OK,"Drone client connects")
	while NetSession.phase!="running" or not game.started: await wait_seconds(0.1)
	game.player.set_physics_process(false)
	game.waves.set_process(false)
	while true:
		var request = read_json("step")
		if not request is Dictionary or int(request.number)<=step_seen or not role in request.targets:
			await wait_seconds(0.05)
			continue
		step_seen = int(request.number)
		while NetSession._received_sequence<int(request.minimum_sequence): await wait_seconds(0.05)
		match request.action:
			"launch": NetSession.command("drone_launch",[request.args[0]])
			"fly":
				Input.action_press("move_forward")
				await wait_seconds(0.8)
				Input.action_release("move_forward")
			"fire":
				var d: AttackDrone = game.drones.drones.get(game.player.controlling_drone)
				var target := Vector3(request.args[0][0],request.args[0][1],request.args[0][2])
				for i in 5:
					var dir := d.camera.global_position.direction_to(target)
					game.drones._look_yaw = atan2(-dir.x,-dir.z)
					game.drones._look_pitch = atan2(dir.y,Vector2(dir.x,dir.z).length())
					await wait_seconds(0.15)
				Input.action_press("fire")
				await wait_seconds(0.65)
				Input.action_release("fire")
			"pause":
				game._pause()
				await wait_seconds(0.4)
				game._on_start()
			"disconnect","finish":
				write_json("done-"+role,{"step":step_seen})
				print("DRONE_CLIENT_DONE ",role)
				quit(0)
				return
		await wait_seconds(0.6)
		var d: AttackDrone = game.drones.drones.get(game.player.controlling_drone)
		var any: AttackDrone = game.drones.drones.values()[0] if not game.drones.drones.is_empty() else null
		write_json("done-"+role,{"quest_kills":game.progression.goal_value("drone_scout_kills"),"quest_meters":game.progression.goal_value("drone_scout_meters"),"step":step_seen,"count":game.drones.drones.size(),"piloting":game.player.controlling_drone>0,"camera":d!=null and d.camera.current,"player_camera":game.player.camera.current,"replica":d!=null and d.replica,"hp":d.hp if d else 0,"shots":d.shots if d else 0,"old_sound":any!=null and any.shot_audio.playing})
