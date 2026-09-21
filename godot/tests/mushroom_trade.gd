extends SceneTree

const Mushrooms = preload("res://scripts/mushrooms.gd")
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func shot(id: String) -> void:
	if "--render-mushrooms" not in OS.get_cmdline_user_args(): return
	var folder := ProjectSettings.globalize_path("res://../artifacts/mushrooms/")
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + id + ".png")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	var inv: Inventory = game.inventory
	var vendor: Progression = game.progression
	p.set_physics_process(false)
	w.set_process(false)
	for kind in Mushrooms.DEFS: inv.mushrooms[kind] = 5
	p.hp = 30.0
	inv._eat("steinpilz")
	check(p.hp == 55.0 and game.hud.hp_bar.value == 55.0 and inv.mushrooms.steinpilz == 4, "Eating heals and immediately updates health HUD")
	p.hp = p.max_hp
	game.hud.msg_label.text = ""
	inv._eat("steinpilz")
	check(inv.mushrooms.steinpilz == 4, "Pure healing mushroom is retained at full health")
	# The quick bar eats with the inventory closed, so the refusal has to reach the HUD.
	check(game.hud.msg_label.text.contains("voll"), "A refused mushroom says why on the HUD, not only in the hidden inventory panel")
	w.damage_mul = 1.24
	inv._eat("fliegenpilz")
	check(p.hp == 85.0 and is_equal_approx(w.effective_damage_mul(), 2.48), "Fly agaric doubles upgraded weapon damage and costs 15 HP")
	p.score = 10000
	p.global_position = vendor.npcs.mechanic.global_position + Vector3(0, 0, 1)
	game.skills.purchase(p, w, "damage")
	check(is_equal_approx(w.damage_mul, 1.36) and is_equal_approx(w.effective_damage_mul(), 2.72), "Damage training during a buff remains permanent")
	inv._eat("violetter_roetelritterling")
	check(is_equal_approx(w.effective_damage_mul(), 2.72), "Overlapping damage mushrooms use strongest bonus")
	Mushrooms.tick(p.mushroom_effects, 10.0)
	inv._eat("fliegenpilz")
	check(p.mushroom_effects.fliegenpilz == 20.0, "Eating again refreshes duration without stacking strength")
	Mushrooms.tick(p.mushroom_effects, 20.0)
	check(is_equal_approx(w.effective_damage_mul(), 1.36 * 1.35), "Weaker damage bonus remains when stronger one expires")
	Mushrooms.tick(p.mushroom_effects, 30.0)
	check(is_equal_approx(w.effective_damage_mul(), 1.36), "Expired mushrooms preserve all purchased damage upgrades")
	p.speed_mul = 1.15
	inv._eat("pfifferling")
	check(is_equal_approx(p.effective_speed_mul(), 1.38), "Movement bonus combines with speed training")
	w.reload_mul = 0.9
	inv._eat("morchel")
	w.cur().ammo = 0
	w.cur().reserve = 24
	w.reload()
	check(is_equal_approx(w.cur().reloading, float(w.cur().def.reload) * 0.9 * 0.75), "Morel reduces actual reload timer")
	inv._eat("parasol")
	p.hp = 100.0
	p.damage(20)
	check(p.hp == 85.0, "Parasol reduces received damage by 25 percent")
	inv._eat("reizker")
	p.hp = 40.0
	p.regen_timer = 0.0
	p.regen_mul = 1.25
	p._regenerate(1.0)
	check(p.hp == 50.0, "Reizker doubles actual regeneration with training")
	inv._eat("tintenpilz")
	check(is_equal_approx(p.mushroom_multiplier("spread"), 0.65), "Ink mushroom reduces weapon spread")
	for kind in ["maronenroehrling", "krause_glucke"]:
		p.hp = 10.0
		inv._eat(kind)
		check(p.hp == 10.0 + Mushrooms.DEFS[kind].heal, kind + " applies its healing amount")
	var stock_before := inv.mushrooms.duplicate()
	check(not Mushrooms.consume(p, inv.mushrooms, "unknown").is_empty() and inv.mushrooms == stock_before, "Unknown mushroom cannot change inventory")
	p.active = true
	inv.open()
	var remaining := p.mushroom_effects.duplicate()
	p.set_physics_process(true)
	for i in 3: await process_frame
	check(p.mushroom_effects == remaining, "Solo inventory pauses effect timers")
	p.set_physics_process(false)
	inv.close()
	p.global_position = vendor.npcs.camp.global_position + Vector3(0, 0, 1)
	for kind in Mushrooms.DEFS:
		var before := p.score
		var count := int(inv.mushrooms[kind])
		var result := vendor.transact(p, "camp", "sell_mushroom", kind)
		check(result.begins_with("Verkauft") and p.score == before + int(Mushrooms.DEFS[kind].sell) and inv.mushrooms[kind] == count - 1, kind + " sells one item at the catalogue price")
	inv.mushrooms.steinpilz = 0
	var balance := p.score
	vendor.transact(p, "camp", "sell_mushroom", "steinpilz")
	vendor.transact(p, "camp", "sell_mushroom", "invalid")
	check(p.score == balance and inv.mushrooms.steinpilz == 0, "Empty or invalid sales never award points")
	w.grenades = 1
	vendor.transact(p, "camp", "sell_grenade", "")
	vendor.transact(p, "camp", "sell_grenade", "")
	check(w.grenades == 0 and p.score == balance + 15, "Grenade can be sold exactly once")
	w.state.pistol.reserve = 13
	balance = p.score
	vendor.transact(p, "camp", "sell_ammo", "pistol")
	vendor.transact(p, "camp", "sell_ammo", "pistol")
	check(w.state.pistol.reserve == 1 and p.score == balance + Progression.ammo_sale_price("pistol"), "Only complete reserve magazines can be sold")
	w.unlock("revolver")
	w.set_weapon("revolver")
	w.cur().reloading = 1.0
	vendor.transact(p, "camp", "sell_weapon", "revolver")
	check(not w.unlocked.revolver and w.current == "pistol" and w.ammo_weapon() == "pistol" and w.state.revolver.reloading == 0.0, "Selling equipped weapon safely switches to pistol and cancels reload")
	balance = p.score
	vendor.transact(p, "camp", "sell_weapon", "revolver")
	vendor.transact(p, "camp", "sell_weapon", "pistol")
	vendor.transact(p, "camp", "sell_weapon", "knife")
	check(p.score == balance and w.unlocked.pistol and w.unlocked.knife, "Repeated sales and starter equipment sales are rejected")
	p.global_position += Vector3(30, 0, 0)
	vendor.transact(p, "camp", "sell_mushroom", "morchel")
	check(p.score == balance, "Remote sale is rejected by proximity check")
	p.global_position = vendor.npcs.mechanic.global_position + Vector3(0, 0, 1)
	vendor.transact(p, "mechanic", "sell_mushroom", "morchel")
	check(p.score == balance, "Non-vendor NPC rejects item sales")
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var peer: Player = NetSession.world.actor(2)
	peer.set_physics_process(false)
	NetSession.world.weapons[2].set_process(false)
	peer.global_position = vendor.npcs.secret.global_position + Vector3(0, 0, 1)
	NetSession.world.mushrooms[2].morchel = 2
	NetSession.world.eat(2, "morchel")
	check(peer.mushroom_effects.has("morchel") and NetSession.world.mushrooms[2].morchel == 1, "Host applies remote player's mushroom consumption")
	peer._physics_process(0.5)
	check(is_equal_approx(peer.mushroom_effects.morchel, 29.5), "Remote player physics advances effect duration on the host")
	stock_before = inv.mushrooms.duplicate()
	balance = peer.score
	vendor.transact(peer, "secret", "sell_mushroom", "morchel")
	check(peer.score == balance + 14 and NetSession.world.mushrooms[2].morchel == 0 and inv.mushrooms == stock_before, "Secret Vendor sells only the requesting peer's stock")
	var snapshot: Dictionary = NetSession.world.snapshot()
	check(snapshot.players[2].effects == peer.mushroom_effects and snapshot.players[2].mushrooms.morchel == 0, "Co-op snapshot contains effects and updated stock")
	peer.damage(1000)
	check(peer.mushroom_effects.is_empty(), "Death clears temporary mushroom effects")
	inv.mushrooms = inv.mushrooms.duplicate()
	inv.mushrooms.morchel = 7
	check(vendor.mushroom_stock(p).morchel == 7, "Sales UI reads inventory replaced by a client snapshot")
	NetSession.enabled = false
	w._last_firearm = "revolver"
	w.set_weapon("knife")
	check(w.ammo_weapon() == "pistol", "Sold last firearm falls back to pistol while holding melee")
	p.global_position = Vector3(0, 60, 0)
	p.rotation = Vector3.ZERO
	p.head.rotation = Vector3.ZERO
	p.pitch = 0.0
	var target := Zombie.new()
	target.setup("brute", p, [], 1.0, Callable())
	target.model_path = ""
	game.zombies_root.add_child(target)
	target.set_physics_process(false)
	target.agent.avoidance_enabled = false
	target.global_position = p.global_position + Vector3(0, 0, -1.5)
	target.hp = 5000.0
	await physics_frame
	await physics_frame
	for weapon in ["knife", "pistol"]:
		w.set_weapon(weapon)
		w.spread_mul = 0.0
		var damage := []
		for bonus in [false, true]:
			p.mushroom_effects.clear()
			if bonus: p.mushroom_effects.fliegenpilz = 20.0
			w._melee_t = 0.0
			w.cur().cooldown = 0.0
			w.cur().reloading = 0.0
			w.cur().ammo = int(w.cur().def.mag)
			var before := target.hp
			w.try_fire()
			damage.append(before - target.hp)
		check(damage[0] > 0.0 and is_equal_approx(damage[1], damage[0] * 2.0), weapon + " actual hit damage doubles while mushroom effect is active")
	target.queue_free()
	for kind in Mushrooms.DEFS:
		inv.mushrooms[kind] = 3
		if Mushrooms.DEFS[kind].has("duration"): p.mushroom_effects[kind] = Mushrooms.DEFS[kind].duration
	game.day_night.set_time_hours(10.0)
	game.achievements.hide()
	p.global_position = vendor.npcs.camp.global_position + Vector3(0, 0, 1)
	p.active = true
	inv.open()
	await shot("inventory")
	inv.close()
	vendor.interact("camp")
	vendor.page = "Verkaufen"
	vendor._render()
	check(vendor._tabs.Verkaufen.visible and vendor.rows.get_child_count() >= 12, "Vendor renders sale rows for all mushrooms and supplies")
	await shot("vendor-sales")
	vendor.close()
	print("MUSHROOM_TRADE_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
