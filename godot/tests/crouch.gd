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
	p.global_position = Map.ground_pos(20, 105)
	p.velocity = Vector3.ZERO
	w.unlocked.smg = true
	w.set_weapon("smg")
	w.ads = 0
	var standing := w.effective_spread()
	check(InputMap.action_has_event("crouch", _ctrl()), "Control key is bound to crouch")
	p.set_crouching(true)
	check(p.crouching and is_equal_approx(p.body_shape.shape.height, 1.2), "Crouching reduces the collision capsule")
	check(is_equal_approx(p.body_shape.position.y - p.body_shape.shape.height * 0.5, 0), "Feet remain fixed when crouching")
	check(is_equal_approx(w.effective_spread(), standing * 0.7), "Crouch reduces actual bullet spread by thirty percent")
	p.velocity.y = 4
	check(p.stance_precision() == 1.0, "Airborne crouch grants no stability bonus")
	p.velocity = Vector3(7, 0, 0)
	check(p.stance_precision() == 1.0, "Fast movement grants no crouch precision bonus")
	p.velocity = Vector3.ZERO
	var ceiling := StaticBody3D.new()
	ceiling.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 0.2, 3)
	collider.shape = box
	ceiling.add_child(collider)
	game.add_child(ceiling)
	ceiling.global_position = p.global_position + Vector3.UP * 1.55
	for i in 3: await physics_frame
	p.set_crouching(false)
	check(p.crouching, "Low ceiling prevents standing into solid geometry")
	ceiling.queue_free()
	for i in 3: await physics_frame
	p.set_crouching(false)
	check(not p.crouching and is_equal_approx(p.body_shape.shape.height, 1.8), "Standing is restored once the ceiling clears")
	Input.action_press("crouch")
	Input.action_press("sprint")
	Input.action_press("move_forward")
	for i in 25:
		p._physics_process(1.0 / 60.0)
		await physics_frame
	check(p.crouching and p.head.position.y < 1.12, "Held Control lowers the camera")
	check(Vector2(p.velocity.x, p.velocity.z).length() < 2.3, "Crouch overrides sprint and halves walking speed")
	Input.action_release("crouch")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var remote: Player = NetSession.world.actor(2)
	remote.global_position = Map.ground_pos(30, 105)
	NetSession.world.move_player(2, remote.global_position, 0, 0, true, Vector3.ZERO, NetSession._elapsed, 1, true)
	check(remote.crouching and is_equal_approx(remote.head.position.y, Player.CROUCH_EYE), "Host applies remote crouch to collision and shooting origin")
	var proxy: Weapons = NetSession.world.weapons[2]
	proxy.set_process(false)
	check(remote.stance_precision() == 0.7, "Host uses crouch precision for remote shots")
	check(NetSession.world.snapshot().players[2].crouch, "Snapshots include crouch for other players")
	NetSession.enabled = false
	if "--render-crouch" in OS.get_cmdline_user_args():
		var avatar = NetSession.world.avatars[2]
		avatar.global_position = remote.global_position
		avatar.rotation.y = 0.5
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.global_position = remote.global_position + Vector3(3.0, 1.7, -3.5)
		camera.look_at(remote.global_position + Vector3.UP * 0.8)
		camera.make_current()
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/crouch"))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/crouch/stance.png"))
	print("CROUCH_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _ctrl() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_CTRL
	return event
