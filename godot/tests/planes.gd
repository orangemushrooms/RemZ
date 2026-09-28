extends SceneTree
var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>240000:
		print("FAIL: Planes timeout")
		quit(1)
	return false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)

func run() -> void:
	var campaign := Campaign.new()
	check(campaign.select("planes"),"Planes is selectable")
	Map.use_region("forest"); Map._ensure()
	var forest_roads := Map.ROADS.size()
	var forest_height := Map.ground_height(0,0)
	Map.use_region("planes"); Map._ensure()
	check(absf(Map.ground_height(0,0))<0.001,"User coordinate is the zero-altitude datum")
	check(Map._h.size()==Map._w*Map._hh,"Entire height raster is present")
	check(absf(Map.ground_height(-111.8,18.9)+float(Map._d.altitude_m)-557.4)<0.15,"Junction height agrees with independently sampled swissALTI3D source")
	check(Map.BUILDINGS.is_empty() and Map.POND.is_empty() and Map.BARRICADES.is_empty(),"No Forest buildings, pond or gate data leaks into Planes")
	check(Map.ground_height(470,-150)>Map.ground_height(-110,18)+65,"Surveyed uphill route rises towards Sennhof")
	Map.use_region("forest"); Map._ensure()
	check(Map.ROADS.size()==forest_roads and is_equal_approx(Map.ground_height(0,0),forest_height) and Map.BUILDINGS.has("waldhuette"),"Returning to Forest restores original data without duplicated roads")
	game = load("res://scenes/planes.tscn").instantiate()
	game.exploration_only = true
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	check(not game.survival_active and game.waves==null and game.campaign.best_wave("planes")==0,"Exploration starts without enemies, waves or awarded campaign progress")
	for i in 8: await physics_frame
	check(game.player.is_on_floor(),"Explorer settles on terrain at the photo viewpoint")
	var map: Minimap = game.minimap
	var north := map.map_position(Vector3(0,0,-100))
	var east := map.map_position(Vector3(100,0,0))
	var datum := map.map_position(Vector3.ZERO)
	check(north.y<datum.y and east.x>datum.x and absf(north.distance_to(datum)-east.distance_to(datum))<0.001,"Minimap preserves north and equal east/north distances")
	check(map.visible and not map.expanded and map.get_node_or_null("MapClip/Symbols")!=null,"Forest-style minimap starts compact with a separate live marker layer")
	var map_key := InputEventKey.new()
	map_key.keycode = KEY_M
	map_key.physical_keycode = KEY_M
	map_key.pressed = true
	root.push_input(map_key)
	await process_frame
	check(map.expanded and map.visible and game.player.active,"M expands the map without hiding it or stopping exploration")
	var previous_size := root.size
	root.size = Vector2i(1280,720)
	for i in 3: await process_frame
	# Control coordinates follow the project's stretched canvas, not physical window pixels.
	check(map.get_viewport_rect().encloses(map.get_global_rect()),"Expanded map remains fully inside a 720p viewport")
	root.size = previous_size
	map_key.pressed = false
	root.push_input(map_key)
	map_key.pressed = true
	root.push_input(map_key)
	await process_frame
	check(not map.expanded and map.visible,"A second M press restores the compact map")
	check(Lang.resolve(map.LEGEND,"de").contains("Kartengrösse"),"Map legend includes its German translation")
	check(game.landscape.tree_count>100 and game.birds.size()==14,"Mapped groves and reused Meshy wildlife are built")
	check(Map.cover(60,4).r>0.95 and Map.cover(60,4).b<0.01,"Woodland east of the fork is forest floor, not gravel")
	check(game.cornfield.counts.grass>700000 and game.cornfield.counts.undergrowth>5000,"Meadows are denser and mapped woods have undergrowth")
	var woodland_clear := true
	var woodland_samples := 0
	var grid_aligned := 0
	for node: MultiMeshInstance3D in game.cornfield.grass_batches:
		if node.get_meta("kind")!="undergrowth": continue
		for at: Vector3 in node.get_meta("placement_samples"):
			woodland_samples += 1
			var local := at-node.position
			if fposmod(local.x,1.5)<0.45 and fposmod(local.z,1.5)<0.45: grid_aligned += 1
			var crop: Color = game.cornfield.sample(Vector2(at.x,at.z))
			if Map.cover(at.x,at.z).r<0.65 or Map.gravel_weight(at.x,at.z)>0.05 or crop.r>0.5 or crop.g>0.5: woodland_clear = false
	check(woodland_clear and woodland_samples>200,"Dense woodland placement stays off gravel and cultivated crops")
	check(grid_aligned<float(woodland_samples)*0.2 and game.cornfield.counts.undergrowth>14000 and game.cornfield.counts.woodland_grass>15000,"Woodland is substantially denser with mixed grass and no repeated 1.5-m planting grid")
	check(game.landscape.get_node("VillageBuildings").get_meta("exact_footprints",0)>500,"Village walls follow source polygons without overlapping bounding-box houses")
	check(game.cornfield.counts.corn>10000 and game.cornfield.counts.wheat>10000,"Fields contain dense maize and grain")
	check(game.birds[0].model_root!=null and game.birds[0].skeleton!=null,"Raven uses existing animated model")
	check(game.player._surface_step()=="gravel","Junction has gravel footsteps")
	var ray_ok := true
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for p in [Vector2(-111,19),Vector2(0,0),Vector2(100,-17),Vector2(295,-112),Vector2(-170,-144),Vector2(70,65)]:
		var expected := Map.ground_height(p.x,p.y)
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x,expected+2,p.y),Vector3(p.x,expected-2,p.y),1)
		var hit := space.intersect_ray(query)
		ray_ok = ray_ok and not hit.is_empty() and absf(hit.position.y-expected)<0.2
	check(ray_ok,"Road collision follows the surveyed slope at six separated locations")
	var target_faces: Array = game.landscape.get_node("VillageBuildings").get_meta("target_panels",[])
	var targets_block := target_faces.size()==6
	for face: Transform3D in target_faces:
		var normal := face.basis.z
		var query := PhysicsRayQueryParameters3D.create(face.origin+normal*3,face.origin-normal*3,1)
		var hit := space.intersect_ray(query)
		targets_block = targets_block and not hit.is_empty() and str(hit.collider.name)=="Building_1558294553"
		if hit.is_empty() or str(hit.collider.name)!="Building_1558294553":
			print("TARGET_RAY unexpected collider=",str(hit.collider.name) if not hit.is_empty() else "none")
	check(targets_block,"All six target faces have solid stand collision")
	var overhead := Map.ground_pos(176.175,218.3225)+Vector3.UP*3.3
	var above := space.intersect_ray(PhysicsRayQueryParameters3D.create(overhead+Vector3.LEFT*5,overhead+Vector3.RIGHT*5,1))
	check(above.is_empty(),"No invisible former house collider remains above the low target stand")
	var crops_clear := true
	for node: MultiMeshInstance3D in game.cornfield.batches:
		# The headless Dummy renderer does not preserve MultiMesh transforms.
		var samples: PackedVector3Array = node.get_meta("placement_samples")
		for i in samples.size():
			var at := samples[i]
			if DisplayServer.get_name()!="headless": at = node.position+node.multimesh.get_instance_transform(i*37).origin
			if Map.gravel_weight(at.x,at.z)>0.25: crops_clear = false
	check(crops_clear,"Crop instances leave mapped gravel tracks clear")
	game.player.rotation.y = -PI/2
	var start: Vector3 = game.player.position
	Input.action_press("move_forward")
	for i in 90: await physics_frame
	Input.action_release("move_forward")
	check(game.player.position.x>start.x+2 and game.player.is_on_floor(),"Actual walking crosses the junction without floating or falling")
	game.set_menu(true)
	check(not game.player.active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and game.menu.visible,"Escape menu releases the mouse and stops movement")
	game.set_menu(false)
	check(game.player.active and not game.menu.visible,"Continue restores exploration")
	if "--render-planes" in OS.get_cmdline_user_args():
		var folder := ProjectSettings.globalize_path("res://../artifacts/planes/")
		DirAccess.make_dir_recursive_absolute(folder)
		map.expanded = true
		map._update_layout()
		await process_frame
		await RenderingServer.frame_post_draw
		var cache: Image = map._map_cache.get_texture().get_image()
		check(cache.get_pixel(100,160).a>0.9,"Cached cartography renders opaque terrain behind live markers")
		root.get_texture().get_image().save_png(folder+"minimap-expanded.png")
		map.expanded = false
		map._update_layout()
		for i in 3:
			game.set_view(i)
			for frame in 20: await physics_frame
			await create_timer(1.8).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+str(Map._d.views[i].id)+".png")
			print("PLANES_RENDER ",Map._d.views[i].id," fps=",Engine.get_frames_per_second()," draws=",root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		game.set_menu(true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"menu.png")
	if "--render-targets" in OS.get_cmdline_user_args():
		game.set_menu(false)
		var folder := ProjectSettings.globalize_path("res://../artifacts/planes/")
		DirAccess.make_dir_recursive_absolute(folder)
		for view in [{"id":"targets-front","pos":Vector2(154,225),"look":Vector2(176.175,218.3225)}, {"id":"targets-road","pos":Vector2(55.86,228.91),"look":Vector2(275,340)}]:
			game.player.position = Map.ground_pos(view.pos.x,view.pos.y)+Vector3.UP*0.08
			game.player.velocity = Vector3.ZERO
			var direction: Vector2 = view.look-view.pos
			game.player.rotation.y = atan2(-direction.x,-direction.y)
			game.player.pitch = 0.03 if view.id=="targets-front" else 0.0
			game.player.head.rotation.x = game.player.pitch
			game.player.reset_physics_interpolation()
			await create_timer(2.0).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+view.id+".png")
	if "--planes-roundtrip" in OS.get_cmdline_user_args():
		game.return_to_map()
		await process_frame
		while current_scene==game or current_scene==null: await process_frame
		game = current_scene
		while not game.navigation_ready: await process_frame
		for i in 8: await process_frame
		check(Map.active_region=="forest" and game.hud.map_selection.visible,"Return action rebuilds Forest and opens region selection")
		check(not game.started,"Returning from exploration does not start a survival round")
		var forest_id: int = game.get_instance_id()
		game.hud.map_selection.choose("planes")
		while current_scene==null or current_scene.get_instance_id()==forest_id: await process_frame
		game = current_scene
		while not game.ready_for_exploration: await process_frame
		check(Map.active_region=="planes" and game.player.active,"Actual region-selection action enters the separate Planes scene again")
	print("PLANES_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
