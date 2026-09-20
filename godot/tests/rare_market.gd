extends SceneTree

var checks := 0
var failures := 0
var started := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")
func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - started > 120000: quit(1)
	return false
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
	var shop: Progression = game.progression
	var market = shop.rare_market
	market.set_physics_process(false)
	market.random.seed = 7041
	p.set_physics_process(false)
	p.score = 30000
	game.waves.wave = 4
	market._physics_process(0.1)
	check(not market.active and not shop.npcs.wanderer.visible and shop.npcs.wanderer.body.collision_layer == 0, "Merchant hidden and nonblocking before wave five")
	p.global_position = shop.npcs.wanderer.global_position
	check(not shop.close_enough(p, "wanderer"), "Hidden merchant cannot be traded with")
	p.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	game.waves.wave = 5
	game.waves.completed = 4
	for i in 8: market._physics_process(0.1)
	var relics := 0
	for id in market.stock:
		if market.Items.DEFS[id].kind == "relic": relics += 1
	check(market.active and relics >= 3 and market.stock.has("fire"), "Wave five spawns merchant with three legendaries and fire ammo (%d relics)" % relics)
	game.day_night.clock_seconds = 2 * 3600
	market.stock_key = ""
	market.here_region = "N"
	market.restock(5)
	var night_ok := true
	for id in market.stock:
		var spec: Dictionary = market.Items.DEFS[id]
		if spec.has("time") and "night" not in spec.time: night_ok = false
		if spec.has("region") and "N" not in spec.region: night_ok = false
	check(night_ok and market.stock.size() >= 4, "Night stock in the north forest only carries goods offered there at night")
	game.day_night.clock_seconds = 12 * 3600
	market.here_region = "S"
	market.restock(5)
	var day_ok := true
	for id in market.stock:
		var spec: Dictionary = market.Items.DEFS[id]
		if spec.has("time") and "day" not in spec.time: day_ok = false
		if spec.has("region") and "S" not in spec.region: day_ok = false
	check(day_ok and market.stock_key.ends_with("day|S"), "Daylight and a new forest quarter reroll the assortment")
	market.stock["hawk"] = 1
	var origin: Vector3 = market.npc.global_position
	for i in 200:
		market._physics_process(0.1)
		if i % 10 == 0: await physics_frame
	check(origin.distance_to(market.npc.global_position) > 4, "Merchant actually walks through the forest along navigation paths")
	var sampled_cells := {}
	var open_land := 0
	var samples := 0
	var saved_roam_position: Vector3 = market.npc.global_position
	market.visited_cells.clear()
	market.mark_visited()
	for i in 40:
		var goal: Vector3 = market.choose_destination()
		if goal == Vector3.INF: continue
		samples += 1
		sampled_cells[market.roam_cell(goal)] = true
		if not Map.in_forest(goal.x, goal.z): open_land += 1
		market.npc.global_position = goal
		market.mark_visited()
	check(samples >= 30 and sampled_cells.size() == 9, "Merchant tour reaches all nine map sectors (%d sectors, %d goals)" % [sampled_cells.size(), samples])
	check(open_land > 0, "Merchant also visits open terrain outside the forest (%d goals)" % open_land)
	market.npc.global_position = saved_roam_position
	market.path.clear()
	market.trail.clear()
	check(Progression.VOCALS.get("wanderer", "") == "secret_vendor_vocal" and Sfx.get_stream("secret_vendor_vocal") != null, "Merchant greets with the secret vendor voice line")
	check(market.npc.anim.has_animation("walk") and market.npc.anim.get_animation("walk").get_track_count() > 10, "Merchant has a retargeted skeletal walk animation")
	p.global_position = market.npc.global_position + Vector3(0, 0, 2)
	await physics_frame
	await physics_frame
	origin = market.npc.global_position
	market._physics_process(0.5)
	check(origin == market.npc.global_position, "Nearby customer stops merchant for trading")
	check(shop.close_enough(p, "wanderer"), "Moving merchant is reachable through the real interaction check")
	var start_balance := p.score
	shop.transact(p, "wanderer", "rare", "hawk")
	check(p.relic == "hawk" and p.score == start_balance - 1800 and market.stock.hawk == 0, "Legendary purchase charges once, consumes shared stock and equips")
	check(is_equal_approx(p.relic_multiplier("spread"), 0.65), "Precision talisman supplies its actual combat modifier")
	shop.transact(p, "wanderer", "rare", "hawk")
	check(p.score == start_balance - 1800, "Owned talisman equips without another payment")
	shop.transact(p, "wanderer", "rare", "fire")
	check(market.data(p.peer_id).ammo.fire == 24 and market.data(p.peer_id).mode == "fire", "Fire pack enables twenty-four special shots")
	market.restock(5)
	check(market.stock.fire == 2 and market.stock.hawk == 0, "Same wave never replenishes depleted stock")
	market.stock.frost = 1
	var balance := p.score
	shop.transact(p, "wanderer", "rare", "frost")
	check(p.score == balance, "Higher level rare ammunition remains gated")
	p.global_position += Vector3(20, 0, 0)
	shop.transact(p, "wanderer", "rare", "fire")
	check(p.score == balance, "Remote purchase cannot debit or grant rare items")
	p.global_position = market.npc.global_position + Vector3(0, 0, 2)
	market.data(p.peer_id).ammo.fire = 96
	shop.transact(p, "wanderer", "rare", "fire")
	check(p.score == balance and market.stock.fire == 2, "Full special-ammo inventory preserves money and stock")
	market.data(p.peer_id).ammo.fire = 24
	market.equip(p, "normal")
	check(market.consume_round(p).is_empty() and market.data(p.peer_id).ammo.fire == 24, "Normal mode saves special ammunition")
	market.equip(p, "fire")
	w.set_weapon("pistol")
	p.camera.rotation.x = PI * 0.4
	w.try_fire()
	check(w.effects.ammo_mode == "fire" and w.effects.flash_duration > 0.08, "Fire ammunition creates a longer flame muzzle flash")
	check(not get_nodes_in_group("elemental_tracer").is_empty(), "Missed special shots still draw a visible trail")
	check(market.data(p.peer_id).ammo.fire == 23, "Real missed firearm shot consumes one special round")
	var z := Zombie.new()
	z.setup("shambler", p, game.barricades, 1, Callable())
	game.zombies_root.add_child(z)
	z.global_position = p.global_position + Vector3(5, 0, 0)
	z.set_physics_process(false)
	var customer_position := p.global_position
	p.global_position = Map.ground_pos(20, 105)
	z.global_position = Map.ground_pos(20, 111)
	z.hp = 200
	await physics_frame
	await physics_frame
	p.camera.look_at(z.global_position + Vector3.UP)
	w.cur().cooldown = 0
	w.cur().ammo = 12
	var rounds_before: int = market.data(p.peer_id).ammo.fire
	w.try_fire()
	check(z.hp < 200 and z.rare_status == "fire" and market.data(p.peer_id).ammo.fire == rounds_before - 1, "Real bullet hit applies burn and consumes exactly one charge")
	z.update_rare_visual()
	check(z._rare_particles.emitting, "Burn shows particles on the actual zombie")
	market.hit(z, "frost", p.peer_id, "pistol")
	z.update_rare_visual()
	check(z._rare_particles.emitting and z._frost_particles.emitting and z.rare_status == "fire+frost", "Concurrent burn and frost retain both visible effects")
	check(z._frost_visible and not z._frost_meshes.is_empty() and z._frost_meshes[0].material_overlay == z._frost_surface, "Frost coats the actual enemy model in ice")
	check(z._rare_particles.mesh is QuadMesh and z._frost_particles.mesh.material.get_shader_parameter("frost") == true, "Flames and ice crystals use distinct particle visuals")
	market.tick_statuses(3)
	p.global_position = customer_position
	z.hp = 200
	for i in 9: market.hit(z, "fire", p.peer_id, "shotgun")
	market.tick_statuses(3)
	check(z.hp == 164, "Repeated pellets refresh burn without multiplying its thirty-six damage")
	market.hit(z, "frost", p.peer_id, "pistol")
	check(z.frost_mul == 0.55 and z.rare_status == "frost", "Frost slows a normal zombie")
	market.tick_statuses(3.1)
	check(z.frost_mul == 1 and z.rare_status.is_empty(), "Frost expires and restores movement")
	z.update_rare_visual()
	check(not z._rare_particles.emitting and not z._frost_particles.emitting and not z._rare_light.visible and not z._frost_visible, "Expired statuses stop both emitters and their lighting")
	w.effects.fire("pistol", w.muzzle_transform(), Vector3.ZERO, 1.0, "frost")
	check(w.effects.world_light.light_color.b > w.effects.world_light.light_color.r, "Frost muzzle flash casts cold blue light")
	w.effects.fire("pistol", w.muzzle_transform(), Vector3.ZERO)
	check(w.effects.ammo_mode.is_empty() and w.effects.world_light.light_color.r > w.effects.world_light.light_color.b, "Normal ammunition restores the ordinary muzzle flash")
	z.net_kind = "titan"
	market.hit(z, "frost", p.peer_id, "pistol")
	check(z.frost_mul == 0.8, "Titans resist most of the frost slowdown")
	z.net_kind = "shambler"
	z.hp = 10
	market.hit(z, "fire", 77, "marksman")
	market.tick_statuses(1)
	check(not z.alive and z.killer_peer == 77 and z.killer_weapon == "marksman" and not z.last_headshot, "Burn kill preserves the shooter and never grants a phantom headshot")
	market.data(p.peer_id).owned = {"hawk": true, "blood": true, "bark": true, "wind": true, "phoenix": true}
	market.equip(p, "bark")
	p.hp = 100
	p.damage(50)
	check(p.hp == 60 and p.relic_multiplier("spread") == 1, "Only active talisman applies; bark reduces actual incoming damage")
	market.equip(p, "blood")
	market.on_kill(p, "tower")
	check(p.hp == 60, "Tower kills cannot farm lifesteal")
	market.on_kill(p, "pistol")
	check(p.hp == 63, "Bloodstone heals real weapon kills")
	market.equip(p, "wind")
	check(is_equal_approx(w.effective_reload_mul(), 0.8) and is_equal_approx(p.effective_speed_mul(), 1.1), "Wind relic affects reload and movement")
	market.equip(p, "phoenix")
	p.damage(1000)
	check(p.alive and p.hp == p.max_hp * 0.4, "Phoenix prevents one lethal hit")
	# Every legendary the merchant can carry is purchasable, equips itself and changes the real mechanic it names.
	game.waves.completed = 20
	market.stock_key = ""
	market.data(p.peer_id).owned = {}
	market.data(p.peer_id).active = ""
	p.relic = ""
	var relic_ids: Array = []
	for id in market.Items.DEFS:
		if market.Items.DEFS[id].kind == "relic": relic_ids.append(id)
		market.stock[id] = 1
	var bought := 0
	for id in relic_ids:
		p.score = 10000
		var reply: String = market.buy(p, id)
		if reply.begins_with("Gekauft") and p.relic == id and market.stock[id] == 0 and p.score == 10000 - int(market.Items.DEFS[id].price): bought += 1
	check(bought == relic_ids.size() and relic_ids.size() == 14, "All %d legendaries can be bought, charge their price and equip (%d ok)" % [relic_ids.size(), bought])
	market.equip(p, "none")
	var plain_damage := w.effective_damage_mul()
	var plain_speed := p.effective_speed_mul()
	var plain_reload := w.effective_reload_mul()
	market.equip(p, "ember")
	check(is_equal_approx(w.effective_damage_mul(), plain_damage * 1.15), "Glutkern raises the damage multiplier used by real bullet hits")
	market.equip(p, "stag")
	check(is_equal_approx(p.effective_speed_mul(), plain_speed * 1.18), "Hirschkrone raises the movement speed multiplier")
	market.equip(p, "raven")
	w.set_weapon("pistol")
	w.cur().ammo = 0
	w.cur().reserve = 50
	w.cur().reloading = 0.0
	w.reload()
	check(is_equal_approx(w.effective_reload_mul(), plain_reload * 0.7) and is_equal_approx(w.cur().reloading, float(w.cur().def.reload) * plain_reload * 0.7), "Rabenfeder shortens the actual reload timer")
	w.cur().reloading = 0.0
	w.cur().ammo = 12
	market.equip(p, "root")
	p.hp = 100
	p.damage(40)
	check(p.hp == 70, "Wurzelband cuts real incoming damage by a quarter")
	market.equip(p, "moss")
	p.hp = 100
	p.damage(40)
	check(p.hp == 66 and is_equal_approx(p.effective_speed_mul(), plain_speed * 1.05), "Moosmantel reduces damage and adds tempo")
	market.equip(p, "lantern")
	p.hp = 100
	p.damage(40)
	check(p.hp == 66 and is_equal_approx(w.effective_damage_mul(), plain_damage * 1.08), "Nebellaterne guards and adds damage")
	market.equip(p, "owl")
	check(is_equal_approx(p.relic_multiplier("spread"), 0.7) and is_equal_approx(p.relic_multiplier("recoil"), 0.85), "Eulenauge tightens spread and recoil")
	# recoil: fire once without and once with Stahlherz, compare the pitch kick (random 0.85..1.15 per shot)
	market.equip(p, "none")
	p.camera.rotation.x = PI * 0.4
	w.cur().cooldown = 0
	w.kick_pitch = 0.0
	w._shots_in_burst = 0
	w.try_fire()
	var plain_kick: float = w.kick_pitch
	market.equip(p, "steel")
	w.cur().cooldown = 0
	w.kick_pitch = 0.0
	w._shots_in_burst = 0
	w.try_fire()
	check(plain_kick > 0 and w.kick_pitch < plain_kick * 0.8, "Stahlherz cuts the real recoil kick (%.3f -> %.3f)" % [plain_kick, w.kick_pitch])
	# score: a real kill through the game's scoring path with and without Wegzoll
	market.equip(p, "none")
	var victim := Zombie.new()
	victim.setup("shambler", p, game.barricades, 1, Callable())
	game.zombies_root.add_child(victim)
	victim.killer_peer = p.peer_id
	victim.last_headshot = false
	# stats.points_earned records exactly the kill bounty; p.score would also pick up quest rewards fired by the kill event
	game.stats._streak = 0
	var earned_before: int = game.stats.points_earned
	game._zombie_killed(victim)
	var plain_points: int = game.stats.points_earned - earned_before
	market.equip(p, "coin")
	game.stats._streak = 0
	earned_before = game.stats.points_earned
	p.score = 0
	game._zombie_killed(victim)
	var coin_points: int = game.stats.points_earned - earned_before
	check(plain_points > 0 and coin_points == maxi(1, roundi(plain_points * 1.2)) and p.score >= coin_points, "Wegzoll pays 20 %% more for a real kill (%d -> %d)" % [plain_points, coin_points])
	victim.queue_free()
	market.equip(p, "none")
	market.data(p.peer_id).owned = {"hawk": true, "blood": true, "bark": true, "wind": true, "phoenix": true}
	market.equip(p, "phoenix")
	market.equip(p, "hawk")
	market.equip(p, "phoenix")
	check(not market.prevent_death(p), "Changing talismans cannot reset Phoenix cooldown")
	game.waves.wave = 6
	check(market.prevent_death(p), "Next wave restores Phoenix charge")
	market.restock(6)
	check(market.stock.fire == 3, "Next wave replenishes market")
	shop.interact("wanderer")
	check(not market.can_process(), "Solo shop pause also freezes trader and damage-over-time")
	check(shop.page == "Raritäten" and shop._tabs.Raritäten.visible and not shop._tabs.Handel.visible, "Wanderer opens his dedicated rare-item menu")
	shop.close()
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var peer: Player = NetSession.world.actor(2)
	peer.set_physics_process(false)
	var avatar = NetSession.world.avatars[2]
	avatar.shot("pistol", [-8.0, 1.0, 2.0, "frost"])
	check(avatar.flash.light_color.b > avatar.flash.light_color.r, "Remote shot payload renders frost lighting")
	peer.score = 1000
	peer.global_position = market.npc.global_position + Vector3(0, 0, 2)
	market.stock.fire = 1
	shop.transact(peer, "wanderer", "rare", "fire")
	check(peer.score == 520 and market.data(2).ammo.fire == 24 and market.stock.fire == 0, "Remote purchase consumes shared stock but grants only buyer's ammunition")
	balance = p.score
	shop.transact(p, "wanderer", "rare", "fire")
	check(p.score == balance, "Second buyer cannot purchase the sold-out pack")
	var snap: Dictionary = shop.snapshot()
	check(snap.rare_market.people[2].ammo.fire == 24 and snap.rare_market.pos == market.npc.global_position, "Snapshot includes roaming position, stock and separate inventories")
	NetSession.enabled = false
	market.apply_snapshot(snap.rare_market)
	check(market.stock.fire == 0 and market.data(2).ammo.fire == 24, "Late-join state restores sold-out stock and ammunition")
	# The navmesh leaves gates traversable for enemies; the merchant must check
	# the real swept capsule before accepting a route through that opening.
	var gate: Barricade = game.barricades[0]
	var normal := Vector3(gate.normal2.x, 0, gate.normal2.y)
	var outside := gate.center + normal * 3.0
	var inside := gate.center - normal * 3.0
	var route := PackedVector3Array([outside, inside])
	check(market.route_clear(route), "Unbuilt gate permits merchant routes")
	gate.build()
	await physics_frame
	await physics_frame
	check(not market.route_clear(route), "Built gate is rejected even when the navmesh offers that path")
	check(not market.movement_clear(outside, inside), "Swept movement cannot tunnel through a gate")
	var saved_position: Vector3 = market.npc.global_position
	market.npc.global_position = gate.center + normal * 1.2
	market.trail = PackedVector3Array([outside])
	market.path = PackedVector3Array([inside])
	market.path_index = 0
	p.global_position = outside + normal * 20.0
	market._physics_process(0.5)
	check(market.path.size() == 1 and market.path[0].is_equal_approx(outside), "Newly blocked merchant route backs out along the travelled path")
	var before_retreat: Vector3 = market.npc.global_position
	market._physics_process(0.5)
	check(market.npc.global_position.distance_to(outside) < before_retreat.distance_to(outside), "Merchant actually walks away from the blocked gate")
	market.npc.global_position = saved_position
	market.trail.clear()
	market.path.clear()
	for other_gate: Barricade in game.barricades:
		if other_gate.level == 0: other_gate.build()
	await physics_frame
	await physics_frame
	market.active = false
	check(market.choose_destination() != Vector3.INF, "Merchant can spawn in the forest even when every camp gate is built")
	market.active = true
	if "--render-rare" in OS.get_cmdline_user_args():
		peer.global_position += Vector3(15, 0, 0)
		p.hp = p.max_hp
		game.hud.set_health(p.hp)
		game.achievements.set_process(false)
		game.achievements._toast.hide()
		market.stock = {"hawk": 1, "fire": 3, "frost": 2, "phoenix": 1}
		p.global_position = market.npc.global_position + Vector3(0, 0, 2)
		p.camera.rotation = Vector3.ZERO
		p.camera.look_at(market.npc.global_position + Vector3.UP * 1.1)
		shop.interact("wanderer")
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/rare-market"))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/rare-market/shop.png"))
		shop.close()
		p.global_position = market.npc.global_position + Vector3(0, 0, 4)
		p.camera.look_at(market.npc.global_position + Vector3.UP)
		game.hud.message("", 0)
		await create_timer(0.5).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/rare-market/merchant.png"))
	print("RARE_MARKET_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
