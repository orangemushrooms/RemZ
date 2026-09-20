extends SceneTree

var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func make_drop(kind: String, position: Vector3) -> Pickup:
	var drop := Pickup.new()
	drop.setup(kind)
	game.add_child(drop)
	drop.global_position = position
	drop.set_physics_process(false)
	return drop

func fill(p: Player, w: Weapons) -> void:
	w.grenades = w.grenades_max
	w.state[w.current].reserve = w.reserve_limit(w.current)
	p.hp = p.max_hp

func make_space(kind: String, p: Player, w: Weapons) -> void:
	match kind:
		"grenade": w.grenades -= 1
		"ammo": w.state[w.current].reserve -= 1
		_: p.hp -= 1.0

func full(kind: String, p: Player, w: Weapons) -> bool:
	match kind:
		"grenade": return w.grenades == w.grenades_max
		"ammo": return w.state[w.current].reserve == w.reserve_limit(w.current)
		_: return p.hp == p.max_hp

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.player.global_position = Vector3(0, 60, 0)
	for networked in [false, true]:
		NetSession.enabled = networked
		if networked:
			NetSession.world.add_player(2)
		var p: Player = NetSession.world.actor(2) if networked else game.player
		var w: Weapons = NetSession.world.weapons[2] if networked else game.weapons
		p.set_physics_process(false)
		w.set_process(false)
		p.global_position = Vector3(0, 60, 0)
		for kind in ["grenade", "ammo", "medkit"]:
			fill(p, w)
			var drop := make_drop(kind, p.global_position)
			drop._on_body(p)
			check(not drop._taken and not drop.is_queued_for_deletion() and drop.visible, "%s remains when full (coop=%s)" % [kind, networked])
			make_space(kind, p, w)
			drop._on_body(p)
			check(drop._taken and drop.is_queued_for_deletion() and full(kind, p, w), "%s is collected after space opens without exceeding capacity (coop=%s)" % [kind, networked])
			make_space(kind, p, w)
			drop._on_body(p)
			check(not full(kind, p, w), "%s cannot be collected twice (coop=%s)" % [kind, networked])
			await process_frame
		fill(p, w)
		var loot := Loot.new()
		loot.setup("ammo", "", "Munition")
		game.add_child(loot)
		loot.global_position = p.camera.global_position - Vector3.UP * 0.3 + Vector3.FORWARD
		if networked:
			NetSession.world.loot_nodes["capacity_test"] = loot
			NetSession.world.collect_loot(2, "capacity_test")
		else:
			loot.take(w, p.hud)
		check(not loot.taken and loot.visible and not loot.is_queued_for_deletion(), "World ammunition stays when full (coop=%s)" % networked)
		make_space("ammo", p, w)
		if networked: NetSession.world.collect_loot(2, "capacity_test")
		else: loot.take(w, p.hud)
		check(loot.taken and full("ammo", p, w), "World ammunition can be collected later (coop=%s)" % networked)
		await process_frame
	NetSession.enabled = false
	var p: Player = game.player
	var w: Weapons = game.weapons
	fill(p, w)
	var drop := make_drop("grenade", p.global_position)
	await physics_frame
	await physics_frame
	check(drop.get_overlapping_bodies().has(p) and not drop._taken, "Standing on a drop with full pockets leaves it available")
	w.grenades -= 1
	drop._physics_process(0.3)
	check(drop._taken and w.grenades == w.grenades_max, "Drop is retried without leaving and re-entering its area")
	print("PICKUP_CAPACITY_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
