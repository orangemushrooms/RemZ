extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.weapons.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	p.set_physics_process(false)
	var field = game.cornfield
	check(field.plant_count>10000 and field.plant_count<40000,"Dense field uses a bounded number of batched corn stalks")
	print("CORN_PLANTS ",field.plant_count)
	var start: Vector3 = Map.ground_pos(40.25,72)
	var caches: Array = []
	for item in game.loots:
		if is_instance_valid(item) and item is Loot and item.kind=="maze_cache": caches.append(item)
	check(caches.size()==5,"Five distinct rewards are hidden in maze dead ends")
	var visited := {Vector2i(1,0):true}
	var queue: Array[Vector2i] = [Vector2i(1,0)]
	while not queue.is_empty():
		var cell := queue.pop_front() as Vector2i
		for d: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if field.passages.has(cell+d) and not visited.has(cell+d):
				visited[cell+d]=true
				queue.append(cell+d)
	check(visited.size()==field.passages.size() and visited.has(Vector2i(11,12)),"Every passage and the second exit connect to the entrance")
	var nav: RID = game.get_world_3d().navigation_map
	for item in caches:
		var path := NavigationServer3D.map_get_path(nav,start,item.global_position,true)
		check(path.size()>1 and path[-1].distance_to(item.global_position)<2,"Navigation reaches cache: "+item.id)
	var fire = caches[0]
	var data: Dictionary = game.progression.rare_market.data(p.peer_id)
	data.ammo.fire = 96
	fire.take(w,game.hud)
	check(not fire.taken and data.ammo.fire==96,"Full special-ammo inventory leaves its cache intact")
	data.ammo.fire = 0
	fire.take(w,game.hud)
	fire.take(w,game.hud)
	check(fire.taken and data.ammo.fire==12,"Fire cache grants twelve rounds exactly once")
	var cash = caches[2]
	var before := p.score
	cash.take(w,game.hud)
	cash.take(w,game.hud)
	check(p.score==before+250,"Cash cache grants its reward exactly once")
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var remote: Player = NetSession.world.actor(2)
	var frost = caches[1]
	remote.global_position = frost.global_position+Vector3(0,0,0.7)
	for i in 3: await physics_frame
	NetSession.world.collect_loot(2,str(frost.get_meta("coop_id")))
	check(frost.taken and game.progression.rare_market.data(2).ammo.frost==12,"Host awards maze special ammunition to the collecting teammate")
	NetSession.world.collect_loot(2,str(frost.get_meta("coop_id")))
	check(game.progression.rare_market.data(2).ammo.frost==12,"Duplicate coop requests cannot duplicate rewards")
	remote.global_position = Vector3(120,20,-100)
	NetSession.enabled = false
	var crow = field.birds[0]
	crow.set_process(false)
	crow.scare(crow.global_position)
	crow._process(0.4)
	check(crow.flying>0 and crow.position.y>crow.home.y,"Nearby player or gunshot makes ravens take flight")
	var owl = field.birds[7]
	owl.set_process(false)
	game.day_night.set_time_hours(12)
	owl._process(0.1)
	check(not owl.visible,"Owls remain hidden during daylight")
	game.day_night.set_time_hours(23)
	owl._process(0.1)
	check(owl.visible and owl.position.y>owl.home.y,"Owls become airborne at night")
	game.day_night.set_time_hours(12)
	if "--render-corn" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.make_current()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/cornfield"))
		camera.position = Map.ground_pos(27,65)+Vector3.UP*8
		camera.look_at(Map.ground_pos(58,96)+Vector3.UP)
		await capture("overview")
		camera.position = Map.ground_pos(40.25,72.8)+Vector3.UP*1.7
		camera.look_at(Map.ground_pos(40.25,90)+Vector3.UP*1.7)
		await capture("maze")
		game.day_night.set_time_hours(23)
		owl._process(0.1)
		camera.position = owl.position+Vector3(2,1,-3)
		camera.look_at(owl.position+Vector3.UP*0.2)
		await capture("owl")
		camera.position = Map.ground_pos(27,65)+Vector3.UP*8
		camera.look_at(Map.ground_pos(58,96)+Vector3.UP)
		game.day_night.set_time_hours(12)
		for i in 60: await process_frame
		var times: Array[float] = []
		for i in 180:
			await process_frame
			times.append(root.get_process_delta_time())
		times.sort()
		print("CORN_RENDER p95_ms=",times[int(times.size()*0.95)]*1000," median_ms=",times[times.size()/2]*1000," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		field.hide()
		for i in 60: await process_frame
		times.clear()
		for i in 180:
			await process_frame
			times.append(root.get_process_delta_time())
		times.sort()
		print("BASE_RENDER p95_ms=",times[int(times.size()*0.95)]*1000)
	print("CORNFIELD_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
func capture(id: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/cornfield/%s.png" % id))
