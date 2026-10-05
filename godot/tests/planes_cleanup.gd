extends SceneTree
class Fixture extends "res://scripts/planes.gd":
	func _ready() -> void: pass
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Map.use_region("planes")
	Map._ensure()
	var game := Fixture.new()
	root.add_child(game)
	current_scene = game
	game.difficulty = GameSettings.DIFFICULTIES[1]
	game.player = Player.new()
	game.add_child(game.player)
	game.player.position = Vector3(0,0,100)
	game.zombies_root = Node3D.new()
	game.add_child(game.zombies_root)
	Zombie.preload_models(game,["soldier"])
	for i in 3:
		var enemy := game.create_enemy("soldier",Vector3.ZERO,1,true,true)
		await process_frame
		if i%2==0: enemy.queue_free()
		else: game._clear_combat()
		for frame in 3: await process_frame
		if is_instance_valid(enemy) or game.alive_zombies()!=0:
			print("FAIL: Armored enemy was not released")
			quit(1)
			return
	# Give the audio mixer its teardown frame after freeing the fixture. Exiting
	# directly from the last deletion frame leaves an active MP3 decode in use.
	game.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("PLANES_CLEANUP_DONE checks=3 failures=0")
	quit()
