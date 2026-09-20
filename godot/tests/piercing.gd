extends SceneTree

var game: Node
var targets: Array[Zombie] = []
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func prepare(w: Weapons, id: String) -> void:
	w.unlock(id)
	w.set_weapon(id)
	w.spread_mul = 0.0
	w.cur().cooldown = 0.0
	w.cur().reloading = 0.0
	w.cur().ammo = int(w.cur().def.mag)
	for z in targets: z.hp = 10000.0

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	p.set_physics_process(false)
	w.set_process(false)
	p.global_position = Vector3(0, 60, 0)
	p.rotation = Vector3.ZERO
	p.head.rotation = Vector3.ZERO
	p.camera.rotation = Vector3.ZERO
	for i in 6:
		var z := Zombie.new()
		z.setup("brute", p, [], 1.0, Callable())
		z.model_path = ""
		game.zombies_root.add_child(z)
		z.set_physics_process(false)
		z.agent.avoidance_enabled = false
		z.global_position = Vector3(0, 60, -3.0 * (i + 1))
		z.collision_layer = 2
		# Overlapping body parts exercise complete-actor exclusion after a hit.
		for offset in [-0.15, 0.15]:
			var area := Area3D.new()
			area.collision_layer = Zombie.HITBOX_LAYER
			area.collision_mask = 0
			area.set_meta("zombie", z)
			area.set_meta("headshot", false)
			var shape := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 0.3
			shape.shape = sphere
			area.add_child(shape)
			z.add_child(area)
			area.position = Vector3(0, Player.EYE, offset)
			z._hitboxes.append(area)
		targets.append(z)
	await physics_frame
	await physics_frame
	for id in ["pistol", "ak47", "marksman", "titanbreaker", "lmg"]:
		prepare(w, id)
		var shots: int = game.stats.shots
		var hits: int = game.stats.hits
		w.try_fire()
		var spec: Dictionary = Weapons.DEFS[id]
		for i in targets.size():
			var expected := float(spec.damage) * pow(float(spec.get("pierce_retention", 1.0)), i) if i < int(spec.get("pierce_targets", 1)) else 0.0
			check(is_equal_approx(targets[i].hp, 10000.0 - expected), "%s target %d receives its penetration damage once" % [id, i + 1])
		check(w.cur().ammo == int(spec.mag) - 1 and game.stats.shots == shots + 1 and game.stats.hits == hits + 1, id + " uses one bullet and counts one accuracy hit")
	prepare(w, "marksman")
	targets[0]._hitboxes[1].set_meta("headshot", true)
	p.mushroom_effects.fliegenpilz = 20.0
	w.damage_mul = 1.24
	w.try_fire()
	check(is_equal_approx(targets[0].hp, 10000.0 - 165 * 2.48 * 2.2), "First headshot combines with training and mushroom bonus")
	check(is_equal_approx(targets[1].hp, 10000.0 - 165 * 2.48 * 0.75), "Next body hit does not inherit previous headshot multiplier")
	targets[0]._hitboxes[1].set_meta("headshot", false)
	p.mushroom_effects.clear()
	w.damage_mul = 1.0
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 0.2)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = Vector3(0, 61.7, -4.5)
	await physics_frame
	await physics_frame
	prepare(w, "titanbreaker")
	w.try_fire()
	check(targets[0].hp < 10000 and targets[1].hp == 10000, "Solid wall between zombies stops piercing")
	wall.queue_free()
	await physics_frame
	await physics_frame
	NetSession.world.add_player(2)
	var remote: Player = NetSession.world.actor(2)
	remote.set_physics_process(false)
	remote.active = true
	remote.global_position = p.global_position
	remote.rotation = Vector3.ZERO
	remote.head.rotation = Vector3.ZERO
	var proxy: Weapons = NetSession.world.weapons[2]
	proxy.set_process(false)
	prepare(proxy, "marksman")
	NetSession.world.action(2, "fire", ["marksman", 0.0, 0.0, 0.0])
	check(targets[2].hp < 10000 and targets[3].hp == 10000, "Remote player's host fire command penetrates three zombies")
	check(targets[0].killer_peer == 2 and targets[2].killer_peer == 2, "All penetrated targets retain the firing player's attribution")
	prepare(w, "marksman")
	targets[0].hp = 1
	w.try_fire()
	check(not targets[0].alive and targets[1].hp < 10000 and targets[2].hp < 10000, "Lethal first hit still continues through remaining targets")
	print("PIERCING_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
