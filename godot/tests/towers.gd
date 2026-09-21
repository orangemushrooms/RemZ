extends SceneTree

var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_dt: float) -> bool:
	if Time.get_ticks_msec()-began>180000: quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ",description)
	else:
		failures += 1
		push_error("FAIL: "+description)

func settle() -> void:
	await physics_frame
	await physics_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	var defence: DefenceSystem = game.defences
	defence.set_process(false)
	var player: Player = game.player
	var point := Map.ground_pos(60,112)
	player.score = 10000
	for kind in DefenceTower.TYPES:
		player.global_position = Map.ground_pos(60,115)+Vector3.UP*0.1
		await settle()
		var before := player.score
		check(defence.purchase(player,point,0.0,kind).is_empty(),kind+" builds on a valid site")
		check(player.score==before-int(DefenceTower.SPECS[kind].cost),kind+" charges its advertised price")
		var tower: DefenceTower = defence.towers.values()[0]
		tower.set_physics_process(false)
		check(tower.kind==kind and tower.hp==tower.max_hp(),kind+" starts with correct type and health")
		check(ResourceLoader.exists("res://assets/models/tower_%s.glb" % kind) and tower.gun.has_node("WeaponModel"),kind+" uses its generated Meshy model")
		await settle()
		check(defence.mount(player,tower.tower_id).is_empty() and player.mounted_tower==tower.tower_id,kind+" can be mounted")
		check(player.global_position.distance_to(tower.seat_position())<0.01 and tower.operator_peer==player.peer_id,kind+" places operator on platform")
		var shots := tower.shots
		tower._physics_process(0.1)
		check(tower.shots==shots,kind+" does not automatically fire while occupied")
		var ammo: int = game.weapons.cur().ammo
		var grenades: int = game.weapons.grenades
		game.weapons.try_fire()
		game.weapons.throw_grenade()
		check(game.weapons.cur().ammo==ammo and game.weapons.grenades==grenades,"Personal weapons are blocked while operating "+kind)
		defence.control(player,tower.tower_id,NAN,0.0,true)
		check(not tower.trigger,"Nonfinite aim is rejected for "+kind)
		var hip_spread := tower.manual_spread()
		defence.input_grace = 0
		Input.action_press("aim")
		for frame in 30:
			defence._process(1.0/60.0)
			game.weapons._handle_weapon_input(1.0/60.0)
		check(tower.aiming and player.camera.fov < 56 and player.camera.fov >= 55,kind+" right mouse smoothly zooms without personal scope overriding it")
		check(is_equal_approx(tower.manual_spread(), hip_spread*0.25),kind+" aimed shots use a 75 percent tighter cone")
		Input.action_release("aim")
		for frame in 30: defence._process(1.0/60.0)
		check(not tower.aiming and player.camera.fov > 74.9,kind+" releasing right mouse restores view and normal precision")
		Input.action_press("aim")
		defence._process(0.5)
		player.active = false
		defence._process(0.1)
		check(not tower.aiming and is_equal_approx(player.camera.fov,75.0),kind+" menus stop aiming and restore view")
		player.active = true
		Input.action_release("aim")
		# Exercise the actual camera ray, muzzle ray and shell destination with identical random samples.
		defence.control(player,tower.tower_id,0.0,0.55,false)
		tower._physics_process(1.0)
		var nominal: Vector3 = player.camera.global_position-player.camera.global_basis.z*tower.attack_range()
		var centered := tower.muzzle.global_position.direction_to(nominal)
		seed(142)
		defence.control(player,tower.tower_id,0.0,0.55,true,false)
		tower.cooldown = 0
		tower._physics_process(0.01)
		var hip_error := tower.muzzle.global_position.direction_to(tower.last_impact).distance_to(centered)
		seed(142)
		defence.control(player,tower.tower_id,0.0,0.55,true,true)
		tower.cooldown = 0
		tower._physics_process(0.01)
		var aimed_error := tower.muzzle.global_position.direction_to(tower.last_impact).distance_to(centered)
		check(hip_error>0.0001 and aimed_error<hip_error*0.4,kind+" precision reduces actual shot deviation at the same aim and random sample")
		tower.cooldown = 0
		defence.control(player,tower.tower_id,0.0,-0.25,true,true)
		tower._physics_process(0.05)
		check(tower.shots>shots,kind+" fires using manual controls")
		tower._physics_process(0.5)
		check(not tower.trigger and not tower.aiming,kind+" stops firing and aiming when control packets stop")
		defence.control(player,tower.tower_id,PI*0.5,0.0,false)
		tower._physics_process(1.0)
		check(player.global_position.distance_to(tower.seat_position())<0.01 and absf(player.global_position.x-point.x)>0.5,kind+" operator follows the rotating weapon")
		check(not defence.rotate_tower(player,tower.tower_id,1.0).is_empty(),kind+" cannot be rotated while occupied")
		defence.control(player,tower.tower_id,PI*0.5,0.0,false,true)
		var snapshot := defence.snapshot()
		check(snapshot[tower.tower_id][10]==kind and snapshot[tower.tower_id][11]==player.peer_id,kind+" replicates type and operator")
		var replica_system := DefenceSystem.new()
		replica_system.game = game
		game.add_child(replica_system)
		replica_system.set_process(false)
		replica_system.apply_snapshot(snapshot,true)
		var replica: DefenceTower = replica_system.towers[tower.tower_id]
		check(replica.kind==kind and replica.operator_peer==player.peer_id and replica.hp==tower.hp,kind+" restores the right turret for late joiners")
		check(replica.aiming,kind+" restores aiming state for late joiners")
		replica_system.apply_snapshot({},false)
		replica_system.queue_free()
		await settle()
		defence.release_tower(tower)
		check(not tower.aiming and is_equal_approx(player.camera.fov,75.0),kind+" dismount clears aiming and zoom")
		check(player.mounted_tower==0 and tower.operator_peer==0 and player.global_position.distance_to(point)>1.8,kind+" dismounts safely")
		player.global_position = Map.ground_pos(60,115)+Vector3.UP*0.1
		check(defence.mount(player,tower.tower_id).is_empty(),kind+" can be mounted again")
		tower.damage(100000)
		check(player.mounted_tower==0,kind+" destruction releases its operator")
		await settle()
	# Exercise each distinct weapon against actual zombie hitboxes.
	var enemies: Array[Zombie] = []
	for at in [Vector2(60,102),Vector2(62,102),Vector2(65,102)]:
		game.spawn_zombie("shambler",at,1)
		var enemy: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count()-1)
		enemy.set_physics_process(false)
		enemy.agent.avoidance_enabled = false
		enemy.hp = 10000
		enemies.append(enemy)
	await settle()
	for kind in DefenceTower.TYPES:
		var tower := defence.create_tower(point,player.peer_id,0,false,kind)
		tower.set_physics_process(false)
		await settle()
		for enemy in enemies: enemy.hp = 10000
		check(tower.can_see(enemies[0]),kind+" acquires an animated body hitbox")
		tower.target = enemies[0]
		tower.shoot()
		if kind=="mortar": await create_timer(2.0,false).timeout
		check(enemies[0].hp<10000,kind+" deals actual damage")
		if kind in ["tesla","mortar","flame"]: check(enemies[1].hp<10000,kind+" hits multiple enemies")
		if kind in ["flame","tesla"]:
			var wall := StaticBody3D.new()
			wall.collision_layer = 1
			var collider := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(12,10,0.5)
			collider.shape = box
			wall.add_child(collider)
			game.add_child(wall)
			wall.global_position = Map.ground_pos(60,107)+Vector3.UP*3
			await settle()
			var hp_before := enemies[0].hp
			var neighbor_before := enemies[1].hp
			tower.fire_at(tower.target_point(enemies[0]))
			check(enemies[0].hp==hp_before and enemies[1].hp==neighbor_before,kind+" cannot damage enemies through a solid wall")
			wall.queue_free()
		tower.queue_free()
		await settle()
	# Prices and unknown types must never charge a failed purchase.
	player.global_position = Map.ground_pos(60,115)+Vector3.UP*0.1
	player.score = 120
	check(not defence.purchase(player,point,0,"tesla").is_empty() and player.score==120,"Insufficient funds reject expensive tower without charging")
	check(not defence.purchase(player,point,0,"invalid").is_empty() and player.score==120,"Unknown tower type rejected without charging")
	print("TOWERS_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
