extends SceneTree

const Recipes = preload("res://scripts/brew_recipes.gd")
const Flowers = preload("res://scripts/field_flowers.gd")
var checks := 0
var failures := 0
var game: Node3D

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func shot(id: String) -> void:
	if "--render-brewing" not in OS.get_cmdline_user_args(): return
	var dir := ProjectSettings.globalize_path("res://../artifacts/brewing/")
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir + id + ".png")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	if "--render-brewing" in OS.get_cmdline_user_args():
		Lang.set_language("de")
		game.day_night.set_time_hours(12)
		await create_timer(2.5).timeout
	var p: Player = game.player
	var brew = game.brewing
	brew.set_process(false)
	var layout := Flowers.locations(game)
	check(layout == Flowers.locations(game), "Deterministic flower layout for all peers")
	var kinds := {}
	var all_clear := true
	for entry in layout:
		kinds[entry.kind] = true
		all_clear = all_clear and Flowers.clear_ground(game, entry.at)
	check(layout.size() >= 36 and kinds.size() == 6, "All six flowers distributed across fields (%d plants)" % layout.size())
	check(all_clear, "Flowers avoid roads, buildings, forest, corn, pond and steep slopes")
	if "--render-brewing" in OS.get_cmdline_user_args():
		var at: Vector2 = layout[layout.size() / 2].at
		p.global_position = Map.ground_pos(at.x, at.y + 2.4)
		p.camera.look_at(Map.ground_pos(at.x, at.y) + Vector3.UP * 0.45)
		await shot("field")
	var plant: Loot
	for item in game.loots:
		if item is Loot and item.kind == "flower": plant = item; break
	check(plant != null and plant.get_child_count() > 0, "Flower pickup uses supplied model")
	if plant:
		var kind := plant.id
		plant.take(game.weapons, game.hud)
		plant.take(game.weapons, game.hud)
		check(int(brew.stock(1).flowers[kind]) == 1 and plant.taken, "Picking twice grants only one flower and removes visual")
	var bag: Dictionary = brew.stock(1)
	for kind in Recipes.FLOWERS: bag.flowers[kind] = 12
	for kind in Inventory.MUSHROOMS: game.inventory.mushrooms[kind] = 4
	p.global_position = Map.ground_pos(100, 100)
	brew.transact(p, "brew", "brew_meadow")
	check(brew.jobs.is_empty() and bag.flowers.golden_yarrow == 12, "Remote crafting rejected without spending ingredients")
	if brew.stations.size() > 1:
		var small: Vector2 = Map.SMALL_CAMPSITE.pos
		p.global_position = Map.ground_pos(small.x + 0.7, small.y + 2.2)
		await physics_frame
		check(brew.station_for(p) == 1, "Small woodland campfire also supports brewing")
	p.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 2.5)
	p.camera.look_at(brew.stations[0] + Vector3.UP * 0.6)
	await physics_frame
	check(brew.station_for(p) == 0, "Main campfire kettle reachable beside grill")
	check(game.hunting.at_grill(p), "Existing E grill remains reachable")
	game._process(0.01)
	check(Lang.text(game.hud.prompt_label.text).contains("[C]"), "Campfire advertises brewing key")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	brew.menu._unhandled_input(key)
	await process_frame
	await process_frame
	check(brew.menu.is_open and paused and not p.active, "C opens menu and pauses solo combat")
	brew.menu.rows.brew_meadow.button.pressed.emit()
	check(brew.jobs.has(1) and bag.flowers.golden_yarrow == 10, "Menu button reserves exact ingredients")
	brew.transact(p, "brew", "brew_meadow")
	check(bag.flowers.golden_yarrow == 10, "Repeated requests cannot overlap jobs")
	brew.advance_jobs(3.0)
	check(bag.drinks.is_empty(), "No bottle before brewing finishes")
	brew._process(0)
	await shot("menu")
	check(brew.menu.panel.size.y < 850 and brew.menu.panel.scale.x >= 0.8, "Brewing menu keeps readable scale without runaway wrapped-label height")
	if "--render-brewing" in OS.get_cmdline_user_args():
		brew.menu.close()
		await shot("kettle")
		brew.menu.open()
	brew.advance_jobs(1.1)
	check(bag.drinks.brew_meadow == 1 and brew.jobs.is_empty(), "Finished brew awards one bottle")
	brew.menu.close()
	check(not paused and p.active, "Closing restores gameplay")
	bag.flowers.ember_lily = 0
	var before: int = game.inventory.mushrooms.reizker
	brew.transact(p, "brew", "brew_ember")
	check(brew.jobs.is_empty() and game.inventory.mushrooms.reizker == before, "Missing flower never spends the mushroom")
	bag.flowers.ember_lily = 2
	brew.transact(p, "brew", "brew_ember")
	check(bag.flowers.ember_lily == 1 and game.inventory.mushrooms.reizker == before - 1, "Mixed recipe consumes flower and mushroom")
	brew.advance_jobs(4.1)
	bag.drinks.brew_meadow = Recipes.DRINK_LIMIT
	before = bag.flowers.golden_yarrow
	brew.transact(p, "brew", "brew_meadow")
	check(brew.jobs.is_empty() and bag.flowers.golden_yarrow == before, "Bottle cap preserves ingredients")
	brew.transact(p, "brew", "bad_id")
	brew.transact(p, "bad_action", "brew_meadow")
	check(brew.jobs.is_empty(), "Unknown recipes and actions rejected")
	p.hp = p.max_hp
	brew.transact(p, "drink", "brew_meadow")
	check(bag.drinks.brew_meadow == 8, "Full health preserves healing tea")
	p.hp = 20
	game.quickbar.bind_item(2, "brew_meadow")
	game.quickbar.activate(2)
	check(p.hp == 65 and bag.drinks.brew_meadow == 7, "Quickbar drinks tea and heals 45")
	for kind in Recipes.DRINKS: bag.drinks[kind] = 2
	brew.transact(p, "drink", "brew_fleet")
	check(is_equal_approx(p.mushroom_multiplier("speed"), 1.35), "Speed brew affects actual movement multiplier")
	p.mushroom_effects.brew_fleet = 1
	brew.transact(p, "drink", "brew_fleet")
	check(p.mushroom_effects.brew_fleet == 45 and is_equal_approx(p.mushroom_multiplier("speed"), 1.35), "Repeat drink refreshes without stacking")
	brew.transact(p, "drink", "brew_rose")
	p.hp = p.max_hp
	p.damage(20)
	check(is_equal_approx(p.hp, p.max_hp - 16), "Rose tonic reduces real incoming damage")
	brew.transact(p, "drink", "brew_focus")
	check(is_equal_approx(p.mushroom_multiplier("reload"), 0.65) and is_equal_approx(p.mushroom_multiplier("spread"), 0.6), "Focus brew supports reload and precision")
	brew.transact(p, "drink", "brew_spring")
	check(p.hp == p.max_hp and p.mushroom_multiplier("regen") == 3, "Spring cordial heals and boosts regeneration")
	brew.transact(p, "drink", "brew_dream")
	check(is_equal_approx(p.mushroom_multiplier("damage"), 1.65), "Dream brew increases combat damage")
	p.mushroom_effects.fliegenpilz = 20
	check(p.mushroom_multiplier("damage") == 2, "Mushroom and drink bonuses use strongest value")
	Inventory.Mushrooms.tick(p.mushroom_effects, 60)
	check(p.mushroom_effects.is_empty() and p.mushroom_multiplier("speed") == 1, "All buffs expire cleanly")
	game.hud.sober()
	if "--render-brewing" in OS.get_cmdline_user_args(): await create_timer(1.6).timeout
	# Actual aura status path, then obstacle occlusion.
	p.global_position = Map.ground_pos(42, 102)
	var z := Zombie.new()
	z.setup("shambler", p, [], 1.0, func(_z): pass)
	z.replica = true
	z.net_kind = "shambler"
	game.zombies_root.add_child(z)
	z.global_position = Map.ground_pos(46, 102)
	z.set_physics_process(false)
	brew.transact(p, "drink", "brew_frost")
	brew.tick_auras(0.1)
	check(z.rare_status.contains("frost") and z.frost_mul < 1, "Frost pulse slows nearby zombies")
	brew.transact(p, "drink", "brew_ember")
	brew.tick_auras(0.1)
	check(z.rare_status.contains("fire"), "Ember pulse ignites zombies through shared status system")
	var wall := StaticBody3D.new()
	wall.collision_layer = 8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 6, 6)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = p.global_position + Vector3(1, 1, 0)
	await physics_frame
	await physics_frame
	z.rare_status = ""
	brew.tick_auras(4)
	check(z.rare_status.is_empty(), "Aura cannot pass through walls")
	wall.queue_free()
	if "--render-brewing" in OS.get_cmdline_user_args():
		await physics_frame
		await physics_frame
		brew.tick_auras(4)
		z.update_rare_visual()
		p.camera.look_at(z.global_position + Vector3.UP)
		game.hud.msg_label.text = ""
	await shot("aura")
	z.queue_free()
	game.inventory.open()
	check(game.inventory.grid.get_child_count() > 12, "Inventory contains flower ingredients and drink slots")
	await shot("inventory")
	game.inventory.close()
	var saved: Dictionary = brew.snapshot()
	bag.flowers.crimson_rose = 999
	brew.apply_snapshot(saved)
	check(brew.stock(1).flowers.crimson_rose != 999, "Snapshot restores independent stock copies")
	# Authoritative host dispatch and independent teammate stock (offline multiplayer peer).
	var net = root.get_node("NetSession")
	net.set_process(false)
	net.enabled = true
	net.world = preload("res://scripts/coop_world.gd").new()
	net.world.setup(game)
	net.world.add_player(1)
	net.world.add_player(42)
	var other: Player = net.world.actor(42)
	other.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y + 2.5)
	brew.stock(42).flowers.golden_yarrow = 4
	before = brew.stock(1).flowers.golden_yarrow
	net.world.action(42, "brewing", ["brew", "brew_meadow"])
	check(brew.jobs.has(42) and brew.stock(42).flowers.golden_yarrow == 2 and brew.stock(1).flowers.golden_yarrow == before, "Host dispatch consumes only requesting peer's ingredients")
	check(net.world.snapshot().brewing.jobs.has(42), "Late-join snapshot includes running brews")
	brew.advance_jobs(4.1)
	other.hp = 10
	net.world.action(42, "brewing", ["drink", "brew_meadow"])
	check(other.hp == 55 and brew.stock(42).drinks.brew_meadow == 0, "Host applies remote drinking exactly once")
	net.world.action(42, "brewing", ["drink", "brew_meadow"])
	check(other.hp == 55, "Duplicate remote consumption cannot duplicate healing")
	other.downed = true
	net.world.action(42, "brewing", ["brew", "brew_meadow"])
	check(not brew.jobs.has(42), "Downed player cannot brew")
	net.enabled = false
	net.world = null
	await process_frame
	await process_frame
	print("BREWING_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
