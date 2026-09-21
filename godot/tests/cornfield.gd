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
	check(field.plant_count>35000 and field.plant_count<70000,"Dense field uses a bounded number of batched corn stalks")
	print("CORN_PLANTS ",field.plant_count)
	var rendered_instances := 0
	for batch: MultiMeshInstance3D in field._plant_batches:
		rendered_instances += batch.multimesh.instance_count
	check(rendered_instances == field.plant_count,"Each corn stalk has exactly one render instance, without overlapping LOD copies")
	var sample: MultiMeshInstance3D = field._plant_batches[field._plant_batches.size()/2]
	var stable_bounds := sample.multimesh.custom_aabb
	var sample_center := sample.global_transform * stable_bounds.get_center()
	field._update_plant_lods(sample_center)
	check(sample.get_meta("corn_lod")==0,"Approaching corn selects its detailed mesh")
	var stable := true
	for distance in [11.7,12.3,11.9,12.1,13.0]:
		field._update_plant_lods(sample_center+Vector3.RIGHT*distance)
		stable = stable and sample.get_meta("corn_lod")==0
	check(stable,"Camera bob across the near boundary does not flicker between corn meshes")
	field._update_plant_lods(sample_center+Vector3.RIGHT*15)
	check(sample.get_meta("corn_lod")==1,"Moving beyond hysteresis switches once to medium detail")
	field._update_plant_lods(sample_center+Vector3.RIGHT*45)
	stable = sample.get_meta("corn_lod")==2
	for distance in [41.7,42.3,41.9,42.1,41.0]:
		field._update_plant_lods(sample_center+Vector3.RIGHT*distance)
		stable = stable and sample.get_meta("corn_lod")==2
	check(stable,"Distant corn remains stable around its LOD boundary")
	field._update_plant_lods(sample_center)
	check(sample.get_meta("corn_lod")==0 and sample.multimesh.custom_aabb==stable_bounds,"Returning to close detail retains the same wind-safe culling bounds")
	# The headless dummy renderer does not retain MultiMesh instance transforms.
	if DisplayServer.get_name() != "headless":
		var south_only := true
		for child in field.get_children():
			if child is MultiMeshInstance3D:
				for i in child.multimesh.instance_count:
					var at: Vector3 = child.position + child.multimesh.get_instance_transform(i).origin
					if at.x >= -80 or not field.field_ground(Vector2(at.x,at.z)) or Map.on_road(at.x,at.z,2.0): south_only = false
		check(south_only, "All corn stays on western meadow, clear of forest, trees and village road")
	var entrance: Vector2 = field.cell_position(Vector2i(1,0))
	var start: Vector3 = Map.ground_pos(entrance.x,entrance.y)
	check(field.FIELD_AXIS.dot(Vector2(76,112).normalized()) > 0.995,"Long field edge follows the NW-SE forest boundary")
	check(not field.field_ground(Vector2(-220,120)),"Previous crosswise field footprint returns to meadow")
	var soil: MeshInstance3D = field.get_node("CornSoil")
	check(soil.material_override is ShaderMaterial and soil.material_override.get_shader_parameter("normal_tex") != null,"Soil uses textured PBR relief instead of flat triangle colors")
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
	check(crow.skeleton != null and crow.wing_bones.size()==4 and not crow.wing_bones.has(-1), "Meshy raven loads a complete articulated wing rig")
	crow.voice.stop()
	crow.call_voice()
	var first_call: int = crow.last_call
	crow.voice.stop()
	crow.call_voice()
	check(crow.last_call!=first_call and crow.voice.stream.resource_path.begins_with("res://assets/audio/sfx/raven"), "Raven uses supplied recordings without immediate repetition")
	crow.set_process(false)
	crow.scare(crow.global_position)
	crow._process(0.4)
	check(crow.flying>0 and crow.position.y>crow.home.y,"Nearby player or gunshot makes ravens take flight")
	var owl = field.birds[7]
	check(owl.skeleton != null and owl.wing_bones.size()==4 and not owl.wing_bones.has(-1), "Meshy owl loads a complete articulated wing rig")
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
		# Several frames while moving at the field edge expose tile flashes and gaps.
		game.day_night.set_process(false)
		for frame in 8:
			var edge: Vector2 = field.field_to_world(Vector2(48+frame*0.35,-9))
			var ahead: Vector2 = field.field_to_world(Vector2(62,18))
			camera.position = Map.ground_pos(edge.x,edge.y)+Vector3.UP*(1.7+sin(frame*1.7)*0.04)
			camera.look_at(Map.ground_pos(ahead.x,ahead.y)+Vector3.UP*1.8)
			await capture("edge-motion-%02d" % frame)
		var overlook: Vector2 = field.field_to_world(Vector2(70,100))
		var center: Vector2 = field.field_to_world(Vector2(70,26))
		camera.position = Map.ground_pos(overlook.x,overlook.y)+Vector3.UP*60
		camera.look_at(Map.ground_pos(center.x,center.y)+Vector3.UP)
		await capture("overview")
		camera.position = start+Vector3.UP*1.7
		var inward: Vector2 = field.cell_position(Vector2i(1,2))
		camera.look_at(Map.ground_pos(inward.x,inward.y)+Vector3.UP*0.8)
		await capture("maze")
		var inside: Vector2 = field.cell_position(Vector2i(1,1))
		camera.position = Map.ground_pos(inside.x,inside.y)+Vector3.UP*1.7
		camera.look_at(camera.position-Vector3(field.FIELD_AXIS.x,0,field.FIELD_AXIS.y)*3)
		await capture("dense-wall")
		var scarecrow: Node3D = field.get_node("Scarecrow_1_0")
		camera.position = scarecrow.global_position+scarecrow.basis.z*3.8+scarecrow.basis.x*0.6+Vector3.UP*1.6
		camera.look_at(scarecrow.global_position+Vector3.UP*1.3)
		game.hud.msg_label.text = ""
		await capture("scarecrow")
		var raven_position: Vector3 = crow.position
		crow.position += Vector3.UP*4.0
		crow.flying = 5.0
		crow.clock = 0.0
		crow.flap_power = 1.0
		crow.flap_phase = 0.25  # top of the library wingbeat
		crow._advance_flap(0.0)
		crow._pose_raven()
		camera.position = crow.position+Vector3(1.1,0.65,-1.3)
		camera.look_at(crow.position+Vector3.UP*0.22)
		await capture("raven-flight")
		crow.flap_phase = 0.81  # bottom of the power stroke
		crow._advance_flap(0.0)
		crow._pose_raven()
		await capture("raven-downstroke")
		crow.flying = 0.0
		crow.flap_power = 0.0
		crow._advance_flap(0.0)
		crow._pose_raven()
		await capture("raven-perched")
		crow.position = raven_position
		game.day_night.set_time_hours(23)
		owl._process(0.1)
		camera.position = owl.position+Vector3(2,1,-3)
		camera.look_at(owl.position+Vector3.UP*0.2)
		await capture("owl")
		camera.position = Map.ground_pos(overlook.x,overlook.y)+Vector3.UP*60
		camera.look_at(Map.ground_pos(center.x,center.y)+Vector3.UP)
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
