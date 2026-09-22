extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var shop: Progression = game.progression
	var p: Player = game.player
	p.global_position = shop.npcs.camp.global_position + Vector3(0, 0, 2)
	p.score = 0
	shop.interact("camp")
	shop.request("quest", "arrival")
	check(shop.vendor_guide.visible and paused and not p.active, "First quest opens the tutorial inside the paused solo conversation")
	check(not shop.local_data().accepted.get("arrival", false) and p.score == 0, "Opening tutorial neither accepts quest nor spends or awards money")
	shop.vendor_guide.next.pressed.emit()
	shop.close()
	check(not shop.vendor_guide.visible and not paused and p.active and not shop._arrival_guide_read, "Closing an unfinished introduction restores gameplay without completing it")
	shop.interact("camp")
	shop.request("quest", "arrival")
	check(shop.vendor_guide.step == 1, "Returning to the first quest resumes the unfinished introduction")
	shop.vendor_guide.back.pressed.emit()
	check(shop.vendor_guide.step == 0, "Previous page can be revisited")
	for i in 3: shop.vendor_guide.next.pressed.emit()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		for i in 12: await process_frame
		var rect := shop.vendor_guide.next.get_global_rect()
		check(root.get_visible_rect().encloses(rect), "Tutorial navigation fits the 1280x720 viewport")
		check(shop.vendor_guide.body.get_content_height() <= shop.vendor_guide.body.size.y, "The longest tutorial page is readable without scrolling")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../logs/vendor-tutorial.png")
	shop.vendor_guide.next.pressed.emit()
	check(not shop.vendor_guide.visible and shop._arrival_guide_read and shop.local_data().accepted.get("arrival", false), "Finishing all four pages accepts the quest through the regular shop action")
	check(p.score == 0 and not shop.has_claim(p.peer_id, "arrival"), "Tutorial completion leaves the reward for the player to collect")
	shop.request("quest", "arrival")
	check(p.score == 20 and shop.has_claim(p.peer_id, "arrival"), "Reward can be collected exactly once after the introduction")
	shop._replay_vendor_guide()
	for i in 4: shop.vendor_guide.next.pressed.emit()
	check(p.score == 20 and not shop.vendor_guide.visible, "Replaying the introduction does not repeat a transaction or reward")
	shop.close()
	game.inventory.open()
	shop._process(0.3)
	check(shop._arrival_inventory_seen, "Opening the real inventory clears its follow-up hint")
	game.inventory.close()
	game.defences.begin_building()
	shop._process(0.3)
	check(shop._arrival_build_menu_seen and p.score == 20, "Opening the real build menu clears its hint without requiring a purchase")
	game.defences.close()
	print("VENDOR_TUTORIAL_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
