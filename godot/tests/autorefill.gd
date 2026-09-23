extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", text)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	var shop: Progression = game.progression
	p.set_physics_process(false)
	w.set_process(false)
	p.global_position = shop.npcs.camp.global_position + Vector3(0, 0, 1)
	for id in Weapons.ORDER:
		w.unlock(id)
		w.state[id].ammo = 0
		w.state[id].reserve = 0
	p.score = 10000
	var quote := shop.refill_quote(p)
	var grenades := w.grenades
	w.state.pistol.reloading = 1.0
	shop.transact(p, "camp", "autorefill", "")
	check(p.score == 10000 - int(quote.full_cost), "Full refill charges exactly the quoted total")
	for id in Weapons.ORDER:
		if Weapons.is_melee(id): continue
		check(w.state[id].ammo == Weapons.DEFS[id].mag and w.state[id].reserve == w.reserve_limit(id), id + " magazine and reserve reach their limits")
	check(w.state.pistol.reloading == 0 and w.grenades == grenades, "Refill cancels affected reloads and keeps grenades separate")
	var balance := p.score
	shop.transact(p, "camp", "autorefill", "")
	check(p.score == balance, "Already full cannot charge twice")
	w.set_weapon("pistol")
	w.state.pistol.ammo = 0
	w.state.pistol.reserve = 0
	w.state.revolver.reserve = 0
	p.score = 3
	quote = shop.refill_quote(p)
	check(quote.rounds == 6 and quote.cost == 3, "Small budget buys proportional rounds at existing ammo prices")
	shop.transact(p, "camp", "autorefill", "")
	check(p.score == 0 and w.state.pistol.ammo == 6 and w.state.pistol.reserve == 0 and w.state.revolver.reserve == 0, "Partial refill prioritizes current weapon and magazine without overdraft")
	shop.transact(p, "camp", "autorefill", "")
	check(p.score == 0 and w.state.pistol.ammo == 6, "Zero budget never grants free ammunition")
	p.score = 100
	w.unlocked.revolver = false
	shop.transact(p, "camp", "autorefill", "")
	check(w.state.revolver.reserve == 0 and not w.unlocked.revolver, "Locked weapon receives no ammunition")
	p.score = 100
	w.state.pistol.reserve = 0
	p.global_position += Vector3(20, 0, 0)
	shop.transact(p, "camp", "autorefill", "")
	check(p.score == 100 and w.state.pistol.reserve == 0, "Remote purchase is rejected atomically")
	p.global_position = shop.npcs.mechanic.global_position + Vector3(0, 0, 1)
	shop.transact(p, "mechanic", "autorefill", "")
	check(p.score == 100 and w.state.pistol.reserve == 0, "Mechanic cannot perform vendor refill")
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var peer: Player = NetSession.world.actor(2)
	var proxy: Weapons = NetSession.world.weapons[2]
	peer.set_physics_process(false)
	proxy.set_process(false)
	peer.global_position = shop.npcs.secret.global_position + Vector3(0, 0, 1)
	peer.score = 5
	proxy.state.pistol.ammo = 0
	proxy.state.pistol.reserve = 0
	NetSession.world.action(2, "shop", ["secret", "autorefill", "", ""])
	check(peer.score == 0 and proxy.state.pistol.ammo == 10 and p.score == 100 and w.state.pistol.reserve == 0, "Host refills only requesting peer's ammunition and debits that peer")
	NetSession.enabled = false
	p.global_position = shop.npcs.camp.global_position + Vector3(0, 0, 1)
	shop.interact("camp")
	shop.page = "Trade"
	shop._render()
	if "--render-autorefill" in OS.get_cmdline_user_args():
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../artifacts/autorefill/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder + "vendor.png")
	shop.close()
	print("AUTOREFILL_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
