extends SceneTree

var checks := 0
var failures := 0
var game: Node3D
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 480000: quit(2)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	CharacterProfile.persist = false
	CharacterProfile.data = CharacterProfile.empty_profile("Onboarding")
	var planes := "--planes-onboarding" in OS.get_cmdline_user_args()
	game = load("res://scenes/planes.tscn" if planes else "res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if planes:
		while not game.ready_for_exploration or game.preparing_survival or game.boot != null: await process_frame
	else: game._on_start(false)
	paused = false
	game.waves.set_process(false)
	game.weapons.set_process(false)
	game.expedition.set_process(false)
	game.player.set_physics_process(false)
	game.player.active = true
	game.hud.overlay.hide()
	var shop: Progression = game.progression
	shop.set_process(false)
	shop._process(0.3)
	check(shop.tracker.visible and not shop.tutorial.visible, "Fresh arrival has one objective and no extra tutorial card")
	check(not shop.tracker.text.contains("[") and not shop.tracker.text.contains("Q") and not shop.tracker.text.contains("J"), "Arrival objective contains no menu shortcut list")
	check(shop.tracker.text.split("\n").size() == 2, "Arrival objective is only a heading and a next step")
	game.expedition.book.open()
	check(game.expedition.book.is_open, "Fieldbook is available before meeting Vendor")
	game.expedition.book.close()
	game.player.global_position = shop.npcs.camp.global_position + Vector3(0, 0, 2)
	if planes: shop.open_field("camp")
	else: shop.interact("camp")
	shop._replay_vendor_guide()
	check(shop.vendor_guide.visible, "Both maps offer the optional Vendor introduction")
	shop.vendor_guide.step = 1
	for id in ["gunslinger", "assault", "breacher", "marksman", "assassin"]:
		shop.vendor_guide.class_id = id
		shop.vendor_guide.refresh()
		check(shop.vendor_guide.keys.text == ("V" if id == "assassin" else "Z"), "Vendor gives the actual ability key for " + id)
		check(shop.vendor_guide.body.text == shop.vendor_guide.CLASS_LESSONS[id], "Vendor explains the selected class effect for " + id)
	shop.vendor_guide.step = 3
	shop.vendor_guide.refresh()
	check(shop.vendor_guide.body.text.contains("click"), "Building lesson teaches actual planner mouse placement")
	check(shop.vendor_guide.body.text.contains("kits") == planes, "Building lesson matches the current map")
	shop.vendor_guide.advance()
	shop.close()
	game.waves.phase = "spawning"
	shop._process(0.3)
	check(not shop.tutorial.visible, "Menu lessons wait for a genuine wave break, even before distant enemies arrive")
	game.waves.phase = "idle"
	shop._process(0.3)
	check(shop.tutorial.visible and not shop.tracker.visible and shop._onboarding_topic == "inventory_tip", "After the briefing one practical inventory hint replaces the quest")
	game.inventory.open()
	shop._process(0.3)
	check(shop._arrival_inventory_seen and shop._lesson_seen("inventory"), "Using the real inventory completes its lesson persistently")
	check(not shop.tutorial.visible, "Guidance is hidden inside the inventory")
	game.inventory.close()
	shop._process(0.3)
	check(shop._onboarding_topic == "book_tip", "The fieldbook follows inventory as a separate quiet lesson")
	game.expedition.book.open()
	shop._process(0.3)
	check(shop._arrival_book_seen and shop._lesson_seen("book"), "Opening the fieldbook completes its practical lesson")
	game.expedition.book.close()
	shop._process(0.3)
	check(not shop.tutorial.visible, "No unsolicited building menu hint before a building quest")
	# A real nearby Zombie drives the first-combat lesson, without waiting for a wave.
	var enemy := Zombie.new()
	enemy.setup("shambler", game.player, game.barricades, 1.0, func(_enemy): pass)
	enemy.set_physics_process(false)
	game.zombies_root.add_child(enemy)
	enemy.global_position = game.player.global_position + Vector3(0, 0, -8)
	shop._process(0.3)
	check(shop.tutorial.visible and shop._onboarding_topic == "class_gunslinger", "First nearby threat introduces the matching class action")
	for i in 9: shop._process(1.0)
	check(not shop.tutorial.visible and shop._lesson_seen("class_gunslinger"), "Combat lesson expires and cannot nag repeatedly")
	for i in 12: shop._process(1.0)
	check(not shop.tutorial.visible, "The same threat never replays an acknowledged lesson")
	enemy.queue_free()
	await process_frame
	# Repeat players can opt out of all remaining practical tips in one action.
	if planes: shop.open_field("camp")
	else: shop.interact("camp")
	shop._replay_vendor_guide()
	shop.vendor_guide.skip.pressed.emit()
	check(not shop.vendor_guide.visible and shop._lesson_seen("building_tip"), "Skip guidance immediately closes the introduction and suppresses remaining prompts")
	shop.close()
	var restored := Progression.new()
	restored._load_onboarding()
	check(restored._arrival_guide_read and restored._arrival_inventory_seen and restored._arrival_book_seen, "A fresh progression object restores the player's learned controls")
	restored.free()
	if planes:
		var snapshot: Dictionary = shop.snapshot()
		shop.collectibles[0].taken = true
		shop.collectibles[0].node.hide()
		game.nature.hide_harvested(0)
		shop.apply_snapshot(snapshot, true)
		check(not shop.collectibles[0].taken and shop.collectibles[0].node.visible, "Restoring an earlier Planes snapshot returns harvested quest baskets")
		check(not game.nature._picked.has(0), "Restoring an earlier Planes snapshot restores wild plants too")
	print("ONBOARDING_POLISH_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
