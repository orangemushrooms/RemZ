extends SceneTree

var checks := 0
var failures := 0
var game: Node3D
func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("FIREWORKS_TIMEOUT"); quit(2))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.weapons.set_process(false)
	game.day_night.set_process(false)
	var f: Fireworks = game.fireworks
	var p: Player = game.player
	p.set_physics_process(false)
	p.score = 1000
	p.global_position = game.progression.npcs.camp.global_position + Vector3(0, 0, 1)
	var result: String = game.progression.transact(p, "camp", "firework", "fw_ruby")
	check(f.stock(p.peer_id).fw_ruby == 1 and p.score == 955, "Vendor purchase grants exactly one rocket and deducts its price")
	check(result.contains("Rubinstern"), "Purchase explains inventory selection")
	game.progression.transact(p, "camp", "firework", "fw_cracker")
	check(f.stock(p.peer_id).fw_cracker == 5 and p.score == 920, "Cracker pack grants five individual uses")
	var before := p.score
	f.buy(p, "invalid")
	check(p.score == before, "Unknown item never spends points")
	p.score = 0
	f.buy(p, "fw_gold")
	check(f.stock(p.peer_id).fw_gold == 0, "Insufficient funds cannot create stock")
	p.score = 10000
	f.stock(p.peer_id).fw_cracker = 18
	f.buy(p, "fw_cracker")
	check(f.stock(p.peer_id).fw_cracker == 18 and p.score == 10000, "Pack that exceeds capacity is rejected atomically")
	f.stock(p.peer_id).fw_ruby = 8
	f.stock(p.peer_id).fw_aurora = 6
	f.buy(p, "fw_gold")
	check(f.stock(p.peer_id).fw_gold == 0, "Shared firework bag capacity is enforced")
	p.global_position = Map.ground_pos(-100, 155) + Vector3.UP * 0.1
	game.progression.transact(p, "camp", "firework", "fw_gold")
	check(f.stock(p.peer_id).fw_gold == 0, "Remote shopping is rejected")
	for id in Fireworks.DEFS: f.stock(p.peer_id)[id] = 2
	p.rotation.y = 0
	p.pitch = 0
	p.head.rotation.x = 0
	for i in 3: await physics_frame
	game.inventory.open()
	f.select("fw_ruby")
	check(f.armed and not game.inventory.is_open and not paused and not game.weapons.cur().node.visible, "Inventory selection equips firework, closes menu and resumes play")
	f.cancel()
	check(not f.armed and game.weapons.viewmodel.visible, "Cancel restores the weapon without consuming an item")
	check(f.stock(p.peer_id).fw_ruby == 2, "Selection and cancellation do not consume stock")
	f.select("fw_ruby")
	game.inventory.open()
	f.cancel()
	game.weapons.set_weapon("pistol")
	game.inventory.close()
	check(game.weapons.viewmodel.visible and game.weapons.cur().node.visible and not f.armed, "Choosing a weapon in the inventory restores its first-person model")
	result = f.ignite(p, "fw_ruby")
	check(result.is_empty() and f.stock(p.peer_id).fw_ruby == 1 and f.active.size() == 1, "Outdoor rocket consumes exactly one unit and creates one effect")
	f.ignite(p, "fw_ruby")
	check(f.stock(p.peer_id).fw_ruby == 1, "Duplicate ignition during cooldown cannot consume twice")
	f.cooldowns.clear()
	p.alive = false
	f.ignite(p, "fw_gold")
	check(f.stock(p.peer_id).fw_gold == 2, "Downed players cannot ignite fireworks")
	p.alive = true
	p.active = false
	f.ignite(p, "fw_gold")
	check(f.stock(p.peer_id).fw_gold == 2, "Menus prevent accidental ignition")
	p.active = true
	var roof := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.3, 4)
	collision.shape = box
	roof.add_child(collision)
	game.add_child(roof)
	roof.global_position = p.global_position + Vector3(0, 3, -1.8)
	for i in 3: await physics_frame
	result = f.ignite(p, "fw_gold")
	check(not result.is_empty() and f.stock(p.peer_id).fw_gold == 2, "Ceiling blocks rocket placement without consuming it")
	roof.queue_free()
	for i in 3: await physics_frame
	result = f.ignite(p, "fw_cracker")
	check(result.is_empty() and f.stock(p.peer_id).fw_cracker == 1, "Cracker ignition consumes one piece from its pack")
	var cracker = f.active[f.next_id - 1]
	check(cracker.flight_path.size() > 1 and cracker.landing.y < p.camera.global_position.y, "Cracker trajectory lands on actual terrain")
	var data: Dictionary = f.snapshot()
	var replica := Fireworks.new()
	game.add_child(replica)
	replica.setup(game)
	replica.apply_snapshot(data)
	check(replica.stocks == f.stocks and replica.active.size() == f.active.size(), "Snapshot carries all players' stocks and active fireworks")
	replica.apply_snapshot(data)
	check(replica.active.size() == f.active.size(), "Repeated snapshots do not duplicate effects")
	var late: Dictionary = data.duplicate(true)
	for id in late.active: late.active[id][4] = 5.0
	replica.apply_snapshot(late)
	for effect in replica.active.values(): effect._tick()
	var all_burst := true
	for effect in replica.active.values(): all_burst = all_burst and effect.burst
	check(all_burst, "Late-join timeline reconstructs already expanded bursts")
	replica.apply_snapshot({"stocks": data.stocks, "active": {}})
	check(replica.active.is_empty(), "Expired effects disappear from clients")
	replica.queue_free()
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var remote: Player = NetSession.world.actor(2)
	remote.active = true
	remote.global_position = p.global_position + Vector3.RIGHT * 5
	f.stock(2).fw_cracker = 2
	NetSession.world.action(2, "firework", ["fw_cracker", 0.0, 0.0])
	check(f.stock(2).fw_cracker == 1 and f.stock(1).fw_cracker == 1, "Coop command consumes only the sender's stock")
	NetSession.world.action(2, "firework", ["fw_cracker", NAN, 0.0])
	check(f.stock(2).fw_cracker == 1, "Non-finite aim is rejected")
	check(NetSession.world.snapshot().has("fireworks"), "World snapshot includes fireworks")
	NetSession.enabled = false
	for id in ["firework_rocket", "firework_cracker"]:
		check(ResourceLoader.exists("res://assets/models/" + id + ".glb"), "Meshy model imported: " + id)
	for effect in f.active.values():
		if is_instance_valid(effect): effect.queue_free()
	f.active.clear()
	f.cooldowns.clear()
	# Real input route: the same left click must never fire the equipped gun as well.
	f.stock(p.peer_id).fw_cracker = 2
	p.active = true
	f.select("fw_cracker")
	f.input_grace = 0
	await process_frame
	var ammo_before: int = game.weapons.cur().ammo
	game.weapons.set_process(true)
	Input.action_press("fire")
	await process_frame
	await process_frame
	Input.action_release("fire")
	game.weapons.set_process(false)
	check(f.stock(p.peer_id).fw_cracker == 1 and game.weapons.cur().ammo == ammo_before, "Left click ignites selected firework without firing the weapon")
	f.cancel()
	for effect in f.active.values(): effect.queue_free()
	f.active.clear()
	f.cooldowns.clear()
	# A close wall terminates the sampled throw instead of allowing a teleport through it.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4, 4, 0.3)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	game.add_child(wall)
	wall.global_position = p.global_position + Vector3(0, 1, -2)
	for i in 3: await physics_frame
	f.ignite(p, "fw_cracker")
	var blocked_throw = f.active[f.next_id - 1]
	check(blocked_throw.landing.z > wall.global_position.z, "Thrown cracker cannot cross a nearby wall")
	wall.queue_free()
	for effect in f.active.values(): effect.queue_free()
	f.active.clear()
	f.cooldowns.clear()
	for i in Fireworks.MAX_ACTIVE:
		var dummy := Node3D.new()
		f.add_child(dummy)
		f.active[i] = dummy
	before = f.stock(p.peer_id).fw_gold
	f.ignite(p, "fw_gold")
	check(f.stock(p.peer_id).fw_gold == before and f.active.size() == Fireworks.MAX_ACTIVE, "Effect limit refuses extra fireworks without consuming stock")
	for effect in f.active.values(): effect.queue_free()
	f.active.clear()
	f.stock(p.peer_id).fw_cracker = 1
	if "--render-fireworks" in OS.get_cmdline_user_args(): await render(f, p)
	print("FIREWORKS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func capture(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/fireworks/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + name + ".png")

func render(f: Fireworks, p: Player) -> void:
	game.day_night.set_time_hours(12.0)
	p.global_position = game.progression.npcs.camp.global_position + Vector3(0, 0, 1)
	p.active = false
	game.progression.shop = "camp"
	game.progression.page = "Feuerwerk"
	game.progression.is_open = true
	game.progression.panel.show()
	game.progression._render()
	await capture("vendor")
	game.progression.close()
	p.global_position = Map.ground_pos(-100, 155) + Vector3.UP * 0.1
	game.inventory.open()
	await capture("inventory")
	f.select("fw_ruby")
	await capture("held-rocket")
	f.select("fw_cracker")
	await capture("held-cracker")
	f.cancel()
	game.weapons.viewmodel.hide()
	game.day_night.set_time_hours(23.0)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.make_current()
	var center: Vector3 = Map.ground_pos(-100, 155)
	camera.global_position = center + Vector3(0, 1.7, 26)
	camera.look_at(center + Vector3.UP * 32)
	for id in ["fw_ruby", "fw_aurora", "fw_gold"]:
		var effect = Fireworks.Effect.new()
		effect.configure(id, center, center, 7331, 4.65)
		game.add_child(effect)
		effect.set_process(false)
		await capture(id)
		effect.queue_free()
	# Render the cracker at ground level, early enough to catch its flash and sparks.
	camera.global_position = center + Vector3(1.6, 1.2, 2.7)
	camera.look_at(center + Vector3.UP * 0.2)
	var cracker = Fireworks.Effect.new()
	cracker.configure("fw_cracker", center, center + Vector3.UP * 0.1, 7331, 2.53)
	game.add_child(cracker)
	cracker.set_process(false)
	await capture("cracker-burst")
	cracker.queue_free()
	# Allow complete live effects to finish and measure cleanup.
	var effect = Fireworks.Effect.new()
	effect.configure("fw_gold", center, center, 42, 10.9)
	game.add_child(effect)
	await create_timer(0.5).timeout
	check(not is_instance_valid(effect), "Finished visual and audio nodes clean up automatically")
