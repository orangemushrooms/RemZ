extends SceneTree
var game: Node3D
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>300000: quit(1)
	return false
func run() -> void:
	game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	var combat := "--planes-combat-perf" in OS.get_cmdline_user_args()
	if combat:
		await game.start_survival()
		game.waves.set_process(false)
		game.weather.force("storm" if "--planes-storm-perf" in OS.get_cmdline_user_args() else "clear")
		game.weather.intensity = 1.0 if game.weather.forced=="storm" else 0.0
		game.weather.wetness = game.weather.intensity
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var folder := ProjectSettings.globalize_path("res://../artifacts/planes/performance/")
	DirAccess.make_dir_recursive_absolute(folder)
	var label := "sample"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--planes-perf="): label = arg.trim_prefix("--planes-perf=")
	var views: Array = Map._d.views.duplicate(true)
	views.append({"id":"grove","pos":[30,-7],"target":[135,-22]})
	views.append({"id":"village","pos":[-180,-100],"target":[-260,-210]})
	var report := {"label":label,"viewport":str(root.size),"adapter":RenderingServer.get_video_adapter_name(),"views":[]}
	for view: Dictionary in views:
		var p := Vector2(view.pos[0],view.pos[1])
		var target := Vector2(view.target[0],view.target[1])
		game.player.position = Map.ground_pos(p.x,p.y)+Vector3.UP*0.08
		game.player.velocity = Vector3.ZERO
		game.player.rotation.y = atan2(-(target.x-p.x),-(target.y-p.y))
		game.player.pitch = 0.015
		game.player.head.rotation.x = 0.015
		game.player.reset_physics_interpolation()
		game.cornfield.update_lod()
		if combat:
			game._clear_combat()
			await process_frame
			var forward := (target-p).normalized()
			var right := Vector2(-forward.y,forward.x)
			for i in 24:
				var spawn := p+forward*(20+(i/6)*2.2)+right*((i%6)-2.5)*1.5
				var at := NavigationServer3D.map_get_closest_point(game.nav_region.get_navigation_map(),Map.ground_pos(spawn.x,spawn.y))
				var enemy: Zombie = game.create_enemy(["shambler","soldier","brute","runner"][i%4],at,25)
				enemy.damage_mul = 0.0
		await create_timer(3.0).timeout
		var samples: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in 200:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			last = now
		var average := 0.0
		for sample in samples: average += sample/samples.size()
		samples.sort()
		var row := {"id":view.id,"mean_ms":average,"median_ms":samples[100],"p95_ms":samples[190],"fps":1000.0/average,
			"draws":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
		report.views.append(row)
		root.get_texture().get_image().save_png(folder+label+"-"+view.id+".png")
		print("PLANES_PERF ",JSON.stringify(row))
	var file := FileAccess.open(folder+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("PLANES_PERF_DONE ",label)
	quit()
