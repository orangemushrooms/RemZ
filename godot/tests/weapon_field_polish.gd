extends SceneTree
var checks := 0
var failures := 0
var game: Node3D
var forest := false

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", message)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/weapon-field-polish/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + ("forest-" if forest else "planes-") + name + ".png")

func open_shop(id: String, page: String) -> void:
	var shop: Progression = game.progression
	game.player.position = shop.npcs[id].position + Vector3(0, 0, 1)
	if forest: shop.interact(id)
	else: shop.open_field(id)
	shop.page = page
	shop._render()
	check(shop.is_open and shop.page == page, "%s %s opens on %s" % [id, page, "Forest" if forest else "Planes"])

func finish() -> void:
	print("WEAPON_FIELD_POLISH_DONE map=%s checks=%d failures=%d" % ["forest" if forest else "planes", checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	forest = "--forest" in OS.get_cmdline_user_args()
	game = load("res://scenes/main.tscn" if forest else "res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	if forest:
		while not game.navigation_ready: await process_frame
		game._on_start()
	else:
		while not game.ready_for_exploration: await process_frame
		await game.start_survival()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.weather.force("clear")
	game.day_night.set_time_hours(11.0)
	var boot := BootScreen.find(self)
	if boot: boot.hide()
	game.hud.message("", 0)
	var w: Weapons = game.weapons
	check(Weapons.DEFS.sawed_off.mag == 3 and Weapons.DEFS.sawed_off.reload == 1.4 and Weapons.DEFS.sawed_off.damage == 28, "Sawed-Off has three stronger shots and faster reload")
	check(Weapons.DEFS.tommy_gun.mag == 70, "Tommy drum has seventy rounds")
	w.unlock("sawed_off")
	w.set_weapon("sawed_off")
	w.cur().ammo = 0
	w.cur().reserve = 12
	w.reload()
	check(w.cur().reloading <= 1.4, "Actual sawed-off reload uses the shorter duration")
	w._process(2.0)
	check(w.cur().ammo >= 3 and w.cur().reserve == 12 - w.cur().ammo, "Reload transfers a full magazine without creating ammunition")
	for id in Weapons.ORDER:
		if Weapons.is_melee(id): continue
		w.unlock(id)
		var arm: Node3D = w.state[id].hands.get_node("TriggerHand")
		var glove: Node3D = arm.get_node("Glove")
		var skeleton: Skeleton3D = glove.find_child("Skeleton3D", true, false)
		var tip := glove.transform * skeleton.get_bone_global_pose(skeleton.find_bone("finger_index_r_end")).origin
		var error: float = tip.distance_to(arm.get_meta("trigger_target"))
		check(error < 0.012, "%s trigger finger within 12 mm (%.1f mm)" % [id, error * 1000])
	w.set_weapon("pistol")
	var shop: Progression = game.progression
	game.player.score = 50000
	game.waves.wave = 20
	game.waves.completed = 19
	if forest:
		for id in Progression.QUESTS: shop.data(game.player.peer_id).claimed[id] = true
	open_shop("mechanic", "Mods")
	var chooser := shop.rows.find_child("ModWeaponChooser", true, false)
	check(chooser.get_child_count() == 23, "Mod menu lists every owned firearm even with pistol equipped")
	chooser.get_node("tommy_gun").pressed.emit()
	check(shop._mod_weapon == "tommy_gun" and w.current == "pistol", "Menu selection edits a stowed weapon without switching the equipped pistol")
	shop.request("mod", "extended", "tommy_gun")
	check(w.mod_loadout.get("tommy_gun", {}).get("Magazine") == "extended" and w.state.tommy_gun.def.mag >= 105, "Selected stowed Tommy receives the purchased magazine")
	var balance: int = game.player.score
	shop.request("remove_mod", "Magazine", "tommy_gun")
	shop.request("mod", "extended", "tommy_gun")
	check(game.player.score == balance, "Owned mod can be removed and mounted again for free")
	shop._render()
	await capture("mods")
	shop.close()
	for vendor in ["camp", "secret"]:
		open_shop(vendor, "Trade")
		check(shop._row_nodes.any(func(row): return row[5].visible), vendor + " renders graphical weapon attributes")
		shop.rows.get_parent().scroll_vertical = 245
		await capture(vendor + "-vendor")
		shop.close()
	open_shop("secret", "Mods")
	chooser = shop.rows.find_child("ModWeaponChooser", true, false)
	check(chooser.get_child_count() == 23, "Secret vendor lists all owned firearms for modding")
	chooser.get_node("marksman").pressed.emit()
	shop.request("mod", "titan_core", "marksman")
	check(w.state.marksman.def.pierce_targets == 4 and w.current == "pistol", "Secret vendor installs legendary mod on stowed rifle")
	shop._render()
	await capture("secret-mods")
	shop.close()
	if forest:
		var grenade := Grenade.new()
		game.add_child(grenade)
		grenade.zombies_root = game.zombies_root
		grenade.position = game.player.position
		grenade._explode()
		var flare := WeaponSpecials.Flare.new()
		flare.specials = w.specials
		flare.authoritative = true
		flare.owner_peer = game.player.peer_id
		game.add_child(flare)
		flare._impact(game.player.position, null)
		check(is_instance_valid(game), "Grenade and flare hooks also complete on Forest")
		for i in 3: await process_frame
		finish()
		return
	var range_house = game.shooting_range
	for i in 8:
		range_house.reset_run()
		check(range_house.key_spawned and range_house.key.visible, "Schuetzenhaus key spawns on fresh run %d" % i)
	var fires = game.cornfield.fires
	fires.set_process(false)
	check(fires.wheat.size() > 100, "Wheat fire uses actual planted cells")
	var cell: Vector2i = fires.wheat.keys()[fires.wheat.size() / 2]
	var point: Vector3 = fires.wheat[cell]
	fires.ignite(point + Vector3.UP * 100, 3.5, 1, "flare_pistol")
	check(fires.active.is_empty(), "An airborne flare does not ignite distant ground")
	fires.ignite(point, 3.5, 1, "flare_pistol")
	check(fires.active.has(cell), "Ground flare ignites wheat")
	var enemy: Zombie = game.create_enemy("runner", point, 1)
	enemy.set_physics_process(false)
	var hp := enemy.hp
	fires._process(0.25)
	game.progression.rare_market.tick_statuses(1.0)
	check(enemy.hp < hp and enemy.rare_status.contains("fire"), "Zombie inside burning wheat receives fire damage")
	var before: int = fires.burned.size()
	fires._process(2.1)
	check(fires.burned.size() >= before and fires.active.size() <= fires.MAX_ACTIVE, "Fire spreads with bounded active cells")
	var state: Dictionary = fires.snapshot()
	fires.reset_run()
	fires.apply_snapshot(state)
	check(fires.burned.size() == state.burned.size() and fires.active.size() == state.active.size(), "Late-join snapshot restores flames and burned wheat")
	game.player.position = point + Vector3(0, 2, 9)
	game.player.camera.look_at(point)
	fires._update_effects()
	for i in 40: await process_frame
	await capture("wheat-fire")
	if DisplayServer.get_name() != "headless":
		# Compare the same view and charred crop geometry, with/without the pooled flames.
		for effect in fires.effects: effect.emitting = false
		for i in 60: await process_frame
		var baseline_start := Time.get_ticks_usec()
		for i in 60: await process_frame
		var baseline_ms := (Time.get_ticks_usec() - baseline_start) / 60000.0
		fires._update_effects()
		for i in 60: await process_frame
		var burning_start := Time.get_ticks_usec()
		for i in 60: await process_frame
		print("FIRE_RENDER baseline_ms=%.2f burning_ms=%.2f active=%d" % [baseline_ms, (Time.get_ticks_usec()-burning_start)/60000.0, fires.active.size()])
	var start := Time.get_ticks_usec()
	for i in 100: fires._process(0.25)
	print("FIRE_TICK_AVG_US=", (Time.get_ticks_usec() - start) / 100.0)
	check(fires.active.size() <= fires.MAX_ACTIVE, "Sustained spread keeps the emitter limit")
	fires.reset_run()
	var grenade := Grenade.new()
	game.add_child(grenade)
	grenade.zombies_root = game.zombies_root
	grenade.position = point
	grenade._explode()
	check(not fires.active.is_empty(), "Grenade explosion ignites wheat through combat hook")
	fires.reset_run()
	var flare := WeaponSpecials.Flare.new()
	flare.specials = w.specials
	flare.authoritative = true
	flare.owner_peer = game.player.peer_id
	game.add_child(flare)
	flare._impact(point, null)
	check(not fires.active.is_empty(), "Flare projectile impact ignites wheat through combat hook")
	# Actual weather transitions must extinguish existing fires, preserve the
	# spent-fuel mask, and block both combat ignition hooks until rain stops.
	for weather_state in ["rain", "storm"]:
		fires.reset_run()
		game.weather.force("clear")
		fires.ignite(point, 3.5, 1, "flare_pistol")
		fires._process(0.25)
		var charred: int = fires.burned.size()
		game.weather.force(weather_state)
		game.weather._process(Weather.FADE_SECONDS)
		fires._process(0.25)
		check(game.weather.is_raining() and fires.active.is_empty(), weather_state + " extinguishes the field fire")
		check(fires.burned.size() == charred and fires.mask.get_pixelv(cell).r > 0.9, weather_state + " preserves charred wheat")
		check(fires.effects.all(func(effect): return not effect.emitting), weather_state + " stops every fire emitter")
		var extinguished: Dictionary = fires.snapshot()
		fires.reset_run()
		fires.apply_snapshot(extinguished)
		check(fires.active.is_empty() and fires.burned.size() == charred, weather_state + " snapshot keeps the fire extinguished for joining players")
		fires.reset_run()
		var wet_grenade := Grenade.new()
		game.add_child(wet_grenade)
		wet_grenade.zombies_root = game.zombies_root
		wet_grenade.position = point
		wet_grenade._explode()
		var wet_flare := WeaponSpecials.Flare.new()
		wet_flare.specials = w.specials
		wet_flare.authoritative = true
		wet_flare.owner_peer = game.player.peer_id
		game.add_child(wet_flare)
		wet_flare._impact(point, null)
		check(fires.active.is_empty() and fires.burned.is_empty(), weather_state + " blocks both grenade and flare ignition")
		var wet_enemy: Zombie = game.create_enemy("shambler", point, 1)
		wet_enemy.set_physics_process(false)
		var wet_hp := wet_enemy.hp
		fires._process(0.25)
		game.progression.rare_market.tick_statuses(1.0)
		check(wet_enemy.hp == wet_hp and not wet_enemy.rare_status.contains("fire"), weather_state + " prevents field fire damage to a passing zombie")
		game.weather.force("clear")
		fires.ignite(point, 3.5, 1, "flare_pistol")
		check(not fires.active.is_empty(), "Fresh wheat can burn again after " + weather_state + " ends")
	game.weather.force("fog")
	game.weather._process(Weather.FADE_SECONDS)
	fires._process(0.25)
	check(not fires.active.is_empty(), "Fog alone does not extinguish field fires")
	game.weather.force("clear")
	fires.reset_run()
	check(fires.burned.is_empty() and fires.active.is_empty() and fires.effects.all(func(effect): return not effect.emitting), "New run clears fire, charred mask and emitters")
	for i in 3: await process_frame
	finish()
