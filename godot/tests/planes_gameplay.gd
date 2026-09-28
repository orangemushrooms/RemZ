extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>300000: quit(1)
	return false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)
func go(p: Vector2) -> void:
	game.player.position = Map.ground_pos(p.x,p.y)+Vector3.UP*0.1
	game.player.velocity = Vector3.ZERO
	game.player.reset_physics_interpolation()
func run() -> void:
	game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game); current_scene = game
	while not game.ready_for_exploration: await process_frame
	check(game.progression.npcs.size()==3,"Vendor, Mechanic and woodland Secret Vendor exist")
	await game.start_survival()
	game.waves.set_process(false)
	var economy = game.progression
	var construction = game.field_building
	check(game.player.score==150 and not game.weapons.unlocked.ak47,"Pistol economy starts without free advanced weapons")
	game.player.score = 10000
	check(not economy.buy_kit("palisade").is_empty() and economy.kit_stock.palisade==0,"Remote kit purchase is rejected")
	go(economy.SITES.mechanic+Vector2(0,2))
	var money: int = game.player.score
	economy.buy_kit("palisade"); economy.buy_kit("sandbags")
	check(game.player.score==money-110 and economy.kit_stock.palisade==1 and economy.kit_stock.sandbags==1,"Mechanic sells portable kits at Forest prices")
	go(Vector2(-70,60))
	var site := Vector3.ZERO
	for x in range(-78,-61,2):
		for z in range(53,67,2):
			var candidate := Map.ground_pos(x,z)
			if construction.placement_error(candidate,0).is_empty(): site = candidate; break
		if site!=Vector3.ZERO: break
	check(site!=Vector3.ZERO,"Player can choose a build site away from the camp")
	check(not construction.place("palisade",Map.ground_pos(-50,-280),0).is_empty() and economy.kit_stock.palisade==1,"Invalid placement preserves the purchased kit")
	check(construction.place("palisade",site,0).is_empty(),"Palisade builds on valid terrain")
	check(economy.kit_stock.palisade==0 and game.barricades.size()==1,"Successful construction consumes exactly one kit")
	check(not construction.place("palisade",site,0).is_empty() and game.barricades.size()==1,"Empty inventory cannot duplicate fortifications")
	var bar: Barricade = game.barricades[0]
	check(bar.level==1 and bar.hp==300 and bar.body.collision_layer==8,"Placed palisade has Forest health and zombie collision")
	go(Vector2(site.x,site.z+4))
	var enemy: Zombie = game.create_enemy("runner",Map.ground_pos(site.x,site.z-5),1)
	check(enemy.barricades.has(bar),"Live zombies see freely placed fortifications")
	for frame in 360:
		if bar.hp<bar.max_hp(): break
		await physics_frame
	check(bar.hp<bar.max_hp(),"A live zombie approaches and damages the player-built palisade")
	game.discard_enemy(enemy)
	bar.damage(60)
	go(Vector2(site.x,site.z+2))
	money = game.player.score
	construction.repair_nearest()
	check(bar.hp==bar.max_hp() and game.player.score==money-25,"Repair restores health and charges Forest price")
	construction.repair_nearest()
	check(game.player.score==money-25,"Full-health repair does not charge again")
	go(economy.SITES.camp+Vector2(0,2))
	economy.shop = "camp"
	economy.quest_action("welcome")
	economy.field_counts.built_wall = 2
	money = game.player.score
	economy.quest_action("welcome"); economy.quest_action("welcome")
	check(game.player.score==money+90,"Quest reward is claimed once at its giver")
	game.waves.wave = 1
	money = game.player.score
	economy.buy_weapon("ak47")
	check(game.player.score==money and not game.weapons.unlocked.ak47,"Early advanced weapon purchase is rejected")
	game.waves.wave = 4
	economy.buy_weapon("ak47")
	check(game.player.score==money-780 and game.weapons.unlocked.ak47,"Vendor sells the AK at Forest price and wave gate")
	economy.buy_weapon("ak47")
	check(game.player.score==money-780,"Owned weapon cannot be charged twice")
	economy.buy_weapon("lmg")
	check(not game.weapons.unlocked.lmg,"Rare weapons cannot be purchased at the normal vendor")
	game.weapons.state.pistol.ammo = 0
	game.weapons.state.pistol.reserve = 0
	money = game.player.score
	economy.buy_supply("ammo")
	check(game.weapons.state.pistol.ammo>0 and game.player.score<money,"Ammo refill uses paid Forest quote")
	go(economy.SITES.secret+Vector2(0,2))
	game.waves.wave = 5
	economy.buy_weapon("lmg")
	check(game.weapons.unlocked.lmg,"Secret Vendor sells advanced equipment in person")
	var item: Dictionary = economy.collectibles[0]
	go(item.at)
	check(economy.collect(0) and not economy.collect(0) and economy.field_counts.flowers==1,"A flower bundle is collected once and disappears")
	var gathered: Array[int] = []
	for woodland in [false,true]:
		var picked := -1
		for index in game.nature.plants.size():
			var plant: Dictionary = game.nature.plants[index]
			if plant.woodland!=woodland or not preload("res://scripts/planes_boundary.gd").contains(plant.at): continue
			go(plant.at)
			economy.sample_collectibles()
			if economy.nearest(game.player).is_empty() and economy.nearest_collectible<0 and economy.nearest_wild_plant==index:
				picked = index; break
		check(picked>=0,"An ordinary wild plant is reachable: woodland=%s" % woodland)
		if picked<0: continue
		var kind := "mushrooms" if woodland else "flowers"
		var previous: int = economy.field_counts.get(kind,0)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E; key.keycode = KEY_E; key.pressed = true
		root.push_input(key)
		key.pressed = false; root.push_input(key)
		check(economy.field_counts.get(kind,0)==previous+1 and game.nature._picked.has(picked),"E gathers ordinary %s and advances quest progress" % kind)
		check(not economy.collect_wild(picked),"Picked wild plant cannot be collected twice")
		var plant: Dictionary = game.nature.plants[picked]
		var mm: MultiMesh = game.nature._plant_batches[plant.group][0]
		# The headless dummy renderer always returns identity for MultiMesh transforms.
		if DisplayServer.get_name()!="headless":
			check(is_zero_approx(mm.get_instance_transform(plant.instance).basis.determinant()),"Harvest hides the existing plant instance")
		gathered.append(picked)
	go(economy.SITES.mechanic+Vector2(0,2))
	game.waves.completed = 5
	check(construction.upgrade_bar(0)=="Fortification upgraded." and bar.level==2,"Mechanic upgrades placed palisades after the wave gate")
	go(Vector2(-100,55))
	var tower_site := Vector3.ZERO
	for x in range(-108,-91,2):
		for z in range(48,63,2):
			var candidate := Map.ground_pos(x,z)
			if game.defences.placement_error(game.player,candidate).is_empty(): tower_site = candidate; break
		if tower_site!=Vector3.ZERO: break
	check(tower_site!=Vector3.ZERO and game.defences.purchase(game.player,tower_site).is_empty(),"Towers can be purchased away from merchants")
	if not game.defences.towers.is_empty():
		var tower: DefenceTower = game.defences.towers.values()[0]
		check(not game.defences.maintain(game.player,tower.tower_id,"upgrade",true).is_empty(),"Remote turret upgrade is rejected")
		go(economy.SITES.mechanic+Vector2(0,2))
		game.waves.completed = 15
		check(game.defences.maintain(game.player,tower.tower_id,"upgrade",true).is_empty() and tower.level==2,"Turret upgrades work at Mechanic")
	go(economy.SITES.mechanic+Vector2(0,2))
	money = game.player.score
	game.skills.purchase(game.player,game.weapons,"hp")
	check(game.player.max_hp==125 and game.player.score==money-200,"Mechanic training uses shared costs and updates Planes health")
	game.skills.purchase(game.player,game.weapons,"grenades")
	check(game.weapons.grenades_max==7,"Grenade pouch training increases capacity")
	game.weapons.set_weapon("pistol")
	money = game.player.score
	economy.trade_mod(game.player,"mechanic","suppressor","pistol")
	check(game.player.score==money-220 and game.weapons.mod_owned.has("pistol:suppressor"),"Weapon mods work without Forest quest prerequisites")
	go(Vector2(-70,90))
	var bag_site := Vector3.ZERO
	for x in range(-78,-61,2):
		for z in range(83,97,2):
			var candidate := Map.ground_pos(x,z)
			if construction.placement_error(candidate,0).is_empty(): bag_site = candidate; break
		if bag_site!=Vector3.ZERO: break
	check(bag_site!=Vector3.ZERO and construction.place("sandbags",bag_site,0).is_empty() and game.barricades[-1] is SandbagLine,"Sandbag kits build a real defensive line")
	go(economy.SITES.camp+Vector2(0,2))
	game.weapons.grenades = 6
	economy.buy_supply("grenade")
	check(game.weapons.grenades==7,"Supplies respect upgraded grenade capacity")
	economy.open_field("camp")
	check(economy.is_open and not game.player.active,"Trading opens a usable menu and releases mouse look")
	economy.close()
	check(game.player.active,"Closing trade returns player control")
	game.defences.planner.open()
	check(game.defences.planner.is_open and paused and game.defences.planner.overview.current,"Shared T planner opens over the player without a hut")
	game.defences.planner.close()
	check(not paused and game.player.active,"Closing T planner restores the first-person view")
	construction.open_kits()
	check(construction.kit_menu.visible and not game.player.active,"B menu lists carried kits")
	construction.cancel()
	check(game.player.active and not construction.placing,"Cancelling the kit menu preserves control and inventory")
	if "--render-gameplay" in OS.get_cmdline_user_args():
		go(Vector2(5,23)); game.player.rotation.y = -0.6
		game.player.pitch = 0.0; game.player.head.rotation.x = 0.0
		await create_timer(3).timeout
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../artifacts/planes/gameplay/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder+"camp.png")
		go(economy.SITES.mechanic+Vector2(0,2)); economy.open_field("mechanic")
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"mechanic.png")
		economy.close()
	await game.start_survival() # A live round cannot be restarted through this entry.
	game.finish_survival(false)
	await game.start_survival()
	check(game.barricades.is_empty() and game.defences.towers.is_empty() and economy.claimed.is_empty() and economy.kit_stock.palisade==0,"Retry removes structures, quests and carried kits")
	check(game.player.score==150 and not game.weapons.unlocked.lmg and not economy.collectibles[0].taken,"Retry resets economy and replenishes collectibles")
	for index in gathered:
		var plant: Dictionary = game.nature.plants[index]
		var mm: MultiMesh = game.nature._plant_batches[plant.group][0]
		check(not game.nature._picked.has(index) and not is_zero_approx(mm.get_instance_transform(plant.instance).basis.determinant()),"Retry restores harvested wild plants")
	print("PLANES_GAMEPLAY_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
