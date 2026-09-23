extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	# The skin comes from randi() and the walk cycle kept playing, so the hip-high ray sometimes
	# slipped between two hit volumes of a random pose. Fix both; the barricade is what is tested.
	seed(4242)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var bar: Barricade = game.barricades[0]
	var normal := Vector3(bar.normal2.x, 0, bar.normal2.y)
	game.player.global_position = bar.center - normal * 3
	# Skin, size (0.94-1.08) and pose speed come from the global RNG, which the threaded world build
	# draws from a varying number of times, so the seed above did not hold here: pin the model and
	# seed again right before this one zombie.
	Zombie.force_skin = "zombie_shambler"
	seed(4242)
	var zombie := Zombie.new()
	zombie.setup("shambler", game.player, game.barricades, 1.0, Callable())
	Zombie.force_skin = ""
	game.zombies_root.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.agent.avoidance_enabled = false
	zombie.anim.pause()
	zombie.global_position = bar.center + normal * 3
	zombie.hp = 10000
	game.weapons.spread_mul = 0
	game.player.camera.look_at(zombie.global_position + Vector3.UP * 0.8)
	for level in range(1, 4):
		bar.build()
		await physics_frame
		await physics_frame
		var query := PhysicsRayQueryParameters3D.create(game.player.camera.global_position, zombie.global_position + Vector3.UP * 0.8, 1 | 2 | 8)
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == bar.body, "Level %d still blocks movement ray" % level)
		var before := zombie.hp
		game.weapons.cur().cooldown = 0.0
		game.weapons.try_fire()
		check(zombie.hp < before, "Real bullet hits zombie through level %d barricade" % level)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 4, 2)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = bar.center + Vector3.UP
	await physics_frame
	await physics_frame
	var before := zombie.hp
	game.weapons.cur().cooldown = 0.0
	game.weapons.try_fire()
	check(zombie.hp == before, "Solid wall still blocks bullets behind the barricade")
	print("BARRICADE_SHOOTING_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
