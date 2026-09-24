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
		check(w.unlocked[id] == (id in ["pistol", "knife"]), id + " starts with the correct ownership")
		if Weapons.is_melee(id):
			check(not w.state[id].node.find_children("*", "MeshInstance3D", true, false).is_empty(), id + " has weapon geometry")
		else:
			check(ResourceLoader.exists("res://assets/models/%s.glb" % Weapons.DEFS[id].model), id + " has a production mesh")
	for id in Progression.NPCS:
		check(shop.npcs[id].anim != null and shop.npcs[id].anim.is_playing(), id + " has a rigged animated NPC")
	var locked_pickups_safe := true
	for item in game.loots:
		if item is Loot and item.kind == "weapon" and not w.unlocked.get(item.id, false) and not shop.lock_reason(p, item.id).is_empty():
			locked_pickups_safe = locked_pickups_safe and not item.grant_supplies(w, game.hud) and not w.unlocked.get(item.id, false)
	check(locked_pickups_safe, "World loot cannot bypass merchant unlocks")
	var before := p.score
	shop.transact(p, "camp", "weapon", "revolver")
	check(p.score == before and not w.unlocked.revolver, "Remote merchant purchase rejected atomically")
	await visit("camp")
	check(shop.close_enough(p, "camp"), "Camp merchant reachable in actual world")
	var missing := Lang.text(shop.transact(p, "camp", "quest", "marksman_training"))
	check(missing.contains("A Steady Hand") and missing.contains("By the Fire") and missing.contains("Vendor"), "Blocked quest names its prerequisite, NPC and earliest actionable step")
	check(not shop.local_data().accepted.get("marksman_training", false), "Blocked quest cannot be accepted")
	var covered := {}
	for chain in Progression.QUEST_CHAINS:
		for quest in Progression.QUEST_CHAINS[chain].quests:
			check(Progression.QUESTS.has(quest) and not covered.has(quest), "Quest belongs to exactly one valid chain: " + quest)
			covered[quest] = true
	check(covered.size() == Progression.QUESTS.size(), "All quests have a named chain")
	shop.interact("camp")
	check(shop.is_open and paused and not p.active, "NPC interaction opens shop and pauses solo")
	for page in ["Trade", "Quests", "Training", "Towers", "Skins"]:
		shop.page = page
		shop._render()
		check(shop.rows.get_child_count() > 0, "Shop page renders: " + page)
		if page == "Quests":
			var clear_requirement := false
			for widgets in shop._row_nodes:
				if Lang.text(widgets[0].text).contains("Precision Under Pressure"):
					clear_requirement = Lang.text(widgets[0].text).contains("Marksman") and Lang.text(widgets[4].text).contains("A Steady Hand") and Lang.text(widgets[4].text).contains("Vendor") and Lang.text(widgets[1].text).contains("purchase permit")
			check(clear_requirement, "Quest UI shows chain, named prerequisite, giver and weapon permission")
			if "--render-quests" in OS.get_cmdline_user_args():
				await process_frame
				for widgets in shop._row_nodes:
					if Lang.text(widgets[0].text).contains("Precision Under Pressure"):
						(shop.rows.get_parent() as ScrollContainer).scroll_vertical = int(widgets[0].get_parent().get_parent().position.y)
				await process_frame
				await RenderingServer.frame_post_draw
				check(shop.balance.get_line_count() == 1 and shop.balance.size.x > 300, "Currency icon leaves enough width for the merchant balance")
				var folder := ProjectSettings.globalize_path("res://../artifacts/quest-chains/")
				DirAccess.make_dir_recursive_absolute(folder)
				root.get_texture().get_image().save_png(folder + "marksman-requirements.png")
		for widgets in shop._row_nodes:
			check(widgets[3] is TextureRect and widgets[3].texture != null and widgets[3].mouse_filter == Control.MOUSE_FILTER_IGNORE, "Shop icon loads without intercepting clicks: " + Lang.text(widgets[0].text))
	# A sale used to be a small grey line nobody noticed: it has to flash the earned points in gold
	# and show the new total straight away, not a quarter second later.
	shop.page = "Sell"
	shop._render()
	game.weapons.grenades = 2
	var purse: int = p.score
	shop.request("sell_grenade")
	check(p.score == purse + 15, "Selling a grenade pays its price")
	check(shop._gain_popup.visible and shop._gain_popup.text == "+15 R" and shop._gain_popup.get_theme_color("font_color") == shop.GAIN_GOLD,
		"The earned points pop up in gold")
	check(shop._balance_pulse > 0.9 and Lang.text(shop.balance.text).begins_with("%d REM DOLLARS" % p.score),
		"The balance flashes and already shows the new total")
	# Leave the purse and the pouch exactly as they were; the checks below count on them.
	p.score = purse
	game.weapons.grenades = 2
	shop._balance_pulse = 0.0
	shop._gain_t = 0.0
	shop._gain_popup.visible = false
	shop.page = "Trade"
	shop._render()
	var first_button: Button = shop._row_nodes[0][2]
	shop.team.kills += 1
	shop._render()
	check(is_instance_valid(first_button) and first_button == shop._row_nodes[0][2], "Live shop refresh preserves the button under the pointer")
	shop.close()
	check(not paused and p.active, "Leaving merchant restores controls")
	shop.transact(p, "camp", "weapon", "revolver")
	check(not w.unlocked.revolver and p.score == before, "Points alone cannot bypass quest and wave gates")
	check(not shop.has_ready_quest("camp"), "Unaccepted quest has no turn-in marker")
	shop._seen_npcs["camp"] = true
	check(shop.has_available_quest("camp") and game.hud.minimap._quest_symbol("camp") == "!", "Available unaccepted quest shows exclamation mark on minimap")
	check(not shop.has_available_quest("mechanic") and not shop.has_available_quest("secret"), "Locked quests and undiscovered secret trader do not advertise available quests")
	shop.transact(p, "camp", "quest", "arrival")
	check(not shop.has_claim(p.peer_id, "arrival"), "Accepting a quest does not claim its reward")
	check(game.hud.minimap._quest_symbol("camp") == "?", "Ready quest replaces acceptance marker with question mark")
	check(Sfx._voices.has("quest_accept"), "Accepted quest plays its dedicated sound")
	await process_frame
	await process_frame
	check(shop.has_ready_quest("camp") and shop.npcs.camp.quest_marker.visible, "Completed accepted quest marks its giver in world and minimap state")
	check(not shop.has_ready_quest("mechanic") and not shop.has_ready_quest("secret"), "Other givers and undiscovered secret shop remain unmarked")
	shop.transact(p, "camp", "quest", "arrival")
	check(shop.has_claim(p.peer_id, "arrival") and p.score == before + 20, "Completed quest pays exactly once")
	check(Sfx._voices.has("quest_complete"), "Quest reward plays completion sound")
	await process_frame
	await process_frame
	check(not shop.has_ready_quest("camp") and not shop.npcs.camp.quest_marker.visible, "Claimed reward removes the turn-in marker")
	var completion_voices: Array = Sfx._voices["quest_complete"].duplicate()
	var rewarded_score := p.score
	shop.transact(p, "camp", "quest", "arrival")
	check(p.score == rewarded_score, "Repeated quest claim cannot duplicate points")
	check(Sfx._voices["quest_complete"] == completion_voices, "Rejected duplicate reward stays silent")
	shop.transact(p, "camp", "weapon", "revolver")
	check(not w.unlocked.revolver, "Quest completion still requires surviving wave one")
	var level_result := Lang.text(shop.transact(p, "camp", "quest", "steady_aim"))
	check(level_result.contains("Mission level 2") and not shop.local_data().accepted.get("steady_aim", false), "Quest transaction rejects acceptance below level gate")
	game.waves.completed = 1
	p.score = 219
	shop.transact(p, "camp", "weapon", "revolver")
	check(not w.unlocked.revolver and p.score == 219, "Insufficient funds preserve ownership and balance")
	p.score = 220
	shop.transact(p, "camp", "weapon", "revolver")
	check(w.unlocked.revolver and p.score == 0 and w.state.revolver.reserve == 12, "Eligible weapon purchase charges once with bounded starting ammunition")
	check(Sfx._voices.has("weapon_pickup"), "Purchased weapon plays gun pickup sound")
	shop._render()
	var ammo_rows := 0
	var revolver_ammo := false
	for widgets in shop._row_nodes:
		if Lang.text(widgets[0].text).begins_with("Ammo"):
			ammo_rows += 1
			if Lang.text(widgets[0].text).contains("Revolver"): revolver_ammo = true
	check(ammo_rows == 2 and revolver_ammo, "Shop adds ammunition for every owned weapon after purchase")
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
	game.waves.completed += 1
	check(shop.complete("watch"), "Defence quest completes with a built line and rotated tower")
	before = p.score
	game.defences.maintain(p, tower.tower_id, "upgrade")
	check(tower.level == 1 and p.score == before, "Turret upgrades require the mechanic")
	await visit("mechanic")
	shop.transact(p, "mechanic", "tower_upgrade", str(tower.tower_id))
	check(tower.level == 2 and p.score == before - 100, "Mechanic upgrades deployed tower transactionally")
	# The builder's Towers page offers dismantling; the row had gone missing while the guides described it.
	shop.interact("mechanic")
	shop.page = "Towers"
	shop._render()
	var dismantle: Button = null
	for widgets in shop._row_nodes:
		if widgets[2].text == "Dismantle": dismantle = widgets[2]
	check(dismantle != null and not dismantle.disabled, "Mechanic offers dismantling of the builder's own tower")
	shop.close()
	shop.transact(p, "mechanic", "quest", "watch")
	game.waves.completed = 3
	shop.transact(p, "mechanic", "quest", "supplies")
	await visit("cache")
	check(shop.close_enough(p, "cache"), "Supply objective reachable")
	shop.transact(p, "cache", "cache", "")
	check(shop.team.cache, "World interaction collects shared delivery")
	game.waves.completed += 1
	await visit("mechanic")
	shop.transact(p, "mechanic", "quest", "supplies")
	check(shop.has_claim(p.peer_id, "supplies"), "Delivery must be returned to claim its reward")
	# Precision rifles require the complete Marksman chain, not a delivery alone.
	check(Lang.text(shop.lock_reason(p, "marksman")).contains("Marksman") and Lang.text(shop.lock_reason(p, "marksman")).contains("A Steady Hand"), "Sniper shop names the missing Marksman chain and next quest")
	await visit("camp")
	before = p.score
	shop.transact(p, "camp", "weapon", "marksman")
	check(p.score == before and not w.unlocked.marksman, "Delivery and points cannot bypass the sniper permission")
	game.waves.completed = maxi(game.waves.completed, 3)
	shop.team.headshot_kills = 40
	for quest in ["steady_aim", "marksman_training"]:
		game.waves.completed = maxi(game.waves.completed, int(Progression.QUESTS[quest].min_level) - 1)
		shop.transact(p, "camp", "quest", quest)
		var quest_balance := p.score
		shop.transact(p, "camp", "quest", quest)
		check(p.score == quest_balance and not shop.has_claim(p.peer_id, quest), quest + " cannot be claimed by clicking again with old counters")
		game.waves.completed += 1
		shop.transact(p, "camp", "quest", quest)
	check(not shop.chain_complete(p.peer_id, "marksman") and Lang.text(shop.lock_reason(p, "marksman")).contains("Secret Vendor"), "Intermediate quests direct the player to the final giver")
	await visit("secret")
	game.waves.completed = 7
	shop.transact(p, "secret", "quest", "silent_deal")
	game.waves.completed += 1
	check(Lang.text(shop.next_quest_step(p.peer_id, "silent_deal")).contains("collect reward") and not shop.chain_complete(p.peer_id, "marksman"), "Completed objective requires turn-in before granting permission")
	var chain_reward := shop.transact(p, "secret", "quest", "silent_deal")
	check(shop.chain_complete(p.peer_id, "marksman") and Lang.text(chain_reward).contains("Purchase permit"), "Final turn-in announces the earned Marksman permission")
	check(not shop.chain_complete(2, "marksman"), "Shared team goals do not grant another player's unclaimed permission")
	var quest_snapshot := shop.snapshot()
	shop.apply_snapshot(quest_snapshot)
	check(shop.chain_complete(p.peer_id, "marksman") and not shop.chain_complete(2, "marksman"), "Snapshots preserve individual chain permissions")
	check(shop.lock_reason(p, "marksman").is_empty(), "Marksman chain permits the precision rifle")
	check(Lang.text(shop.lock_reason(p, "titanbreaker")).contains("What Lurks in the Field"), "Heavy sniper still requires its separate titan quest")
	await visit("camp")
	before = p.score
	shop.transact(p, "camp", "weapon", "marksman")
	check(w.unlocked.marksman and p.score == before - int(Progression.GOODS.marksman.price), "Earned sniper permission still requires paying the weapon price")
	await visit("secret")
	shop.transact(p, "secret", "visit", "")
	check(shop.local_data().discovered, "Secret merchant discovered by reaching the actual NPC")
	game.waves.completed = 9
	shop.transact(p, "secret", "weapon", "titanbreaker")
	check(not w.unlocked.titanbreaker, "Top weapon additionally requires a defeated titan")
	shop.transact(p, "secret", "quest", "titan")
	shop.event("titans")
	game.waves.completed += 1
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
	check(is_equal_approx(p.camera.fov, w.aimed_fov()) and w.viewmodel.scope.visible, "Heavy optic uses its configured scope magnification")
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
	await visit("ranger")
	check(shop.close_enough(p, "ranger"), "Mara can be reached beside the small campfire")
	var reserve_before: int = w.state.pistol.reserve
	shop.transact(p, "ranger", "ammo", "pistol")
	check(w.state.pistol.reserve == reserve_before, "Quest-only ranger cannot be used as a hidden shop")
	shop.interact("ranger")
	check(shop.is_open and shop.page == "Quests" and not shop._tabs.Trade.visible, "Mara opens her own quest-only conversation")
	shop.close()
	shop.transact(p, "ranger", "quest", "forest_basket")
	var saved_clock: float = game.day_night.clock_seconds
	for greeting_case in [[5.0, "morning"], [9.0, "hello"], [17.0, "evening"], [20.0, "evening"], [21.0, "night"], [0.0, "night"]]:
		game.day_night.set_time_hours(greeting_case[0])
		shop.interact("ranger")
		var stem: String = "mara_sfx_hello" if greeting_case[1] == "hello" else "mara_sfx_good_" + greeting_case[1]
		check(shop.is_open and shop._greeting.playing and shop._greeting.stream == Sfx._file(stem) and shop._greeting.can_process(), "Mara opens with the correct audible greeting at %02d:00" % int(greeting_case[0]))
		shop.close()
	game.day_night.set_time_hours(saved_clock / 3600.0)
	var gathered := int(shop.team.get("edible_mushrooms", 0))
	for i in 5:
		var mushroom := Loot.new()
		mushroom.setup("mushroom", "steinpilz", "Steinpilz")
		game.add_child(mushroom)
		mushroom.take(w, game.hud)
	game.waves.completed += 1
	check(shop.team.edible_mushrooms == gathered + 5 and shop.has_ready_quest("ranger"), "Mushroom pickups and surviving a wave complete Mara's first quest")
	before = p.score
	shop.transact(p, "ranger", "quest", "forest_basket")
	shop.transact(p, "ranger", "quest", "forest_basket")
	check(p.score == before + 90 and shop.has_claim(p.peer_id, "forest_basket"), "Mara pays her reward exactly once")
	print("PROGRESSION_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
