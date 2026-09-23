extends SceneTree

var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - began > 240000:
		push_error("DEFENCE_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func settle() -> void:
	await physics_frame
	await physics_frame

func run() -> void:
	seed(772)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Player = game.player
	player.score = 2000
	var defence: DefenceSystem = game.defences
	for n in range(1, 25):
		var plan: Array = game.waves.plan(n)
		var count := 0
		for entry in plan:
			if entry.type == "titan":
				count += 1
				check(entry.lane in ["east", "south"] and entry.point.y > 100, "Titan wave %d enters from open field" % n)
		check(plan.size() == game.waves.preview_count(n), "Wave %d preview includes all bosses" % n)
		check(count == Waves.titan_count(n) and (n >= 6 or count == 0) and count <= 3, "Wave %d respects titan progression" % n)
	var bar: Barricade = game.barricades[1]
	check(Waves.titan_count(117) == 3 and Waves.titan_count(120) == 0, "Late titan waves stay bounded and do not overlap worm encounters")
	var boss_positions := {}
	for entry in game.waves.plan(39):
		if entry.type == "titan": boss_positions[entry.point] = true
	check(boss_positions.size() == 3, "Simultaneous bosses have separate field spawns")
	bar.build()
	var normal := Vector3(bar.normal2.x, 0, bar.normal2.y)
	player.global_position = Map.ground_pos(bar.center.x, bar.center.z - 8)
	game.spawn_zombie("shambler", Vector2(bar.center.x, bar.center.z + 2.5), 1, "east")
	var z: Zombie = game.zombies_root.get_child(0)
	await settle()
	await create_timer(3.5, false).timeout
	check(z.siege_target == bar, "Incoming zombie commits to defended entrance")
	check(bar.hp < bar.max_hp(), "Zombie actually damages the barricade")
	check(bar._local(z.global_position).y > 0, "Continuous collision keeps zombie on attacking side")
	player.global_position = Map.ground_pos(bar.center.x + 12, bar.center.z - 5)
	await create_timer(0.7, false).timeout
	check(z.siege_target == bar, "Moving behind the flank does not cancel a committed breach")
	bar.damage(10000)
	await settle()
	check(bar.level == 0, "Destroyed defence releases the route")
	await create_timer(0.5, false).timeout
	check(z.siege_target != bar, "Zombie resumes pursuit after the breach")
	z.queue_free()
	await settle()
	var point := Map.ground_pos(60, 112)
	player.global_position = Map.ground_pos(60, 117) + Vector3.UP * 0.1
	await settle()
	check(defence.placement_error(player, point).is_empty(), "Clear, flat field accepts a tower: " + defence.placement_error(player, point))
	var before := player.score
	check(not defence.purchase(player, point + Vector3(40, 0, 0)).is_empty() and player.score == before, "Remote placement rejected without charging")
	check(not defence.purchase(player, Vector3(NAN, 0, 0)).is_empty(), "Nonfinite placement rejected")
	check(defence.purchase(player, point).is_empty(), "Valid placement builds a tower")
	check(player.score == before - 120 and defence.towers.size() == 1, "Build charges exactly 120 points once")
	check(not defence.purchase(player, point).is_empty() and player.score == before - 120, "Duplicate placement cannot overlap or charge")
	var tower: DefenceTower = defence.towers.values()[0]
	check(tower.body.collision_layer == 8 and tower.hp == 240, "Tower has blocking, destructible structure")
	var field_position := player.global_position
	player.global_position = game.progression.npcs["mechanic"].global_position + Vector3(0, 0.1, 2.3)
	await settle()
	game.waves.completed = 2
	check(defence.maintain(player, tower.tower_id, "upgrade", true).is_empty() and tower.level == 2 and tower.hp == 400, "Upgrade improves tower and restores health")
	player.global_position = field_position
	await settle()
	tower.damage(120)
	before = player.score
	check(defence.maintain(player, tower.tower_id, "repair").is_empty() and tower.hp == 400 and player.score == before - 35, "Tower repair is transactional")
	before = player.score
	check(not defence.maintain(player, tower.tower_id, "repair").is_empty() and player.score == before, "No charge for unnecessary repair")
	player.global_position = game.progression.npcs["mechanic"].global_position + Vector3(0, 0.1, 2.3)
	await settle()
	game.waves.completed = 5
	defence.maintain(player, tower.tower_id, "upgrade", true)
	check(tower.level == 3 and not defence.maintain(player, tower.tower_id, "upgrade", true).is_empty(), "Upgrade cap enforced")
	player.global_position = field_position
	await settle()
	game.spawn_zombie("shambler", Vector2(60, 99), 1)
	z = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.hp = 10000
	await settle()
	check(tower.can_see(z), "Tower sees an exposed enemy")
	await create_timer(3.0, false).timeout
	check(tower.shots > 0 and z.hp < 10000, "Turret acquires, turns and actually damages enemies")
	for i in 12: tower.target = z; tower.shoot()
	check(tower.overheated, "Sustained fire overheats the weapon")
	var block := StaticBody3D.new()
	block.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 8, 1)
	collider.shape = box
	block.add_child(collider)
	game.add_child(block)
	block.global_position = Map.ground_pos(60, 105) + Vector3.UP * 3
	await settle()
	check(not tower.can_see(z), "Solid cover prevents targeting through walls")
	var shots := tower.shots
	await create_timer(0.6, false).timeout
	check(tower.shots == shots, "Covered enemy does not consume firing bursts")
	block.queue_free()
	await settle()
	tower.overheated = false
	tower.heat = 0
	z.hp = 1
	before = player.score
	await create_timer(2.0, false).timeout
	check(not z.alive and player.score > before, "Tower kill credits its builder")
	defence.open(tower)
	check(defence.placing and not paused and player.active, "Tower interaction starts in-world rotation without a remote shop")
	defence.cancel_placement()
	check(not paused and player.active, "Cancelling rotation restores weapon input")
	var id := tower.tower_id
	player.global_position = game.progression.npcs["mechanic"].global_position + Vector3(0, 0.1, 2.3)
	await settle()
	tower.owner_peer = 99
	check(not defence.maintain(player, id, "sell", true).is_empty(), "Team member cannot sell someone else's tower")
	tower.owner_peer = 1
	check(defence.maintain(player, id, "sell", true).is_empty() and not defence.towers.has(id), "Owner can dismantle tower")
	await settle()
	game.waves.wave = 8
	game.spawn_zombie("titan", Vector2(20, 125), 1, "east")
	var titan: Titan = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	titan.set_physics_process(false)
	titan.agent.avoidance_enabled = false
	check(titan.height >= 20 and titan.max_hp >= 2000, "Titan has boss scale and health")
	check(titan.type.model == "zombie_titan" and ResourceLoader.exists("res://assets/models/zombie_titan.glb"), "Dedicated titan asset is installed")
	check(titan.anim != null and titan.anim.has_animation("walk") and titan.anim.has_animation("attack") and titan.anim.has_animation("death"), "Titan has all three rigged animations")
	player.global_position = Map.ground_pos(20, 121)
	player.hp = 100
	titan.begin_strike(player.global_position)
	check(titan.strike_phase == "windup" and titan.warning.visible and player.hp == 100, "Boss attack is visibly telegraphed before damage")
	player.global_position = Map.ground_pos(30, 121)
	titan.resolve_strike()
	check(player.hp == 100, "Leaving the marked impact area avoids boss damage")
	player.global_position = titan.strike_point
	player.max_hp = 200
	player.hp = 200
	titan.resolve_strike()
	check(is_equal_approx(player.hp, 128.32), "Wave-eight normal titan slam uses bounded 71.68 HP damage")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(20, 8, 0.5)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	game.add_child(wall)
	wall.global_position = Map.ground_pos(20, 120) + Vector3.UP * 3.5
	await settle()
	player.global_position = Map.ground_pos(20, 118)
	player.hp = 100
	titan.begin_strike(player.global_position)
	check(titan.strike_point.z > 120.25, "Solid wall anchors the slam outside the defended building")
	titan.resolve_strike()
	check(player.hp == 100, "Closed wall blocks boss area damage")
	check(titan.warning.mesh is ArrayMesh, "Boss warning follows terrain instead of clipping into slopes")
	wall.queue_free()
	await settle()
	titan.damage(10, Vector3.RIGHT)
	titan.shove(Vector3.RIGHT * 20)
	check(titan._stagger == 0 and titan._knock == Vector3.ZERO, "Titan resists bullet stun-lock and melee knockback")
	var state := titan.boss_state()
	check(state.size() == 4 and state[2] == titan.strike_point and state[3] == titan.impact_serial, "Boss snapshot carries exact telegraph and impact event")
	titan.damage(100000, Vector3.ZERO)
	check(not titan.alive and not titan.warning.visible and titan.collision_layer == 0, "Boss death releases collision and removes warning")
	# Follow the real field approach all the way to the defended gate.
	player.hp = 10000
	player.max_hp = 10000
	player.global_position = Map.ground_pos(7.5, 53)
	bar.build()
	game.spawn_zombie("titan", Vector2(10, 126), 1, "east")
	var approaching: Titan = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	var start := approaching.global_position
	await create_timer(9.0, false).timeout
	check(approaching.global_position.distance_to(start) > 6, "Giant can physically walk off its field spawn")
	await create_timer(34.0, false).timeout
	check(approaching.global_position.z < 82, "Giant navigates the actual field to the entrance")
	check(approaching.siege_target == bar or bar.hp <= 0, "Giant engages the defended gateway")
	# The walk across the field plus a wind-up is close to the fixed wait above, so poll for the
	# first slam instead of assuming it already landed.
	var waited := 0.0
	while bar.hp >= bar.max_hp() and bar.level > 0 and waited < 45.0:
		await create_timer(1.0, false).timeout
		waited += 1.0
	var gap := approaching.global_position.distance_to(bar.attack_point(approaching.global_position))
	check(bar.hp < bar.max_hp() or bar.level == 0, "Field approach ends in actual boss damage to the gate (after %.0f s extra, gap %.1f m, reach %.1f, phase %s, impacts %d, hp %.0f/%.0f)" % [waited, gap, float(approaching.type.reach), approaching.strike_phase, approaching.impact_serial, bar.hp, bar.max_hp()])
	print("DEFENCE_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
