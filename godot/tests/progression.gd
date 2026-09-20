extends SceneTree

var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000: quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func visit(id: String) -> void:
	game.player.global_position = (game.progression.cache_node if id == "cache" else game.progression.npcs[id]).global_position + Vector3(0, 0.1, 2.3)
	await physics_frame
	await physics_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	var shop: Progression = game.progression
	p.score = 5000
	for id in Weapons.ORDER:
		check(w.unlocked[id] == (id == "pistol"), id + " starts with the correct ownership")
		check(ResourceLoader.exists("res://assets/models/%s.glb" % Weapons.DEFS[id].model), id + " has a production mesh")
	for id in Progression.NPCS:
		check(shop.npcs[id].anim != null and shop.npcs[id].anim.is_playing(), id + " has a rigged animated NPC")
	var weapon_pickups := 0
	for item in game.loots:
		if item is Loot and item.kind == "weapon": weapon_pickups += 1
	check(weapon_pickups == 0, "World loot cannot bypass merchant unlocks")
	var before := p.score
	shop.transact(p, "camp", "weapon", "revolver")
	check(p.score == before and not w.unlocked.revolver, "Remote merchant purchase rejected atomically")
	await visit("camp")
	check(shop.close_enough(p, "camp"), "Camp merchant reachable in actual world")
	shop.interact("camp")
	check(shop.is_open and paused and not p.active, "NPC interaction opens shop and pauses solo")
	for page in ["Handel", "Aufträge", "Training", "Türme", "Skins"]:
		shop.page = page
		shop._render()
		check(shop.rows.get_child_count() > 0, "Shop page renders: " + page)
		for widgets in shop._row_nodes:
			check(widgets[3] is TextureRect and widgets[3].texture != null and widgets[3].mouse_filter == Control.MOUSE_FILTER_IGNORE, "Shop icon loads without intercepting clicks: " + widgets[0].text)
	shop.page = "Handel"
	shop._render()
	var first_button: Button = shop._row_nodes[0][2]
	shop.team.kills += 1
	shop._render()
	check(is_instance_valid(first_button) and first_button == shop._row_nodes[0][2], "Live shop refresh preserves the button under the pointer")
	shop.close()
	check(not paused and p.active, "Leaving merchant restores controls")
	shop.transact(p, "camp", "weapon", "revolver")
	check(not w.unlocked.revolver and p.score == before, "Points alone cannot bypass quest and wave gates")
	shop.transact(p, "camp", "quest", "arrival")
	check(not shop.has_claim(p.peer_id, "arrival"), "Accepting a quest does not claim its reward")
	check(Sfx._voices.has("quest_accept"), "Accepted quest plays its dedicated sound")
	shop.transact(p, "camp", "quest", "arrival")
	check(shop.has_claim(p.peer_id, "arrival") and p.score == before + 20, "Completed quest pays exactly once")
	check(Sfx._voices.has("quest_complete"), "Quest reward plays completion sound")
	var completion_voices: Array = Sfx._voices["quest_complete"].duplicate()
	var rewarded_score := p.score
	shop.transact(p, "camp", "quest", "arrival")
	check(p.score == rewarded_score, "Repeated quest claim cannot duplicate points")
	check(Sfx._voices["quest_complete"] == completion_voices, "Rejected duplicate reward stays silent")
	shop.transact(p, "camp", "weapon", "revolver")
	check(not w.unlocked.revolver, "Quest completion still requires surviving wave one")
	game.waves.completed = 1
	p.score = 219
	shop.transact(p, "camp", "weapon", "revolver")
	check(not w.unlocked.revolver and p.score == 219, "Insufficient funds preserve ownership and balance")
	p.score = 220
	shop.transact(p, "camp", "weapon", "revolver")
	check(w.unlocked.revolver and p.score == 0 and w.state.revolver.reserve == 12, "Eligible weapon purchase charges once with bounded starting ammunition")
	check(Sfx._voices.has("weapon_pickup"), "Purchased weapon plays gun pickup sound")
	shop.transact(p, "camp", "weapon", "revolver")
	check(p.score == 0, "Duplicate purchase never charges again")
	p.score = 5000
	w.state.revolver.reserve = 0
	w.refill_all()
	check(w.state.revolver.reserve == 0 and w.state.pistol.reserve >= 36, "Wave safety net does not refill premium ammunition")
	w.add_ammo("revolver", 100000)
	before = p.score
	shop.transact(p, "camp", "ammo", "revolver")
	check(w.state.revolver.reserve == w.reserve_limit("revolver") and p.score == before, "Full ammunition cannot consume purchase points")
	shop.transact(p, "mechanic", "training", "damage")
	check(w.damage_mul == 1.0, "Training cannot be bought at another NPC")
	await visit("mechanic")
	before = p.score
	shop.transact(p, "mechanic", "training", "w_ak47")
	check(p.score == before and not w.unlocked.ak47, "Legacy weapon upgrade ID cannot bypass progression")
	shop.transact(p, "mechanic", "training", "damage")
	check(is_equal_approx(w.damage_mul, 1.12) and p.score == before - 120, "Training applies and charges at the mechanic")
	shop.transact(p, "mechanic", "quest", "watch")
	check(not shop.complete("watch"), "Tower quest requires actual defence work")
	var point := Map.ground_pos(60, 112)
	p.global_position = Map.ground_pos(60, 117) + Vector3.UP * 0.1
	await physics_frame
	await physics_frame
	var error: String = game.defences.purchase(p, point, 0.0)
	check(error.is_empty(), "Valid oriented tower placement: " + error)
	var tower: DefenceTower = game.defences.towers.values()[0]
	check(not game.defences.rotate_tower(p, tower.tower_id, NAN).is_empty(), "Non-finite tower rotation rejected")
	check(game.defences.rotate_tower(p, tower.tower_id, PI / 2).is_empty() and is_equal_approx(tower.rotation.y, PI / 2), "Existing tower rotates authoritatively")
	check(shop.team.built == 1 and shop.team.turned == 1, "Defence tutorial observes real placement and rotation")
	game.barricades[0].build()
	check(shop.complete("watch"), "Defence quest completes with a built line and rotated tower")
	before = p.score
	game.defences.maintain(p, tower.tower_id, "upgrade")
	check(tower.level == 1 and p.score == before, "Turret upgrades require the mechanic")
	await visit("mechanic")
	shop.transact(p, "mechanic", "tower_upgrade", str(tower.tower_id))
	check(tower.level == 2 and p.score == before - 100, "Mechanic upgrades deployed tower transactionally")
	shop.transact(p, "mechanic", "quest", "watch")
	shop.transact(p, "mechanic", "quest", "supplies")
	await visit("cache")
	check(shop.close_enough(p, "cache"), "Supply objective reachable")
	shop.transact(p, "cache", "cache", "")
	check(shop.team.cache, "World interaction collects shared delivery")
	await visit("mechanic")
	shop.transact(p, "mechanic", "quest", "supplies")
	check(shop.has_claim(p.peer_id, "supplies"), "Delivery must be returned to claim its reward")
	await visit("secret")
	shop.transact(p, "secret", "visit", "")
	check(shop.local_data().discovered, "Secret merchant discovered by reaching the actual NPC")
	game.waves.completed = 9
	shop.transact(p, "secret", "weapon", "titanbreaker")
	check(not w.unlocked.titanbreaker, "Top weapon additionally requires a defeated titan")
	shop.transact(p, "secret", "quest", "titan")
	shop.event("titans")
	shop.transact(p, "secret", "quest", "titan")
	shop.transact(p, "secret", "weapon", "titanbreaker")
	check(w.unlocked.titanbreaker, "Earned late-game titan weapon can be purchased")
	var damage_before := w.damage_mul
	shop.transact(p, "secret", "skin", "bone", "titanbreaker")
	check(w.skins.get("titanbreaker") == "bone" and damage_before == w.damage_mul, "Purchased skin is cosmetic and equips its material")
	before = p.score
	shop.transact(p, "secret", "skin", "bone", "titanbreaker")
	check(p.score == before, "Owned skin can be equipped again without repurchasing")
	var state := shop.snapshot()
	shop.apply_snapshot(state)
	check(shop.team.titans == 1 and shop.local_data().skins.has("titanbreaker:bone"), "Progression snapshot preserves shared goals and individual skin ownership")
	# Test the specialist gun against a real giant collider, through the real hitscan.
	p.global_position = Map.ground_pos(80, 125) + Vector3.UP * 0.1
	game.spawn_zombie("titan", Vector2(80, 95), 1, "east")
	var titan: Titan = game.zombies_root.get_children().back()
	titan.set_physics_process(false)
	titan.agent.avoidance_enabled = false
	titan.hp = 10000
	titan.max_hp = 10000
	await physics_frame
	await physics_frame
	w.set_weapon("titanbreaker")
	p.camera.look_at(titan.global_position + Vector3.UP * titan.height * 0.55)
	w.ads = 1
	w.try_fire()
	check(w.cur().ammo == 3 and is_equal_approx(titan.hp, 10000 - 420 * 1.75 * w.damage_mul), "Titan rifle applies its specialist damage through a real bullet hit")
	titan.queue_free()
	await create_timer(0.35).timeout # Let the merchant-close input guard expire.
	Input.action_press("aim")
	w._handle_weapon_input(1.0)
	Input.action_release("aim")
	check(is_equal_approx(p.camera.fov, 26.0), "Heavy optic has its own aiming magnification")
	var front: Zombie = Zombie.new()
	front.setup("shambler", p, game.barricades, 1, Callable())
	game.zombies_root.add_child(front)
	front.global_position = tower.global_position + Vector3(-8, 0, 0)
	front.set_physics_process(false)
	front.agent.avoidance_enabled = false
	await physics_frame
	await physics_frame
	check(tower.can_see(front), "Rotated turret acquires an enemy inside its new firing arc")
	front.global_position = tower.global_position + Vector3(8, 0, 0)
	await physics_frame
	check(not tower.can_see(front), "Rotated turret does not fire behind its covered sector")
	front.queue_free()
	print("PROGRESSION_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
