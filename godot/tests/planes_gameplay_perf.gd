extends SceneTree
var game: Node3D
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>300000: quit(1)
	return false
func run() -> void:
	game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game); current_scene = game
	while not game.ready_for_exploration: await process_frame
	await game.start_survival()
	game.waves.set_process(false)
	game.player.position = Map.ground_pos(95,116)+Vector3.UP*0.1
	game.player.rotation.y = 0
	game.player.pitch = -0.08
	game.player.head.rotation.x = -0.08
	game.player.reset_physics_interpolation()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var rows := []
	for phase in ["quiet","fortified","storm"]:
		if phase=="fortified":
			for i in 40:
				var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(72+(i%8)*6,66+(i/8)*6),1,0,false,DefenceTower.TYPES[i%DefenceTower.TYPES.size()])
				tower.hp = 1000000
				var bar: Barricade = SandbagLine.new() if i%2 else Barricade.new()
				bar.setup({"id":"stress_%d" % i,"name":"Stress","pos":Vector2(60+(i%20)*3.5,49+(i/20)*8),"yaw":0.0,"segments":1},game.hud)
				game.add_child(bar); bar.build(); bar.hp = 1000000
				game.barricades.append(bar)
			for i in 24:
				var enemy: Zombie = game.create_enemy(["runner","soldier","brute","shambler"][i%4],Map.ground_pos(65+(i%8)*6,35+(i/8)*3),25)
				enemy.damage_mul = 0
				enemy.hp = 10000000; enemy.max_hp = enemy.hp
		if phase=="storm":
			game.weather.force("storm")
			game.weather.intensity = 1; game.weather.wetness = 1
		await create_timer(5).timeout
		var samples: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in 600:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0); last = now
		var mean := 0.0
		for sample in samples: mean += sample/samples.size()
		samples.sort()
		var row := {"phase":phase,"mean_ms":mean,"fps":1000/mean,"p95_ms":samples[570],"p99_ms":samples[594],"draws":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
		rows.append(row); print("FIELD_PERF ",JSON.stringify(row))
		var folder := ProjectSettings.globalize_path("res://../artifacts/planes/gameplay/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder+phase+".png")
	var file := FileAccess.open("res://../artifacts/planes/gameplay/performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  ")); file.close()
	print("FIELD_PERF_DONE")
	quit()
