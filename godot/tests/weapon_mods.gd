extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

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
	p.set_physics_process(false)
	p.score = 20000
	p.global_position = shop.npcs.mechanic.global_position + Vector3(0, 0, 1)
	game.waves.completed = 0
	var reason := shop.transact(p, "mechanic", "mod", "extended", "pistol")
	check(Lang.text(reason).contains("Level") or Lang.text(reason).contains("level"), "Low level blocks installation")
	check(p.score == 20000 and w.mod_owned.is_empty(), "Rejected mod never charges or grants ownership")
	game.waves.completed = 15
	reason = shop.transact(p, "mechanic", "mod", "extended", "pistol")
	check(Lang.text(reason).contains(str(Progression.QUESTS.arrival.name)), "Quest lock names the missing quest")
	for id in Progression.QUESTS: shop.data(p.peer_id).claimed[id] = true
	shop.transact(p, "mechanic", "mod", "extended", "pistol")
	check(p.score == 19750 and w.state.pistol.def.mag == 18, "Purchase charges once and expands the actual magazine")
	check(w.state.pistol.ammo == 12 and w.state.pistol.reserve == 84, "Larger magazine gives no free ammunition")
	check(Weapons.DEFS.pistol.mag == 12 and w.state.smg.def.mag == 30, "Mods never mutate base definitions or other weapons")
	shop.transact(p, "mechanic", "mod", "extended", "pistol")
	check(p.score == 19750, "Repeated purchase is idempotent")
	w.state.pistol.ammo = 0
	w.reload()
	check(is_equal_approx(w.cur().reloading, 1.21), "Extended magazine reload penalty reaches the reload system")
	w._process(2.0)
	check(w.state.pistol.ammo == 18 and w.state.pistol.reserve == 66, "Reload transfers eighteen rounds from reserve")
	shop.transact(p, "mechanic", "remove_mod", Weapons.Mods.DEFS.extended.slot, "pistol")
	check(w.state.pistol.ammo == 12 and w.state.pistol.reserve == 72 and w.state.pistol.def.mag == 12, "Removing magazine preserves excess ammunition")
	shop.transact(p, "mechanic", "mod", "extended", "pistol")
	check(p.score == 19750 and w.state.pistol.def.mag == 18, "Owned mod can be reinstalled for free")
	w.state.pistol.ammo = 18
	w.state.pistol.reserve = w.reserve_limit("pistol")
	shop.transact(p, "mechanic", "remove_mod", Weapons.Mods.DEFS.extended.slot, "pistol")
	check(w.state.pistol.def.mag == 18 and w.state.pistol.ammo == 18, "Full reserve prevents lossy magazine removal")
	shop.transact(p, "mechanic", "mod", "suppressor", "pistol")
	check(is_equal_approx(w.state.pistol.def.sfx_db, -12) and w.state.pistol.def.flash_scale == 0.15 and is_equal_approx(w.state.pistol.def.range, 54), "Suppressor changes audio, flash and range")
	w.effects.fire("pistol", w.muzzle_transform(), Vector3.ZERO, w.state.pistol.def.flash_scale)
	check(w.effects.world_light.light_energy < 0.5, "Suppression reduces the actual muzzle lighting")
	w.effects.fire("pistol", w.muzzle_transform(), Vector3.ZERO)
	check(w.effects.world_light.light_energy > 3, "Unsuppressed shots restore full flash without cumulative profile mutation")
	shop.transact(p, "mechanic", "mod", "quick_action", "pistol")
	check(is_equal_approx(w.state.pistol.def.reload, 1.1 * 1.1 * 0.8), "Different slots combine multiplicatively")
	var balance := p.score
	shop.transact(p, "mechanic", "mod", "ghost", "pistol")
	shop.transact(p, "mechanic", "mod", "suppressor", "knife")
	shop.transact(p, "mechanic", "mod", "unknown", "pistol")
	shop.transact(p, "mechanic", "mod", "extended", "marksman")
	check(p.score == balance, "Wrong merchant, melee, unknown mod and unowned weapon are rejected")
	p.global_position = shop.npcs.secret.global_position + Vector3(0, 0, 1)
	shop.transact(p, "secret", "mod", "ghost", "pistol")
	check(w.state.pistol.def.sfx_db == -22 and w.state.pistol.def.range == 60, "Legendary muzzle replaces rather than stacks with suppressor")
	w.unlocked.marksman = true
	shop.transact(p, "secret", "mod", "titan_core", "marksman")
	check(is_equal_approx(w.state.marksman.def.damage, 198) and w.state.marksman.def.pierce_targets == 4, "Legendary barrel improves damage and piercing")
	w.unlocked.marksman = false
	p.global_position = shop.npcs.camp.global_position + Vector3(0, 0, 1)
	w.state.pistol.ammo = 0
	w.state.pistol.reserve = w.reserve_limit("pistol")
	var quote: Dictionary = shop.refill_quote(p)
	check(quote.rounds == 18 and quote.cost == 9, "Autorefill prices extended capacity at the normal per-round rate")
	shop.transact(p, "camp", "autorefill", "")
	check(w.state.pistol.ammo == 18, "Autorefill fills modified magazine")
	for id in Weapons.Mods.DEFS:
		var spec: Dictionary = Weapons.Mods.DEFS[id]
		var wid: String = spec.get("weapons", ["pistol"])[0]
		w.unlocked[wid] = true
		game.waves.completed = int(spec.level) - 2
		check(not shop.mod_lock_reason(p, id, wid).is_empty(), id + " blocked one level below requirement")
		game.waves.completed += 1
		check(shop.mod_lock_reason(p, id, wid).is_empty(), id + " unlocks at exact level with completed quest")
		shop.data(p.peer_id).claimed.erase(spec.quest)
		check(Lang.text(shop.mod_lock_reason(p, id, wid)).contains(str(Progression.QUESTS[spec.quest].name)), id + " still requires the named quest")
		shop.data(p.peer_id).claimed[spec.quest] = true
	game.waves.completed = 15
	p.global_position = shop.npcs.mechanic.global_position + Vector3(0, 0, 1)
	balance = p.score
	p.global_position += Vector3(30, 0, 0)
	shop.transact(p, "mechanic", "mod", "match_barrel", "pistol")
	check(p.score == balance, "Remote installation rejected")
	p.global_position = shop.npcs.mechanic.global_position + Vector3(0, 0, 1)
	p.score = 0
	shop.transact(p, "mechanic", "mod", "match_barrel", "pistol")
	check(not w.mod_owned.has("pistol:match_barrel"), "Insufficient money cannot grant a mod")
	shop.interact("mechanic")
	shop.page = "Mods"
	shop._render()
	shop._render()
	check(shop._tabs.Mods.visible and shop._row_nodes.size() == 10, "Mechanic mod menu renders and refreshes every slot")
	shop.close()
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var peer: Player = NetSession.world.actor(2)
	var proxy: Weapons = NetSession.world.weapons[2]
	peer.set_physics_process(false)
	proxy.set_process(false)
	peer.score = 1000
	peer.global_position = shop.npcs.mechanic.global_position + Vector3(0, 0, 1)
	shop.data(2).claimed.arrival = true
	shop.transact(peer, "mechanic", "mod", "extended", "pistol")
	check(proxy.state.pistol.def.mag == 18 and peer.score == 750, "Host validates and equips remote player mods")
	var snapshot: Dictionary = NetSession.world.snapshot().players[2]
	check(snapshot.mod_owned.has("pistol:extended") and not snapshot.mod_owned.has("pistol:ghost"), "Snapshot preserves individual ownership")
	NetSession.world.show_shot(2, "pistol", [-22.0, 0.03, 1.82])
	check(is_equal_approx(NetSession.world.avatars[2].flash.light_energy, 0.075), "Remote muzzle effect uses the host's modded shot values")
	w.apply_mod_snapshot(snapshot.mod_owned, snapshot.mod_loadout)
	check(w.state.pistol.def.mag == 18 and w.state.pistol.def.sfx_db == 2, "Snapshot rebuilds effective stats without leaking another player's mods")
	NetSession.enabled = false
	if "--render-mods" in OS.get_cmdline_user_args():
		p.score = 2000
		game.waves.completed = 3
		shop.interact("mechanic")
		shop.page = "Mods"
		shop._render()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/weapon-mods"))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/weapon-mods/mechanic.png"))
		shop.close()
		p.global_position = shop.npcs.secret.global_position + Vector3(0, 0, 1)
		shop.interact("secret")
		shop.page = "Mods"
		shop._render()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/weapon-mods/secret.png"))
		shop.close()
	print("WEAPON_MODS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
