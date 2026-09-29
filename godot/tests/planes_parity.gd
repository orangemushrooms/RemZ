extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>480000: quit(1)
	return false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)
func go(at: Vector3) -> void:
	game.player.position = at+Vector3.UP*0.1
	game.player.velocity = Vector3.ZERO
	game.player.reset_physics_interpolation()
func capture(name: String) -> void:
	if "--render-parity" not in OS.get_cmdline_user_args(): return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/planes/parity/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+name+".png")
func view(at: Vector3, target: Vector3) -> void:
	go(at)
	game.player.camera.look_at(target)
	game.player.rotation.y = game.player.camera.global_rotation.y
	game.player.pitch = game.player.camera.global_rotation.x
	game.player.camera.rotation = Vector3.ZERO
	game.player.head.rotation.x = game.player.pitch
func run() -> void:
	CharacterProfile.persist = false
	game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game); current_scene = game
	while not game.ready_for_exploration: await process_frame
	game.waves.set_process(false)
	game.player.hp = 100000
	check(not game.hud.crosshair_parts.is_empty(),"Forest reticle is active")
	check(game.quickbar.bindings==["pistol","","","","","","","","grenade","knife"],"Fresh quickbar contains only owned starter items")
	check(game.hunting.animals.size()>=38,"Fourteen deer/stags and twenty-four birds are huntable")
	check(game.brewing.kettles.size()>0 and game.hunting.grill_food!=null,"Camp has a cooking grate and brewing pot")
	var economy = game.progression
	go(Map.ground_pos(22,5))
	economy.open_field("camp")
	check(economy.is_open and economy.page=="Trade" and economy._tabs.Sell.visible,"Vendor uses Forest trading and selling tabs")
	check(is_instance_valid(economy._greeting) and economy._greeting.playing,"Vendor greeting audio starts when approached")
	await capture("vendor")
	economy.close()
	go(Map.ground_pos(27,15))
	economy.open_field("mechanic")
	check(economy.is_open and economy.page=="Quests" and economy._tabs.Barricades.visible,"Mechanic opens quests and offers a separate barricade tab")
	check(is_instance_valid(economy._greeting) and economy._greeting.playing,"Mechanic greeting audio starts when approached")
	economy.page = "Barricades"
	economy.refresh_field()
	check(economy._row_nodes.size()==2,"Barricade tab displays both build kits")
	await capture("mechanic")
	economy.close()
	var old_flowers: int = game.brewing.stock(game.player.peer_id).flowers.get("golden_yarrow",0)
	go(Map.ground_pos(economy.collectibles[0].at.x,economy.collectibles[0].at.y))
	check(economy.collect(0) and int(game.brewing.stock(game.player.peer_id).flowers.get("golden_yarrow",0))==old_flowers+1,"Picking a named flower supplies real brewing inventory")
	check(Sfx._voices.get("mushroom_pickup",[]).any(func(voice): return is_instance_valid(voice) and voice.playing),"Plant pickup plays its collection sound")
	var animal: Node3D = game.hunting.animals[0]
	animal.show()
	check(game.hunting.hit(animal,200,game.player.peer_id) and game.hunting.health[0]==0 and game.hunting.drops.has(0),"Shooting a deer leaves collectable meat")
	go(game.hunting.drops[0].position)
	game.hunting.transact(game.player,"collect",0)
	check(game.hunting.stock(game.player.peer_id).raw_meat>0,"Meat is added to the hunter's inventory")
	go(game.grill_position+Vector3(0,0,2))
	game.hunting.transact(game.player,"cook")
	game.hunting._process(6.1)
	check(game.hunting.stock(game.player.peer_id).cooked_meat==1,"Collected venison cooks on the camp grill")
	game.brewing.add_flower(game.player.peer_id,"golden_yarrow")
	game.brewing.transact(game.player,"brew","brew_meadow")
	game.brewing.advance_jobs(4.1)
	check(game.brewing.stock(game.player.peer_id).drinks.get("brew_meadow",0)==1,"Collected flowers brew into Meadow Tea at the pot")
	game.player.hp = 25
	game.brewing.transact(game.player,"drink","brew_meadow")
	check(game.player.hp==70 and game.brewing.stock(game.player.peer_id).drinks.brew_meadow==0,"Tea consumption heals and consumes exactly one drink")
	game.player.hp = 100000
	game.inventory.open()
	await capture("inventory")
	game.inventory.close()
	var range_house = game.shooting_range
	check(range_house.targets.size()==6,"All six surveyed targets have individual hit volumes")
	check(preload("res://scripts/planes_boundary.gd").contains(range_house.CENTER),"Playable boundary includes shooting house")
	check(not game.landscape.has_node("Building_118083383"),"Generic solid building proxy is removed")
	view(range_house.house.to_global(Vector3(-7,0,17)),range_house.house.global_position+Vector3.UP*1.4)
	await capture("shooting-house")
	go(range_house.house.to_global(Vector3(-0.8,0,4.5)))
	range_house.transact(game.player,"door")
	check(not range_house.opened,"Shooting house is locked before finding a key")
	for attempt in 32:
		if range_house.key_spawned: break
		range_house.roll_key()
	range_house.refresh()
	go(Map.ground_pos(range_house.key.position.x,range_house.key.position.z+1.3))
	await physics_frame
	range_house.transact(game.player,"key")
	check(range_house.key_owned and range_house.key.taken,"Random woodland key can be picked up from its stump")
	go(range_house.house.to_global(Vector3(-0.8,0,4.5)))
	range_house.transact(game.player,"door")
	check(range_house.opened and range_house.door.collision_layer==0,"Key opens the physical door and shooting shutters")
	var approach: Vector3 = range_house.house.to_global(Vector3(-0.8,0,7))
	go(Map.ground_pos(approach.x,approach.z))
	game.player.rotation.y = range_house.house.rotation.y
	Input.action_press("move_forward")
	for frame in 180:
		if range_house.house.to_local(game.player.position).z<2.7: break
		await physics_frame
	Input.action_release("move_forward")
	check(range_house.house.to_local(game.player.position).z<2.7,"Player can walk up the steps and through the unlocked doorway")
	go(range_house.board.global_position-Vector3.UP*1.5)
	range_house.transact(game.player,"quest")
	check(range_house.data(game.player.peer_id).accepted,"Shooting log starts personal sniper challenge")
	for id in range_house.LOOT:
		go(range_house.loot_nodes[id].global_position-Vector3.UP*0.9)
		range_house.transact(game.player,id)
		check(game.weapons.unlocked[id] and range_house.picked.has(id),"House contains one %s" % id)
	var hits := 0
	for target in range_house.targets:
		var index: int = target.get_meta("range_target")
		var origin: Vector3 = range_house.house.to_global(Vector3(-7.7+(index+0.5)*15.4/6,1.55,-1.6))
		var q := PhysicsRayQueryParameters3D.create(origin,target.global_position,Zombie.SHOT_MASK,[game.player.get_rid()])
		q.collide_with_areas = true
		await physics_frame
		var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
		print("RANGE_RAY ",index," distance=",origin.distance_to(target.position)," collider=",hit.get("collider")," at=",hit.get("position"))
		if not hit.is_empty() and hit.collider==target: hits += 1
		go(origin-Vector3.UP*1.55)
		range_house.hit(target,game.player.peer_id,"pistol")
		check(not index in range_house.data(game.player.peer_id).hits,"Non-sniper hit does not count for target %d" % index)
		range_house.hit(target,game.player.peer_id,"marksman")
	check(hits==6,"All six targets are visible through shooting ports without terrain/wall obstruction")
	view(range_house.house.to_global(Vector3(0,0,1.2)),range_house.targets[3].global_position)
	await capture("shooting-ports")
	check(range_house.data(game.player.peer_id).hits.size()==6,"Six unique sniper targets complete challenge")
	go(range_house.board.global_position-Vector3.UP*1.5)
	var money: int = game.player.score
	range_house.transact(game.player,"quest")
	check(range_house.data(game.player.peer_id).claimed and game.player.score>=money+350,"Challenge pays money and persistent class XP")
	money = game.player.score
	range_house.transact(game.player,"quest")
	check(game.player.score==money,"Challenge reward cannot be duplicated")
	go(range_house.house.to_global(Vector3(-0.8,0,1.2)))
	var intruder: Zombie = game.create_enemy("runner",Map.ground_pos(approach.x,approach.z),1)
	for frame in 600:
		if intruder.position.distance_to(game.player.position)<2.5: break
		await physics_frame
	check(intruder.position.distance_to(game.player.position)<2.5,"Zombie can follow a player through the open shooting-house entrance")
	game.discard_enemy(intruder)
	view(Map.ground_pos(13,19),game.grill_position)
	await capture("camp-cooking")
	for wave in [6,12,15,24,25]:
		var plan: Array = game.waves.plan(wave)
		check(plan.any(func(kind): return Zombie.is_boss_kind(kind) or kind=="brute"),"Wave %d includes its Forest boss encounter" % wave)
	check(Weapons.DEFS.titanbreaker.damage==840,"Titanbreaker base damage doubled")
	check(DefenceTower.SPECS.mortar.range==120,"Mortar range doubled")
	var trunk: StaticBody3D = get_nodes_in_group("planes_tree_trunks")[0]
	var start := trunk.global_position+Vector3(2,1,0)
	var trunk_ray := PhysicsRayQueryParameters3D.create(start,start-Vector3(4,0,0),1,[game.player.get_rid()])
	check(game.get_world_3d().direct_space_state.intersect_ray(trunk_ray).get("collider")==trunk,"Tree trunk blocks a physical ray through the walking height")
	go(Map.ground_pos(-70,60))
	game.progression.kit_stock.palisade = 2
	var builder = game.field_building
	var site := Vector3.ZERO
	for x in range(-78,-61,2):
		for z in range(53,67,2):
			var candidate := Map.ground_pos(x,z)
			if builder.placement_error(candidate,0).is_empty(): site=candidate; break
		if site!=Vector3.ZERO: break
	check(site!=Vector3.ZERO and builder.place("palisade",site,0).is_empty(),"First segment has a valid free build site")
	await physics_frame
	go(Map.ground_pos(site.x+1.6,site.z+4))
	var snapped: Vector3 = builder.snap(site+Vector3(3.3,0,0.2))
	check(is_equal_approx(snapped.x,site.x+3.2) and builder.place("palisade",snapped,builder.yaw).is_empty(),"Adjacent palisade snaps flush and passes real placement collision checks")
	game.progression.kit_stock.palisade = 1
	builder.begin("palisade")
	var before_yaw: float = builder.yaw
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.pressed = true
	root.push_input(wheel)
	check(not is_equal_approx(builder.yaw,before_yaw),"Mouse wheel rotates the carried palisade preview")
	builder.cancel()
	go(Map.ground_pos(-100,55))
	game.player.score = 5000
	var tower_site := Vector3.ZERO
	for x in range(-108,-91,2):
		for z in range(48,63,2):
			var candidate := Map.ground_pos(x,z)
			if game.defences.placement_error(game.player,candidate).is_empty(): tower_site=candidate; break
		if tower_site!=Vector3.ZERO: break
	game.defences.purchase(game.player,tower_site)
	var tower: DefenceTower = game.defences.towers.values()[0]
	var money_before: int = game.player.score
	go(Map.ground_pos(tower_site.x,tower_site.z+2))
	await physics_frame
	var move_key := InputEventKey.new()
	move_key.physical_keycode = KEY_Y; move_key.pressed = true
	root.push_input(move_key)
	check(game.defences.moving_tower and game.defences.rotating_id==tower.tower_id,"Y starts relocation of the nearby tower")
	var moved := Map.ground_pos(tower_site.x+5,tower_site.z)
	var move_error: String = game.defences.relocate(game.player,tower.tower_id,moved,0.7)
	check(move_error.is_empty() and tower.position.distance_to(moved)<0.01 and is_equal_approx(tower.rotation.y,0.7) and game.player.score==money_before,"Tower relocation preserves money and applies position plus chosen orientation")
	game.defences.cancel_placement()
	go(Map.ground_pos(8,19))
	game.player.revive(1)
	var hp: float = game.player.hp
	game.player.damage(40)
	check(hp>=game.player.max_hp*0.65 and game.player.hp==hp,"Revive restores substantial health and protects briefly from another hit")
	game.player.hp = 100000
	# Real movement across the fire-side dip, including exits from its bottom.
	for pair in [[Vector2(5,28),Vector2(24,4)],[Vector2(30,25),Vector2(5,2)]]:
		go(Map.ground_pos(pair[1].x,pair[1].y))
		var zombie: Zombie = game.create_enemy("runner",Map.ground_pos(pair[0].x,pair[0].y),1)
		for frame in 900:
			if zombie.position.distance_to(game.player.position)<3: break
			await physics_frame
		check(zombie.position.distance_to(game.player.position)<3,"Zombie traverses the camp depression: %s" % pair[0])
		game.discard_enemy(zombie)
	# Hit the actual bird collision volume rather than calling the deer path.
	var bird: Node3D = game.birds[0]
	bird.set_process(false)
	bird.position = Map.ground_pos(-120,110)+Vector3.UP*2
	bird.show()
	go(Map.ground_pos(-120,114))
	await physics_frame
	await physics_frame
	var bird_center := bird.global_position+Vector3.UP*0.22
	var bird_ray := PhysicsRayQueryParameters3D.create(bird_center+Vector3(0,0,2),bird_center-Vector3(0,0,2),Zombie.HITBOX_LAYER)
	bird_ray.collide_with_areas = true
	var bird_hit := game.get_world_3d().direct_space_state.intersect_ray(bird_ray)
	check(not bird_hit.is_empty() and game.hunting.hit(bird_hit.collider,100,game.player.peer_id) and bird.get_meta("hunted_dead",false),"A physical shot ray hits and kills a crow")
	# An enemy beyond the old 6 m radius is hit; one beyond 12 m is not.
	go(Map.ground_pos(-220,158))
	var near_blast: Zombie = game.create_enemy("shambler",Map.ground_pos(-211,140),1)
	var far_blast: Zombie = game.create_enemy("shambler",Map.ground_pos(-205,140),1)
	for enemy in [near_blast,far_blast]:
		enemy.hp = 5000; enemy.max_hp = 5000; enemy.set_physics_process(false)
	var shell := preload("res://scripts/tower_shell.gd").new()
	shell.game = game
	shell.start = Map.ground_pos(-220,140)+Vector3.UP*3
	game.add_child(shell)
	shell.set_physics_process(false)
	await physics_frame
	shell.explode()
	check(near_blast.hp<5000 and far_blast.hp==5000,"Mortar explosion damages an enemy at 9 m and excludes one at 15 m")
	game.discard_enemy(near_blast); game.discard_enemy(far_blast)
	game.waves.phase = "idle"; game.waves.timer = 60.0
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER; enter.keycode = KEY_ENTER; enter.pressed = true
	root.push_input(enter)
	check(game.waves.timer<=0.1,"Enter shortens the actual intermission timer")
	enter.pressed = false; root.push_input(enter)
	print("PLANES_PARITY checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
