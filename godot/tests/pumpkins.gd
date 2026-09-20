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
	check(game.pumpkins.size() == 3, "All three campsite pumpkins have shootable bodies")
	game.achievements.counters.clear()
	game.achievements.session_unlocked.clear()
	w.ads = 1
	w.spread_mul = 0.01
	var before := p.score
	var pumpkin = game.pumpkins[0]
	var shape: CollisionShape3D = pumpkin.get_child(0)
	var centre: Vector3 = shape.global_position
	p.global_position = centre + Vector3(0, 0, 2.5) - Vector3.UP * Player.EYE
	p.camera.look_at(centre)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 0.1)
	cs.shape = box
	wall.add_child(cs)
	game.add_child(wall)
	wall.global_position = centre + Vector3(0, 0, 1)
	for i in 3: await physics_frame
	w.try_fire()
	check(not pumpkin.broken and not game.achievements.session_unlocked.has("pumpkin"), "A solid wall blocks pumpkin shots and achievement progress")
	wall.queue_free()
	for i in 3: await physics_frame
	w.cur().cooldown = 0
	w._aim_kick = Vector2.ZERO
	w.try_fire()
	check(pumpkin.broken, "An actual weapon shot breaks the pumpkin")
	check(not pumpkin.model.visible and pumpkin.collision_layer == 0, "Broken pumpkin disappears and no longer blocks bullets")
	check(not pumpkin.lamp.visible and not pumpkin.lamp.is_in_group("day_night_lamps"), "Lantern is extinguished and cannot relight at night")
	check(game.achievements.session_unlocked.has("pumpkin") and game.achievements.unlocked.has("pumpkin"), "Pumpkin achievement is awarded and added to persistent unlocks")
	check(p.score == before + 25, "Achievement grants 25 points")
	check(not pumpkin.shoot() and game.achievements.counters.pumpkins == 1, "Repeated hits cannot count the same pumpkin twice")
	for target in game.pumpkins.slice(1): target.shoot()
	check(game.achievements.counters.pumpkins == 3 and p.score == before + 25, "Other pumpkins break without duplicate achievement rewards")
	var states: Array = NetSession.world.snapshot().pumpkins
	check(states == [true, true, true], "Coop snapshots retain every destroyed pumpkin for late joiners")
	var count: int = game.achievements.counters.pumpkins
	pumpkin.shatter(false)
	check(game.achievements.counters.pumpkins == count, "Applying replicated destruction never awards progress")
	print("PUMPKINS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
