extends SceneTree
const Boundary = preload("res://scripts/planes_boundary.gd")
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
func go(at: Vector3) -> void:
	game.player.position = at+Vector3.UP*0.1
	game.player.velocity = Vector3.ZERO
	game.player.reset_physics_interpolation()
func key(code: Key, physical: Key = KEY_NONE) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = physical if physical else code
	event.pressed = true
	root.push_input(event)
	event.pressed = false
	root.push_input(event)
func capture(label: String, at: Vector3, target: Vector3) -> void:
	if DisplayServer.get_name()=="headless": return
	go(at)
	game.player.rotation.y = atan2(-(target.x-at.x),-(target.z-at.z))
	var direction := target-(at+Vector3.UP*Player.EYE)
	game.player.pitch = atan2(direction.y,Vector2(direction.x,direction.z).length())
	game.player.head.rotation.x = game.player.pitch
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/planes/refinements/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+label+".png")

func run() -> void:
	paused = true
	game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	game.waves.set_process(false)
	check(not paused and game.player.active and not game.hud.overlay.visible and root.gui_get_focus_owner()==null,"Paused scene entry finishes with immediate player control")
	var start: Vector3 = game.player.position
	Input.action_press("move_forward")
	for i in 30: await physics_frame
	Input.action_release("move_forward")
	check(game.player.position.distance_to(start)>1,"Movement works before opening any menu")
	var building = game.field_building
	game.progression.kit_stock.palisade = 20
	game.progression.kit_stock.sandbags = 20
	var site := Map.ground_pos(-74,60)
	go(Map.ground_pos(site.x,site.z+4))
	check(building.place("palisade",site,0).is_empty(),"First wall builds on field terrain")
	for i in 2: await physics_frame
	var joined := Map.ground_pos(site.x+3.2,site.z)
	check(building.placement_error(joined,0).is_empty(),"Flush wall stays valid after physics registers its neighbour")
	check(building.place("sandbags",joined,0).is_empty(),"Mixed palisade/sandbag chain builds flush")
	for i in 2: await physics_frame
	check(not building.placement_error(site,0).is_empty(),"Actual overlapping walls are rejected")
	building.auto_align = true
	var chain_end: Vector3 = building.snap(Map.ground_pos(joined.x+1.55,joined.z))
	check(is_equal_approx(chain_end.x,joined.x+3.2),"Chain snapping skips occupied internal joints and chooses its free end")
	building.yaw = PI/2
	building.auto_align = false
	var corner: Vector3 = building.snap(Map.ground_pos(joined.x+2.05,joined.z))
	check(is_equal_approx(building.yaw,PI/2) and building.placement_error(corner,building.yaw).is_empty(),"Snapping preserves deliberate rotation and allows a clear corner")
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1,2,1)
	shape.shape = box
	obstacle.add_child(shape)
	game.add_child(obstacle)
	obstacle.position = corner+Vector3.UP
	for i in 2: await physics_frame
	check(building.placement_error(corner,building.yaw)=="Building site occupied.","Buildings and other solid obstacles still block construction")
	obstacle.queue_free()
	await physics_frame
	game.player.score = 10000
	go(Map.ground_pos(-100,55))
	var tower_at := Vector3.ZERO
	for x in range(-108,-91,2):
		for z in range(48,63,2):
			var candidate := Map.ground_pos(x,z)
			if game.defences.placement_error(game.player,candidate).is_empty() and game.defences.placement_error(game.player,Map.ground_pos(x+0.1,z)).is_empty():
				tower_at = candidate
				break
		if tower_at!=Vector3.ZERO: break
	check(tower_at!=Vector3.ZERO,"Movement test starts at a valid tower site")
	go(Map.ground_pos(tower_at.x,tower_at.z+3))
	var tower: DefenceTower = game.defences.create_tower(tower_at,1)
	for i in 2: await physics_frame
	key(KEY_Y,KEY_Z) # German QWERTZ: printed Y is at physical Z.
	check(game.defences.moving_tower and game.defences.rotating_id==tower.tower_id,"Printed Y on a German keyboard starts tower movement")
	var moved := Map.ground_pos(tower_at.x+0.1,tower_at.z)
	var hp := tower.hp
	var move_error: String = game.defences.relocate(game.player,tower.tower_id,moved)
	check(move_error.is_empty() and tower.position.is_equal_approx(moved) and tower.hp==hp,"Tower moves inside its former footprint without colliding with itself: "+move_error)
	game.defences.cancel_placement()
	tower.operator_peer = 1
	check(not game.defences.relocate(game.player,tower.tower_id,tower_at).is_empty(),"An occupied tower cannot be moved")
	tower.operator_peer = 0
	var range_house = game.shooting_range
	range_house.opened = true
	range_house.key_owned = true
	range_house.refresh()
	go(range_house.house.to_global(Vector3(0,0,-1.5)))
	check(range_house.monitors.size()==6 and range_house.lane_scores.size()==6,"All six lanes have score displays")
	for target: Area3D in range_house.targets:
		var lane: int = target.get_meta("range_lane")
		range_house.hit(target,1,"pistol",target.to_global(Vector3.ZERO))
		check(range_house.lane_scores[lane].score==10,"Bullseye awards 10 on lane %d" % lane)
		range_house.hit(target,1,"pistol",target.to_global(Vector3(0.55,0,0)))
		check(range_house.lane_scores[lane].score==11 and range_house.lane_scores[lane].hits==2,"Outer hit awards fewer points on lane %d" % lane)
	var snapshot: Dictionary = range_house.snapshot()
	range_house.lane_scores[0].score = 999
	range_house.apply_snapshot(snapshot)
	check(range_house.lane_scores[0].score==11,"Co-op snapshot restores independent lane scores")
	var monitor: Label3D = range_house.monitors[0]
	var local_monitor: Vector3 = range_house.house.to_local(monitor.global_position)
	go(range_house.house.to_global(Vector3(local_monitor.x,0,-1.5)))
	game.player.rotation.y = range_house.house.rotation.y
	game.player.pitch = -0.3
	game.player.head.rotation.x = -0.3
	check(range_house.nearby(game.player)=="score_0","Aiming at a nearby screen selects its reset interaction")
	key(KEY_E)
	check(range_house.lane_scores[0].score==0 and range_house.lane_scores[1].score==11,"E resets only the selected lane")
	go(Map.ground_pos(0,0))
	range_house.transact(game.player,"score_1")
	check(range_house.lane_scores[1].score==11,"Distant score reset is rejected")
	var road_clear := true
	for batch: MultiMeshInstance3D in game.cornfield.batches+game.cornfield.grass_batches:
		for sample: Vector3 in batch.get_meta("placement_samples",PackedVector3Array()):
			if Boundary.southwest_road(Vector2(sample.x,sample.z)): road_clear = false
	for plant: Dictionary in game.nature.plants:
		if Boundary.southwest_road(plant.at): road_clear = false
	check(road_clear,"Main road has no sampled crop, grass or flower placements")
	if DisplayServer.get_name()!="headless":
		var fence: Node3D = game.landscape.get_node("FieldBoundary")
		var rails: MultiMesh = fence.get_child(1).multimesh
		var intact := true
		for i in rails.instance_count:
			var frame := rails.get_instance_transform(i)
			if frame.basis.z.length()<3.0 or frame.basis.x.length()>0.01 or frame.basis.y.length()>0.01: intact = false
		check(intact,"Fence wires preserve their length and thickness at every angle")
	await capture("score",range_house.house.to_global(Vector3(local_monitor.x,0,-1.4)),monitor.global_position)
	await capture("road",Map.ground_pos(-140,310),Map.ground_pos(-210,204))
	await capture("fence",Map.ground_pos(-220,307),Map.ground_pos(-215,320)+Vector3.UP)
	await capture("building",Map.ground_pos(-73,65),site+Vector3.UP)
	print("PLANES_REFINEMENTS_DONE checks=%d failures=%d" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
