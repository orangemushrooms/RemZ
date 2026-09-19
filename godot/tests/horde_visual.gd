# Visual check of the horde update: a field titan on the meadow south of the hut (taller than the trees), the
# second titan skin, and a line of common zombies so every generated skin shows up. Screenshots go to
# shots/horde_*.png, the picked skins, the titans' real height and a short walk of the titan are printed. Run:
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=horde_visual --no-intro
extends SceneTree

var game: Node
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000:
		print("HORDE_VISUAL timeout")
		quit(1)
	return false

func capture(file: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../shots/" + file + ".png"))
	print("HORDE_SHOT ", file)

func view(point: Vector2, target: Vector3) -> void:
	game.player.global_position = Map.ground_pos(point.x, point.y) + Vector3(0, 0.2, 0)
	game.player.camera.look_at(target)

func freeze(z: Zombie, yaw: float, on: bool = true) -> void:
	z.set_physics_process(not on)
	z.agent.avoidance_enabled = not on
	if on: z.rotation.y = yaw

func top_bone(z: Zombie) -> float:
	var top := 0.0
	for sk in z.find_children("*", "Skeleton3D", true, false):
		var skel: Skeleton3D = sk
		for b in skel.get_bone_count():
			var p: Vector3 = skel.to_global(skel.get_bone_global_pose(b).origin)
			top = maxf(top, p.y - z.global_position.y)
	return top

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	if "achievements" in game and game.achievements: game.achievements.hide()
	if "day_night" in game and game.day_night:
		game.day_night.clock_seconds = 17 * 3600 + 40 * 60
		game.day_night.advance(1)
		game.day_night.set_process(false)
	# the titan walks in from the field, 90 m south of the fire
	game.spawn_zombie("titan", Vector2(13, 93), 1, "east")
	var titan: Titan = game.zombies_root.get_children().back()
	freeze(titan, PI)
	# a line of common zombies on the Wiesenweg so all skins can be compared
	var kinds := ["shambler", "shambler", "shambler", "shambler", "shambler", "shambler", "shambler", "shambler",
		"runner", "runner", "runner", "runner", "soldier", "soldier", "soldier", "nurse", "brute"]
	var picked := {}
	var line: Array = []
	for i in kinds.size():
		game.spawn_zombie(kinds[i], Vector2(-2 + i * 1.6, 60 + (i % 2) * 1.2), 1, "east")
		var z: Zombie = game.zombies_root.get_children().back()
		freeze(z, PI)
		line.append(z)
		var skin := "none"
		if z.model: skin = z.model.scene_file_path.get_file().get_basename()
		picked[skin] = int(picked.get(skin, 0)) + 1
	game.hud.message("", 0.0)
	await create_timer(1.5).timeout
	print("HORDE_TITAN height_param=%.1f model_scale=%.2f top_bone=%.1f m skin=%s" % [titan.height, titan.model.scale.y, top_bone(titan), titan.model.scene_file_path.get_file() if titan.model else "none"])
	print("HORDE_SKINS ", picked)
	view(Vector2(9, 40), titan.global_position + Vector3.UP * 12)
	await capture("horde_titan")
	view(Vector2(11, 50), Map.ground_pos(11, 60) + Vector3.UP * 1.2)
	await capture("horde_skins")
	view(Vector2(2, 56.5), Map.ground_pos(5, 60.5) + Vector3.UP * 1.3)
	await capture("horde_skins_close")
	# the second titan skin, forced
	Zombie.force_skin = "zombie_colossus"
	game.spawn_zombie("titan", Vector2(-50, 104), 1, "south")
	Zombie.force_skin = ""
	var colossus: Titan = game.zombies_root.get_children().back()
	freeze(colossus, PI * 0.5)
	await create_timer(1.0).timeout
	print("HORDE_COLOSSUS top_bone=%.1f m skin=%s" % [top_bone(colossus), colossus.model.scene_file_path.get_file() if colossus.model else "none"])
	view(Vector2(-22, 84), colossus.global_position + Vector3.UP * 11)
	await capture("horde_colossus")
	# let the first titan walk towards the hut for a while: it must move and must not crash
	# (the line stays frozen: unfrozen runners would kill the motionless player within seconds)
	var start := titan.global_position
	freeze(titan, 0.0, false)
	game.player.global_position = Map.ground_pos(9, 30) + Vector3(0, 0.2, 0)
	await create_timer(14.0).timeout
	print("HORDE_WALK titan_moved=%.1f m phase=%s pos=%s alive=%d" % [start.distance_to(titan.global_position), titan.strike_phase, titan.global_position, game.alive_zombies()])
	game.player.camera.look_at(titan.global_position + Vector3.UP * 10)
	await capture("horde_titan_walk")
	print("HORDE_VISUAL_DONE")
	quit(0)
