extends SceneTree

const Movement = preload("res://scripts/movement_sync.gd")
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
	# 20 Hz outgoing movement, delayed and missing 10 Hz snapshots. Turning,
	# sprinting and stopping must not turn latency into a position correction.
	for latency_steps in [2, 6, 12, 20]:
		var sync = Movement.new()
		var sent: Dictionary = {}
		var position := Vector3.ZERO
		var worst_error := 0.0
		for step in 160:
			var direction := Vector3.RIGHT if step < 65 else (Vector3.FORWARD if step < 130 else Vector3.ZERO)
			position += direction * Player.SPRINT_SPEED * 0.05
			var seq: int = sync.record(position)
			sent[seq] = position
			var ack: int = seq - latency_steps - (2 if step % 7 == 0 else 0)
			if ack > 0 and step % 2 == 0 and step % 11 != 0:
				var corrected: Vector3 = sync.reconcile(sent[ack], ack, position)
				worst_error = maxf(worst_error, corrected.distance_to(position))
				position = corrected
		check(worst_error < 0.0001, "No rubberbanding with %d ms delayed acknowledgements, jitter and lost snapshots" % (latency_steps * 50))
	var sync = Movement.new()
	var first: int = sync.record(Vector3(2, 0, 0))
	var second: int = sync.record(Vector3(3, 0, 0))
	var current: Vector3 = sync.reconcile(Vector3(1, 0, 0), first, Vector3(4, 0, 0))
	check(current.is_equal_approx(Vector3(3, 0, 0)), "Wall correction preserves movement made since the acknowledged pose")
	current = sync.reconcile(Vector3(2, 0, 0), second, current)
	check(current.is_equal_approx(Vector3(3, 0, 0)), "Pending history does not apply the same correction twice")
	check(sync.reconcile(Vector3.ZERO, first, current) == current, "Stale acknowledgements cannot rewind movement")
	var third: int = sync.record(current)
	check(sync.reconcile(Vector3(50, 0, 0), third, current) == Vector3(50, 0, 0), "Large authoritative corrections still reset invalid positions")
	check(sync.reconcile(Vector3(5, 0, 0), third, current, true) == Vector3(5, 0, 0) and sync.history.is_empty(), "Initial state teleports and clears the old prediction history")
	for i in 400: sync.record(Vector3(i, 0, 0))
	check(sync.history.size() == Movement.HISTORY_LIMIT, "History stays bounded during a network outage")
	# Exercise the actual host capsule against a real physics floor and wall.
	Map.extent()
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 1, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	floor_body.position.y = -0.5
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.5, 4, 10)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	scene.add_child(wall)
	wall.position = Vector3(2, 2, 0)
	var player := Player.new()
	player.remote_actor = true
	scene.add_child(player)
	player.set_physics_process(false)
	var world = preload("res://scripts/coop_world.gd").new()
	world.actors[2] = player
	world.pose_times[2] = 0.0
	await physics_frame
	await physics_frame
	world.move_player(2, Vector3(0.36, -0.05, 0), 0, 0, false, Vector3.RIGHT * 7.2, 0.05, 1)
	check(player.position.x > 0.3 and player.position.y > -0.02, "Host floor contact preserves horizontal walking")
	for step in range(2, 15):
		world.move_player(2, player.position + Vector3(0.36, -0.05, 0), 0, 0, false, Vector3.RIGHT * 7.2, step * 0.05, step)
	check(player.position.x > 1.2 and player.position.x < 1.4, "Host still blocks walking through a wall")
	var before := player.position
	world.move_player(2, before - Vector3(0.3, 0, 0), 0, 0, false, Vector3.ZERO, 0.8, 13)
	check(player.position == before, "Host ignores an older movement sequence")
	world.move_player(2, before + Vector3(100, 0, 0), 0, 0, false, Vector3.ZERO, 0.9, 15)
	check(player.position == before and world.pose_acks[2] == 15, "Rejected teleport is acknowledged so the client can correct it")
	print("MOVEMENT_SYNC_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
