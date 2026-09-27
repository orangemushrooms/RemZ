extends SceneTree
var game: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", message)

func equipment() -> Array:
	return game.get_children().filter(func(n): return n is Pickup and not n.rarity.is_empty() and not n.is_queued_for_deletion())

func drop_at(p: Player, kind: String, id: String) -> Pickup:
	var drop := TitanLoot.spawn(game, p.global_position, {"kind": kind, "id": id})
	drop.set_physics_process(false)
	drop.global_position = p.global_position
	drop._t = TitanLoot.COLLECT_DELAY
	return drop

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73193
	var counts := {"epic": 0, "legendary": 0, "": 0}
	for i in 20000:
		var reward := TitanLoot.roll(rng)
		counts["" if reward.is_empty() else TitanLoot.rarity(reward.kind, reward.id)] += 1
	check(absf(counts.epic / 20000.0 - 0.35) < 0.01 and absf(counts.legendary / 20000.0 - 0.10) < 0.01, "Seeded drop distribution matches 35%% epic / 10%% legendary (%s)" % str(counts))
	check(counts[""] > 10000, "Bonus equipment is optional, not guaranteed")
	check(TitanLoot.pool("epic").size() > 1 and TitanLoot.pool("legendary").any(func(r): return r.kind == "relic") and TitanLoot.pool("legendary").any(func(r): return r.kind == "weapon"), "Pools include several epic weapons plus legendary weapons and relics")
	check(TitanLoot.rarity("weapon", "pistol").is_empty() and TitanLoot.rarity("relic", "fire").is_empty() and TitanLoot.rarity("weapon", "missing").is_empty(), "Ordinary items and invalid ids cannot masquerade as rare equipment")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.player.global_position = Vector3(0, 60, 0)
	# Use the actual death path with a known private RNG seed for each rarity.
	for tier in ["epic", "legendary"]:
		var chosen_seed := 0
		for candidate in 1000:
			rng.seed = candidate
			var result := TitanLoot.roll(rng)
			if not result.is_empty() and TitanLoot.rarity(result.kind, result.id) == tier:
				chosen_seed = candidate
				break
		game.spawn_zombie("titan", Vector2(15, 126), 1, "east")
		var titan: Titan = game.zombies_root.get_children().back()
		titan.set_physics_process(false)
		titan._loot_rng.seed = chosen_seed
		var before := equipment().size()
		titan.die(Vector3.ZERO)
		var drops := equipment()
		check(drops.size() == before + 1 and drops.back().rarity == tier, "Actual titan death can drop " + tier)
		titan.die(Vector3.ZERO)
		check(equipment().size() == drops.size(), "Repeated death cannot duplicate the reward")
		var reward: Pickup = drops.back()
		check(absf(reward.global_position.y - Map.ground_height(reward.global_position.x, reward.global_position.z) - 0.08) < 0.01, "Reward rests on terrain instead of the titan's pivot")
		for drop in drops: drop.queue_free()
		await process_frame
	game.spawn_zombie("titan", Vector2(15, 126), 1, "east")
	var replica: Titan = game.zombies_root.get_children().back()
	replica.replica = true
	replica.set_physics_process(false)
	replica.die(Vector3.ZERO)
	check(equipment().is_empty(), "Replica death never creates its own equipment")
	for networked in [false, true]:
		NetSession.enabled = networked
		if networked: NetSession.world.add_player(2)
		var p: Player = NetSession.world.actor(2) if networked else game.player
		var w: Weapons = NetSession.world.weapons[2] if networked else game.weapons
		p.set_physics_process(false)
		w.set_process(false)
		p.global_position = Vector3(0, 60, 0)
		for id in ["cryo_smg", "titanbreaker"]:
			w.unlocked[id] = false
			var drop := drop_at(p, "weapon", id)
			drop._t = 0
			check(not drop.can_collect(p, w), "Equipment waits for the titan's collapse")
			drop._t = TitanLoot.COLLECT_DELAY
			check(drop.beacon != null and drop.beacon.tier == drop.rarity, "Weapon has its rarity-colored beacon")
			var size := Barricade._bounds(drop._mesh).size
			check(is_equal_approx(size[size.max_axis_index()], 0.85), "Dropped weapon has a consistent visible world size despite nested model transforms")
			if networked:
				p.position.x += 10
				NetSession.world.collect_drop(drop, 2)
				check(not drop._taken and not w.unlocked[id], "Remote players cannot collect equipment from far away")
				p.position.x -= 10
			drop._on_body(p)
			check(drop._taken and w.unlocked[id] and w.state[id].ammo > 0 and w.state[id].reserve <= w.reserve_limit(id), "Equipment unlocks with usable capped ammo (coop=%s)" % networked)
			w.state[id].reserve = 0
			drop._on_body(p)
			check(w.state[id].reserve == 0, "An equipment pickup cannot grant twice")
			await process_frame
			var duplicate := drop_at(p, "weapon", id)
			w.state[id].reserve = w.reserve_limit(id)
			duplicate._on_body(p)
			check(not duplicate._taken and duplicate.beacon.visible, "Full ammo leaves duplicate equipment and its beam for teammates")
			w.state[id].reserve -= 1
			duplicate._on_body(p)
			check(duplicate._taken and w.state[id].reserve == w.reserve_limit(id), "Duplicate weapon only replenishes missing ammunition")
			await process_frame
		var data: Dictionary = game.progression.rare_market.data(p.peer_id)
		data.owned.erase("hawk")
		var previous: String = p.relic
		var relic := drop_at(p, "relic", "hawk")
		relic._on_body(p)
		check(relic._taken and data.owned.get("hawk", false) and p.relic == previous, "Legendary relic enters inventory without replacing the active talisman")
		await process_frame
		var duplicate := drop_at(p, "relic", "hawk")
		duplicate._on_body(p)
		check(not duplicate._taken, "Owned legendary relic stays available for teammates")
		duplicate.queue_free()
		await process_frame
	NetSession.enabled = false
	var lasting := drop_at(game.player, "weapon", "titanbreaker")
	lasting._process(50)
	check(not lasting.is_queued_for_deletion() and lasting.beacon.visible, "Rare equipment remains longer than normal 45-second supplies")
	lasting._process(TitanLoot.LIFETIME)
	check(lasting.is_queued_for_deletion(), "Expired equipment removes its beacon together with the item")
	await process_frame
	NetSession.enabled = true
	var source := drop_at(game.player, "relic", "bark")
	var states: Dictionary = NetSession.world.snapshot().drops
	NetSession.world._apply_drops(states)
	var found := false
	for node in NetSession.world.drops.values():
		node.set_physics_process(false)
		if node.item_id == "bark": found = node.rarity == "legendary" and node.beacon != null and node._t == source._t
	check(found, "Snapshot carries item identity, age and beacon to a newly created replica")
	NetSession.world._apply_drops({})
	check(NetSession.world.drops.is_empty(), "Collected or expired drops disappear from replica state")
	NetSession.enabled = false
	print("TITAN_LOOT_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
