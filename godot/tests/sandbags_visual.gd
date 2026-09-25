# Windowed look at a deployed sandbag line with an acid pool: artifacts/batch26/sandbags_acid.png
extends SceneTree
var game: Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.day_night.set_process(false)
	game.day_night.set_time_hours(16.0)
	var player: Player = game.player
	player.set_physics_process(false)
	var gate: Barricade = game.barricades[1]
	var line: SandbagLine = game.sandbags[1]
	gate.build()
	gate.damage(1e6)
	var inward: Vector2 = (Vector2(line.center.x, line.center.z) - Vector2(gate.center.x, gate.center.z)).normalized()
	var pool := AcidPool.new()
	game.add_child(pool)
	pool.global_position = line.attack_point(gate.center) - Vector3(inward.x, 0, inward.y) * 1.5 + Vector3.UP * 0.04
	pool.setup(Zombie.TYPES.spitter.ranged, true)
	var stand: Vector2 = Vector2(line.center.x, line.center.z) + inward * 5.0 + Vector2(2.0, 0.0)
	var from: Vector3 = Map.ground_pos(stand.x, stand.y) + Vector3.UP * 0.05
	player.global_position = from
	var to: Vector3 = line.center + Vector3.UP * 0.5 - (from + Vector3.UP * Player.EYE)
	player.rotation.y = atan2(-to.x, -to.z)
	player.pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.4, 1.4)
	player.head.rotation.x = player.pitch
	for i in 50: await process_frame
	var dir := ProjectSettings.globalize_path("res://../artifacts/batch26/")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_viewport().get_texture().get_image().save_png(dir + "sandbags_acid.png")
	print("SANDBAGS_VISUAL_DONE")
	quit(0)
