extends SceneTree

var game: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func cash() -> Array:
	return get_nodes_in_group("cash_drops").filter(func(n): return not n._taken and not n.is_queued_for_deletion())

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var p: Player = game.player
	p.set_physics_process(false)
	game.weapons.set_process(false)
	p.global_position = Vector3(0, 60, 0)
	p.score = 250
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	p._unhandled_input(key)
	check(cash().size() == 1 and p.score == 150 and not game.inventory.is_open, "B throws 100 points without opening inventory")
	var first: Pickup = cash()[0]
	check(first.amount == 100 and not first.toss_velocity.is_zero_approx(), "Cash has exact value and initial throwing velocity")
	p._unhandled_input(key)
	check(cash().size() == 1 and p.score == 150, "Rapid duplicate commands cannot create extra bundles")
	check(not first.can_collect(p, game.weapons), "Thrower cannot immediately reclaim cash")
	first.set_physics_process(false)
	first._t = 3.0
	first._on_body(p)
	first._on_body(p)
	check(p.score == 250 and first._taken, "Solo pickup returns exact points only once")
	await process_frame
	p.cash_cooldown = 0
	p.score = 37
	Pickup.throw_cash(p)
	var small: Pickup = cash()[0]
	small.set_physics_process(false)
	check(p.score == 0 and small.amount == 37, "Last partial bundle never overdraws the balance")
	p.cash_cooldown = 0
	Pickup.throw_cash(p)
	check(cash().size() == 1 and p.score == 0, "Empty balance cannot create money")
	small._process(100.0)
	check(not small.is_queued_for_deletion(), "Cash does not expire like zombie supplies")
	small.queue_free()
	await process_frame
	p.score = 100
	p.active = false
	Pickup.throw_cash(p)
	check(cash().is_empty() and p.score == 100, "Menu or inactive player cannot throw")
	p.active = true
	key.physical_keycode = KEY_I
	key.keycode = KEY_I
	game.inventory._unhandled_input(key)
	check(game.inventory.is_open, "I opens inventory after rebinding")
	game.inventory.close()
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	NetSession.world.add_player(3)
	var peer: Player = NetSession.world.actor(2)
	var other: Player = NetSession.world.actor(3)
	for actor in [peer, other]:
		actor.set_physics_process(false)
		actor.active = true
		NetSession.world.weapons[actor.peer_id].set_process(false)
	peer.global_position = p.global_position + Vector3(1, 0, 0)
	other.global_position = peer.global_position
	peer.score = 230
	NetSession.world.action(2, "drop_cash", [99999])
	check(peer.score == 230 and cash().is_empty(), "Client cannot specify its own bundle amount")
	NetSession.world.action(2, "drop_cash", [])
	var drop: Pickup = cash()[0]
	drop.set_physics_process(false)
	drop._t = 0.5
	check(peer.score == 130 and drop.amount == 100 and drop.owner_peer == 2, "Host debits remote sender and owns cash value")
	var snapshot: Dictionary = NetSession.world.snapshot()
	var record: Array = snapshot.drops.values()[0]
	check(record[0] == "cash" and record[3] == 100 and record[4] == 2, "Snapshot sends bundle value and owner to clients")
	NetSession.world._apply_drops(snapshot.drops)
	var replica: Pickup = NetSession.world.drops.values()[0]
	replica.set_physics_process(false)
	check(replica.amount == 100 and replica.owner_peer == 2 and replica._mesh.find_children("*", "Label3D", true, false)[0].text == "100 P", "Receiving snapshot creates visible cash with correct value")
	NetSession.world._apply_drops({})
	check(replica.is_queued_for_deletion() and NetSession.world.drops.is_empty(), "Later snapshot removes collected cash from receiving world")
	NetSession.world.collect_drop(drop, 2)
	check(not drop._taken and peer.score == 130, "Owner grace also applies to host pickup validation")
	p.global_position += Vector3(20, 0, 0)
	NetSession.world.collect_drop(drop, 1)
	check(not drop._taken and p.score == 100, "Distant collection cannot transfer money")
	var total := p.score + peer.score + other.score + drop.amount
	NetSession.world.collect_drop(drop, 3)
	NetSession.world.collect_drop(drop, 1)
	check(other.score == 100 and drop._taken and p.score + peer.score + other.score == total, "Another player receives exact money once, with total conserved")
	await process_frame
	peer.cash_cooldown = 0
	peer.alive = false
	NetSession.world.action(2, "drop_cash", [])
	check(cash().is_empty() and peer.score == 130, "Dead sender cannot drop points")
	peer.alive = true
	NetSession.enabled = false
	p.active = true
	p.global_position = Vector3(0, 60, 0)
	p.rotation = Vector3.ZERO
	p.cash_cooldown = 0
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	shape.shape = box
	floor_body.add_child(shape)
	game.add_child(floor_body)
	floor_body.position = Vector3(0, 59.9, 0)
	await physics_frame
	Pickup.throw_cash(p)
	var falling: Pickup = cash()[0]
	falling.set_physics_process(false)
	for i in 120: falling._physics_process(1.0 / 60.0)
	check(falling.toss_velocity.is_zero_approx() and falling.global_position.y >= 60.0 and falling.global_position.z < -2.0, "Thrown cash follows an arc and lands on collision geometry")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(3, 3, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	game.add_child(wall)
	wall.global_position = Vector3(0, 61, -0.5)
	falling.global_position = Vector3(0, 60.1, -0.8)
	falling._t = 3.0
	await physics_frame
	check(not falling.can_collect(p, game.weapons), "Cash cannot be collected through a wall")
	wall.queue_free()
	var placeholders: Array[Node] = []
	for i in Pickup.MAX_CASH_DROPS - 1:
		var placeholder := Node.new()
		game.add_child(placeholder)
		placeholder.add_to_group("cash_drops")
		placeholders.append(placeholder)
	p.cash_cooldown = 0
	p.score = 100
	Pickup.throw_cash(p)
	check(p.score == 100, "World cash limit rejects throw without losing money")
	for placeholder in placeholders: placeholder.free()
	if "--render-cash" in OS.get_cmdline_user_args():
		floor_body.queue_free()
		game.day_night.set_time_hours(10.0)
		game.achievements.hide()
		falling.global_position = Map.ground_pos(0, -20) + Vector3.UP * 0.06
		p.global_position = Map.ground_pos(0, -22)
		p.camera.look_at(falling.global_position + Vector3.UP * 0.15)
		for i in 6: await process_frame
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../artifacts/cash/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder + "bundle.png")
	print("CASH_DROPS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
