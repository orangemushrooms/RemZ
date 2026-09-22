# Compare the accelerated heightfield movement to CharacterBody's native solver.
extends SceneTree

var scene: Node3D
var player: Player
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func terrain(slope: float, crest := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("terrain_ground")
	var heights := PackedFloat32Array()
	for z in 65:
		for x in 65:
			var px := float(x - 32)
			heights.append((-absf(px) if crest else px) * slope)
	var shape := HeightMapShape3D.new()
	shape.map_width = 65
	shape.map_depth = 65
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	scene.add_child(body)
	return body

func actor(at: Vector3) -> Zombie:
	var zombie := Zombie.new()
	zombie.setup("runner", player, [], 1.0, Callable())
	zombie.model_path = ""
	zombie.replica = true
	scene.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.agent.avoidance_enabled = false
	zombie.replica = false
	zombie.global_position = at
	return zombie

func walk(zombie: Zombie, frames: int, native: bool, direction := Vector3.RIGHT * 4.2) -> int:
	var accelerated := 0
	for i in frames:
		await physics_frame
		if not zombie.is_on_floor(): zombie.velocity.y -= 20.0 / 60.0
		if native:
			zombie.velocity.x = direction.x
			zombie.velocity.z = direction.z
			zombie.move_and_slide()
		else:
			zombie._on_velocity_computed(direction)
			if zombie._terrain_floor.is_valid(): accelerated += 1
	return accelerated

func obstacle(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	scene.add_child(body)
	body.position = at
	return body

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	player = Player.new()
	player.active = true
	scene.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(20, 20, 20)
	for test in [{"slope": 0.0, "crest": false}, {"slope": 0.2, "crest": false}, {"slope": -0.3, "crest": false}, {"slope": 0.2, "crest": true}]:
		var ground := terrain(test.slope, test.crest)
		var start := Vector3(-3, 2, 0)
		var normal := actor(start)
		await walk(normal, 120, true)
		var expected := normal.global_position
		normal.queue_free()
		await physics_frame
		var fast := actor(start)
		var accelerated := await walk(fast, 120, false)
		check(accelerated > 60, "Heightfield acceleration is used: " + str(test))
		check(fast.is_on_floor(), "Zombie remains grounded: " + str(test))
		check(fast.global_position.distance_to(expected) < 0.06, "Heightfield follows native capsule within 6 cm: " + str(test) + " difference=" + str(fast.global_position - expected))
		fast.queue_free()
		ground.queue_free()
		await physics_frame
	var ground := terrain(0.0)
	for layer in [1, 2, 8, 16]:
		var wall := obstacle(Vector3(2, 1.5, 0), Vector3(0.15, 3, 8), layer)
		var zombie := actor(Vector3(0, 0.1, 0))
		await walk(zombie, 90, false)
		check(zombie.position.x > 1.4 and zombie.position.x < 1.61, "Swept capsule stops before obstacle layer %d" % layer)
		wall.queue_free()
		await physics_frame
		await walk(zombie, 30, false)
		check(zombie.position.x > 3.0, "Destroyed obstacle releases movement, layer %d" % layer)
		zombie.queue_free()
		await physics_frame
	var overlapping := actor(Vector3(0, 0.1, 0))
	await walk(overlapping, 20, false, Vector3.ZERO)
	var blocker := obstacle(Vector3(0.25, 1.5, 0), Vector3(0.5, 3, 8), 16)
	await physics_frame
	await walk(overlapping, 30, false)
	check(overlapping.position.x < -0.33, "Newly overlapping obstacle triggers native penetration recovery")
	blocker.queue_free()
	overlapping.queue_free()
	await physics_frame
	var falling := actor(Vector3(0, 0.1, 0))
	await walk(falling, 30, false)
	ground.queue_free()
	await physics_frame
	await walk(falling, 40, false, Vector3.ZERO)
	check(not falling.is_on_floor() and falling.position.y < -1.0, "Removed ground releases cached floor and restores gravity")
	falling.queue_free()
	print("HORDE_GROUND_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
