extends SceneTree
const Boundary = preload("res://scripts/planes_boundary.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)
func run() -> void:
	Map.use_region("planes")
	Map._ensure()
	var residential_clear := true
	var clearance := INF
	for building: Dictionary in Map.VILLAGE:
		if building.get("kind","")=="shooting_targets" or int(building.osm_id)==118083383: continue
		for p in building.poly:
			if Boundary.contains(Vector2(p[0],p[1])): residential_clear = false
			clearance = minf(clearance,Boundary.closest(Vector2(p[0],p[1])).distance_to(Vector2(p[0],p[1])))
	check(residential_clear,"Residential footprints are outside the playable outline")
	check(clearance>=10.0,"At least ten metres clearance before every building")
	for p in [Vector2(-210,305),Vector2(-122,309),Vector2(0,300)]:
		check(Boundary.contains(p),"Southern boundary runs continuously beyond the shooting house: %s" % p)
	check(not Boundary.contains(Vector2(-122,340)),"Southern edge still confines the player beyond the shooting house")
	check(Boundary.southwest_road(Vector2(-137.5,311)) and not Boundary.fence_piece_allowed(Vector2(-136,320),Vector2(-132,320)),"Main road is paved through the southwest boundary and the fence has a gap")
	check(Boundary.fence_piece_allowed(Vector2(-180,320),Vector2(-176,320)),"Fence continues on the fields outside the road opening")
	for p in [Vector2(310,-225),Vector2(400,-165),Vector2(505,50)]:
		check(Boundary.contains(p),"Eastern uphill extension is accessible: %s" % p)
	for p in [Vector2(-107,18),Vector2(0,0),Vector2(175,218),Vector2(250,100)]:
		check(Boundary.contains(p),"Junction, fields and target stand remain accessible: %s" % p)
	var game = load("res://scenes/planes.tscn").instantiate()
	game.exploration_only = true
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	for p in [Vector2(-199,220),Vector2(-172,260),Vector2(-137.5,311)]:
		check(game.cornfield.sample(p).b>0.9,"Main-road surface masks out grass and crops: %s" % p)
	game.set_menu(false)
	for height in [0.1,3.0,25.0]:
		game.player.position = Map.ground_pos(-45,-275)+Vector3.UP*height
		game.player.velocity = Vector3(0,6.5,-20)
		await physics_frame
		await physics_frame
		check(Boundary.contains(Vector2(game.player.position.x,game.player.position.z)),"Actual player controller blocks residential entry at height %s" % height)
	game.player.position = Map.ground_pos(-30,-180)+Vector3.UP*0.1
	game.player.rotation.y = 0
	game.player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await create_timer(4.0).timeout
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var stopped := Vector2(game.player.position.x,game.player.position.z)
	check(Boundary.contains(stopped) and Boundary.closest(stopped).distance_to(stopped)<0.5,"Continuous sprint stops at the visible fence")
	check(not game.spawn_zombie("normal",Vector2(-45,-275),1),"Cheat spawn outside boundary rejected")
	# Fast movement and corner overshoots must also project back inside.
	for p in [Vector2(-1000,-1000),Vector2(1000,1000),Vector2(40,-260),Vector2(310,-210)]:
		game.player.position = Vector3(p.x,100,p.y)
		game.player.velocity = Vector3(200,0,-200)
		Boundary.confine(game.player)
		check(Boundary.contains(Vector2(game.player.position.x,game.player.position.z)),"Corner/overshoot confined: %s" % p)
	game.player.position = Map.ground_pos(-30,-179)+Vector3.UP*0.1
	game.player.velocity = Vector3.ZERO
	game.player.rotation.y = 0
	game.player.pitch = 0.0
	game.player.head.rotation.x = 0.0
	game.player.reset_physics_interpolation()
	if "--render-boundary" in OS.get_cmdline_user_args():
		await create_timer(3).timeout
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../artifacts/planes/boundary/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder+"field-edge.png")
		game.minimap.expanded = true
		game.minimap._update_layout()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"map.png")
	print("BOUNDARY_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
