extends SceneTree
var host := false
var online := false
var game: Node
var checks := 0
var failures := 0
var folder := "res://../artifacts/planes-coop/"
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_dt: float) -> bool:
	if Time.get_ticks_msec()-began>480000: print("FAIL: PLANES_COOP_TIMEOUT"); quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",description)
func signal_file(id: String) -> void:
	FileAccess.open(folder+id,FileAccess.WRITE).store_string("ready")
func wait_file(id: String) -> void:
	while not FileAccess.file_exists(folder+id): await create_timer(0.2).timeout
func run() -> void:
	host = "--test-host" in OS.get_cmdline_user_args()
	online = "--test-online" in OS.get_cmdline_user_args()
	if online: folder = "res://../artifacts/planes-coop-online/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if host or online: set_meta("planes_lobby",true)
	game = load("res://scenes/planes.tscn" if host or online else "res://scenes/main.tscn").instantiate()
	root.add_child(game); current_scene = game
	while not game.navigation_ready: await process_frame
	if host:
		var result: int = await NetSession.host_online("Planes host") if online else NetSession.host("Planes host",24731)
		check(result==OK,"Host opens the Planes lobby")
		if result!=OK: quit(1); return
		if online: FileAccess.open(folder+"code",FileAccess.WRITE).store_string(NetSession.join_code)
		signal_file("host")
		while NetSession.ready_peers.size()<2 or false in NetSession.ready_peers.values(): await create_timer(0.2).timeout
		while not NetSession.class_roster.values().all(func(c): return c.locked): await create_timer(0.2).timeout
		NetSession.start_game()
	else:
		await wait_file("host")
		var result: int = await NetSession.join_online(FileAccess.get_file_as_string(folder+"code"),"Planes client") if online else NetSession.join("127.0.0.1","Planes client",24731)
		check(result==OK,"Client connects to the Planes host")
		if result!=OK: quit(1); return
	while NetSession.phase!="running" or not NetSession.game or not NetSession.game.started: await create_timer(0.2).timeout
	game = NetSession.game
	check(game.campaign.selected_id=="planes" and NetSession.world.actors.size()==2,"Both peers enter Planes with two players")
	await create_timer(2).timeout
	check(not paused and game.player.active,"Co-op starts without pausing the world")
	check(root.gui_get_focus_owner()==null and not game.hud.overlay.visible,"Co-op releases hidden lobby keyboard focus at round start")
	var first_step: Vector3 = game.player.global_position
	var walk_key := InputEventKey.new()
	walk_key.physical_keycode = KEY_W
	walk_key.pressed = true
	Input.parse_input_event(walk_key)
	for frame in 60: await physics_frame
	walk_key.pressed = false
	Input.parse_input_event(walk_key)
	var moved: Vector3 = game.player.global_position
	check(Vector2(first_step.x,first_step.z).distance_to(Vector2(moved.x,moved.z))>=1.0,"Local player can walk immediately after the co-op round starts")
	if online: check(NetSession.transport=="eos","Session uses the real EOS transport")
	if host:
		game.waves.set_process(false)
		game.waves.start(1)
		var enemy: Zombie = game.create_enemy("shambler",game.player.position+Vector3(12,0,0),1)
		enemy.set_physics_process(false)
		game.day_night.set_time_hours(23)
		game.weather.force("clear")
		var fires = game.cornfield.fires
		fires.set_process(false)
		var cell: Vector2i = fires.wheat.keys()[fires.wheat.size() / 2]
		fires.ignite(fires.wheat[cell], 3.5, 1, "flare_pistol")
		check(not fires.active.is_empty(), "Host ignites authoritative wheat fire")
		signal_file("state")
		await wait_file("client-state")
		check(NetSession.world.actors.size()==2,"Host retains the connected teammate")
		var charred: int = fires.burned.size()
		game.weather.force("rain")
		while not game.weather.is_raining(): await process_frame
		fires._process(0.25)
		check(fires.active.is_empty() and fires.burned.size() == charred, "Rain extinguishes host fire without restoring wheat")
		signal_file("rain-state")
		await wait_file("client-rain-state")
		fires.reset_run()
		await host_economy()
		signal_file("done")
		await wait_file("client-done")
	else:
		await wait_file("state")
		await create_timer(2).timeout
		check(game.waves.wave==1 and game.alive_zombies()==1,"Client receives wave and zombie state")
		check(game.day_night.is_night() and game.weather.state=="clear","Client receives day-night and weather state")
		var fires = game.cornfield.fires
		check(not fires.active.is_empty() and not fires.burned.is_empty(), "Client receives active fire and charred wheat from host")
		var fire_count: int = fires.burned.size()
		for cell in fires.wheat:
			if not fires.burned.has(cell):
				fires.ignite(fires.wheat[cell], 3.5, game.player.peer_id, "flare_pistol")
				break
		check(fires.burned.size() == fire_count, "Client cannot ignite unauthorised local wheat fire")
		signal_file("client-state")
		await wait_file("rain-state")
		await create_timer(1.0).timeout
		check(game.weather.state == "rain" and fires.active.is_empty() and fires.burned.size() == fire_count and fires.effects.all(func(effect): return not effect.emitting), "Client receives rain-extinguished fire and retains charred wheat")
		signal_file("client-rain-state")
		await client_economy()
		await wait_file("done")
		signal_file("client-done")
	print("PLANES_COOP_DONE host=%s checks=%d failures=%d" % [host,checks,failures])
	quit(1 if failures else 0)

func move_remote(p: Player, at: Vector3) -> void:
	p.global_position = at+Vector3.UP*0.1
	p.velocity = Vector3.ZERO
	NetSession._sequence += 1
	NetSession.send_reliable_state(p.peer_id,true)
	await create_timer(0.5).timeout

func host_economy() -> void:
	var peer: int = NetSession.roster.keys().filter(func(id): return id!=1)[0]
	var p: Player = NetSession.world.actor(peer)
	await move_remote(p,Map.ground_pos(27,15))
	signal_file("shop")
	await wait_file("bought")
	check(p.score==65 and game.player.score==150,"Client purchases debit only the buyer")
	check(game.progression.field_data(peer).kits.palisade==1 and game.progression.kit_stock.palisade==0,"Purchased kits belong to the requesting player")
	await move_remote(p,Map.ground_pos(-70,60))
	var site := Vector3.ZERO
	for x in range(-78,-61,2):
		for z in range(53,67,2):
			var candidate := Map.ground_pos(x,z)
			if game.field_building.placement_error(candidate,0,p).is_empty(): site = candidate; break
		if site!=Vector3.ZERO: break
	check(site!=Vector3.ZERO,"Remote actor has a valid field build site")
	FileAccess.open(folder+"site",FileAccess.WRITE).store_var(site)
	signal_file("build")
	await wait_file("built")
	check(game.barricades.size()==1 and game.progression.field_data(peer).kits.palisade==0,"Host creates one wall and consumes one kit despite duplicate requests")
	check(game.progression.field_data(peer).counts.get("built_wall",0)==1,"Construction advances the builder's quest progress")
	game.progression.field_data(peer).claimed.welcome = true
	game.progression.field_data(peer).counts.flowers = 6
	game.waves.wave = 1
	game.waves.completed = 1
	await move_remote(p,Map.ground_pos(22,5))
	var cash_before: int = p.score
	var host_xp_before: int = CharacterProfile.data.classes[CharacterProfile.active_class()].total_xp
	signal_file("quest")
	await wait_file("quested")
	check(game.progression.field_data(peer).claimed.get("bouquet",false) and p.score==cash_before+120,"Host validates quest and pays its owner exactly once")
	var other_xp: int = CharacterProfile.data.classes[CharacterProfile.active_class()].total_xp
	check(other_xp==host_xp_before,"Client quest does not grant host XP")
	game._clear_combat()
	game.waves.queue.clear(); game.waves.phase="spawning"; game.waves.wave=1
	game.waves.complete_wave()
	check(game.waves.completed==1,"Shared wave completes on the host")
	await move_remote(p,game.player.global_position+Vector3(1,0,0))
	p.downed = true; p.down_time = 25; p.self_revives = 0
	signal_file("revive")
	await create_timer(1).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("interact")
	await create_timer(0.7).timeout
	Input.action_release("interact")
	await create_timer(0.3).timeout
	check(p.downed and NetSession.world.revive.is_empty(),"Releasing E cancels revival before the hold completes")
	Input.action_press("interact")
	await create_timer(4).timeout
	Input.action_release("interact")
	check(not p.downed and p.alive,"Host revives the client through the shared co-op system")
	signal_file("revived")
	await wait_file("verified")
	var plant := 0
	while not preload("res://scripts/planes_boundary.gd").contains(game.nature.plants[plant].at): plant += 1
	var herb: Dictionary = game.nature.plants[plant]
	await move_remote(p,Map.ground_pos(herb.at.x,herb.at.y))
	FileAccess.open(folder+"plant",FileAccess.WRITE).store_var(plant)
	signal_file("gather")
	await wait_file("gathered")
	check(game.nature._picked.has(plant),"Host harvests a client-selected wild plant")
	check(game.progression.field_data(peer).counts.get("flowers",0)==7,"Duplicate collection grants only one flower")
	check(not game.brewing.stock(peer).flowers.is_empty(),"Client harvest becomes a real brewing ingredient on host")
	var flower_id: String = game.nature.ingredient(plant)
	var flower_before: int = int(game.brewing.stock(peer).flowers.get(flower_id,0))
	NetSession.world.mushrooms[peer].steinpilz = 1
	var sale_cash: int = p.score
	await move_remote(p,game.progression.npcs.camp.global_position)
	FileAccess.open(folder+"flower-sale-id",FileAccess.WRITE).store_var(flower_id)
	signal_file("flower-sale")
	await wait_file("flower-sold")
	check(int(game.brewing.stock(peer).flowers.get(flower_id,0))==flower_before-1 and int(NetSession.world.mushrooms[peer].steinpilz)==0 and p.score==sale_cash+game.progression.FLOWER_SELL_PRICE+Inventory.MUSHROOMS.steinpilz.sell,"Host validates client flower and mushroom sales and pays once")
	p.score = 1000
	await move_remote(p,Map.ground_pos(-100,55))
	var tower_site := Vector3.ZERO
	for x in range(-110,-90,2):
		for z in range(45,65,2):
			var candidate := Map.ground_pos(x,z)
			if game.defences.placement_error(p,candidate).is_empty(): tower_site=candidate; break
		if tower_site!=Vector3.ZERO: break
	check(tower_site!=Vector3.ZERO,"Remote player has a valid tower site")
	FileAccess.open(folder+"tower-site",FileAccess.WRITE).store_var(tower_site)
	signal_file("tower")
	await wait_file("towered")
	check(game.defences.towers.size()==1,"Client tower purchase creates one authoritative tower")
	check(game.progression.field_data(peer).counts.get("built",0)==1,"Tower construction belongs to the builder's quests")
	var tower: DefenceTower = game.defences.towers.values()[0]
	var moved := Vector3.ZERO
	for offset in [Vector2(5,0),Vector2(-5,0),Vector2(0,5),Vector2(0,-5)]:
		var candidate := Map.ground_pos(tower.position.x+offset.x,tower.position.z+offset.y)
		if game.defences.placement_error(p,candidate,tower.kind,true,tower.tower_id).is_empty(): moved=candidate; break
	FileAccess.open(folder+"tower-move-site",FileAccess.WRITE).store_var(moved)
	var tower_cash: int = p.score
	signal_file("move-tower")
	await wait_file("tower-moved")
	check(moved!=Vector3.ZERO and tower.position.distance_to(moved)<0.01 and is_equal_approx(tower.rotation.y,0.7) and p.score==tower_cash,"Client relocates and rotates its tower without another purchase")
	var target: Zombie = game.create_enemy("shambler",p.global_position+Vector3(8,0,0),1)
	target.killer_peer=peer; target.killer_weapon="pistol"
	target.die(Vector3.ZERO)
	await create_timer(1).timeout
	signal_file("kill")
	await wait_file("killed")
	game.shooting_range.key_owned = true
	await move_remote(p,game.shooting_range.house.to_global(Vector3(-0.8,0,4.4)))
	signal_file("range-door")
	await wait_file("range-open")
	check(game.shooting_range.opened,"Client opens the shared shooting house using the woodland key")
	await move_remote(p,game.shooting_range.board.global_position-Vector3.UP*1.4)
	signal_file("range-log")
	await wait_file("range-quest")
	check(game.shooting_range.data(peer).accepted and not game.shooting_range.data(1).accepted,"Sniper quest acceptance belongs to the client")
	await move_remote(p,game.shooting_range.loot_nodes.marksman.global_position-Vector3.UP*0.8)
	signal_file("range-loot")
	await wait_file("range-equipped")
	check(NetSession.world.weapons[peer].unlocked.marksman and game.shooting_range.picked.has("marksman"),"Range rifle is claimed once by the client")
	await move_remote(p,game.shooting_range.house.to_global(Vector3(-6.4167,0,-1.6)))
	NetSession.world.weapons[peer].spread_mul = 0.0
	signal_file("range-shoot")
	await wait_file("range-shot")
	check(game.shooting_range.data(peer).hits.size()==1,"A networked sniper shot records the target for its shooter")
	check(game.shooting_range.lane_scores.any(func(lane): return lane.score>0 and lane.hits==1),"Networked impact awards accuracy points on the host")
	game._clear_combat()
	game.waves.queue.clear(); game.waves.phase="spawning"; game.waves.wave=25
	game.waves.complete_wave()
	check(game.over and game.victory and NetSession.phase=="over","Team victory ends the 25-wave session")
	signal_file("victory")
	await wait_file("victory-seen")
	NetSession.restart()
	while NetSession.phase!="running" or not NetSession.game or not NetSession.game.started: await create_timer(0.2).timeout
	game=NetSession.game
	game.waves.set_process(false)
	check(game.waves.wave==0 and game.barricades.is_empty() and game.defences.towers.is_empty(),"Co-op rematch resets world structures and waves")
	signal_file("rematch")
	await wait_file("rematch-seen")

func client_economy() -> void:
	await wait_file("shop")
	NetSession.command("planes",["buy_kit",["palisade","mechanic"]])
	NetSession.command("planes",["buy_kit",["sandbags","mechanic"]])
	await create_timer(2).timeout
	check(game.progression.kit_stock.palisade==1 and game.progression.kit_stock.sandbags==1 and game.player.score==65,"Client receives its purchased inventory and balance")
	signal_file("bought")
	await wait_file("build")
	var site: Vector3 = FileAccess.open(folder+"site",FileAccess.READ).get_var()
	NetSession.command("planes",["place",["palisade",site,0.0]])
	NetSession.command("planes",["place",["palisade",site,0.0]])
	await create_timer(2).timeout
	check(game.barricades.size()==1 and game.progression.kit_stock.palisade==0,"Built wall and consumed kit replicate to client")
	signal_file("built")
	await wait_file("quest")
	var cash_before: int = game.player.score
	for i in 3: NetSession.command("planes",["quest_action",["bouquet","camp"]])
	await create_timer(2).timeout
	check(game.progression.claimed.get("bouquet",false) and game.player.score==cash_before+120,"Client sees the completed field quest and reward")
	check(CharacterProfile.data.quests.get("planes:bouquet",0)==1,"Client profile receives quest XP exactly once")
	signal_file("quested")
	await wait_file("revive")
	await create_timer(0.5).timeout
	check(game.waves.completed==1 and CharacterProfile.data.classes[CharacterProfile.active_class()].stats.waves==1,"Wave progress and class XP reach the client")
	await wait_file("revived")
	await create_timer(1).timeout
	check(not game.player.downed and game.player.alive,"Client receives its revived state")
	signal_file("verified")
	await wait_file("gather")
	var plant: int = FileAccess.open(folder+"plant",FileAccess.READ).get_var()
	for i in 2: NetSession.command("planes",["collect_wild",[plant]])
	await create_timer(2).timeout
	check(game.nature._picked.has(plant) and game.progression.field_counts.get("flowers",0)==7,"Collected plant disappears for the client without duplicate rewards")
	check(not game.brewing.stock(game.player.peer_id).flowers.is_empty(),"Real flower inventory reaches client")
	signal_file("gathered")
	await wait_file("flower-sale")
	var flower_id: String = FileAccess.open(folder+"flower-sale-id",FileAccess.READ).get_var()
	var flower_before: int = int(game.brewing.stock(game.player.peer_id).flowers.get(flower_id,0))
	var sale_cash: int = game.player.score
	NetSession.command("planes",["trade",["camp","sell_flower",flower_id,""]])
	NetSession.command("planes",["trade",["camp","sell_mushroom","steinpilz",""]])
	await create_timer(2).timeout
	check(int(game.brewing.stock(game.player.peer_id).flowers.get(flower_id,0))==flower_before-1 and int(game.inventory.mushrooms.get("steinpilz",0))==0 and game.player.score==sale_cash+game.progression.FLOWER_SELL_PRICE+Inventory.MUSHROOMS.steinpilz.sell,"Client sees sold plant, sold mushroom and both payments")
	signal_file("flower-sold")
	await wait_file("tower")
	var tower_site: Vector3 = FileAccess.open(folder+"tower-site",FileAccess.READ).get_var()
	NetSession.command("tower_place",[tower_site,0.0,"standard",false])
	await create_timer(2).timeout
	check(game.defences.towers.size()==1,"Tower placement replicates to the client")
	signal_file("towered")
	await wait_file("move-tower")
	var moved: Vector3 = FileAccess.open(folder+"tower-move-site",FileAccess.READ).get_var()
	var tower: DefenceTower = game.defences.towers.values()[0]
	NetSession.command("tower_move",[tower.tower_id,moved,0.7])
	await create_timer(1).timeout
	check(tower.position.distance_to(moved)<0.01 and is_equal_approx(tower.rotation.y,0.7),"Client receives the relocated tower position and orientation")
	signal_file("tower-moved")
	await wait_file("kill")
	await create_timer(1).timeout
	check(CharacterProfile.data.classes[CharacterProfile.active_class()].stats.kills==1,"Attributed kill awards XP to the client profile")
	signal_file("killed")
	await wait_file("range-door")
	NetSession.command("range",["door"])
	await create_timer(1).timeout
	check(game.shooting_range.opened and game.shooting_range.door.collision_layer==0,"Client receives open door and shooting shutters")
	signal_file("range-open")
	await wait_file("range-log")
	NetSession.command("range",["quest"])
	await create_timer(1).timeout
	check(game.shooting_range.data(game.player.peer_id).accepted,"Sniper challenge replicates to its owner")
	signal_file("range-quest")
	await wait_file("range-loot")
	NetSession.command("range",["marksman"])
	await create_timer(1).timeout
	check(game.weapons.unlocked.marksman and not game.shooting_range.loot_nodes.marksman.visible,"Weapon pickup disappears and rifle reaches client inventory")
	NetSession.command("weapon",["marksman"])
	await create_timer(0.5).timeout
	signal_file("range-equipped")
	await wait_file("range-shoot")
	var aim: Vector3 = (game.shooting_range.targets[0].global_position-game.player.camera.global_position).normalized()
	NetSession.command("fire",["marksman",1.0,atan2(-aim.x,-aim.z),asin(aim.y)])
	await create_timer(1).timeout
	check(game.shooting_range.data(game.player.peer_id).hits.size()==1,"Client sees progress from its actual sniper shot")
	check(game.shooting_range.lane_scores.any(func(lane): return lane.score>0 and lane.hits==1),"Client receives lane accuracy score from its actual sniper shot")
	signal_file("range-shot")
	await wait_file("victory")
	await create_timer(1).timeout
	check(game.over and game.victory and CharacterProfile.data.classes[CharacterProfile.active_class()].stats.missions==1,"Client receives victory and mission XP")
	signal_file("victory-seen")
	await wait_file("rematch")
	while NetSession.phase!="running" or not NetSession.game or not NetSession.game.started: await create_timer(0.2).timeout
	game=NetSession.game
	check(game.waves.wave==0 and CharacterProfile.data.classes[CharacterProfile.active_class()].stats.missions==1,"Client rejoins the rematch with persistent class progress")
	signal_file("rematch-seen")
