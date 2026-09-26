# 26 Sep 2026, second feedback round: the stag on its hooves while it really runs (the zombie loop reset
# the model height to 0 on every lean, putting the centred beast half into the ground), green conifers as
# thrown trees, liberty caps around the Goa party, the party bar's drinks and fireworks, the party's own
# firework show.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=batch28 --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	# an offline co-op session (like team_purse): the host is authoritative, Anna is a remote teammate
	var net: Node = root.get_node("NetSession")
	check(net.host("Host", 24697) == OK, "The fixture hosts a round")
	net.roster[2] = "Anna"
	net.world.add_player(2)
	net._begin(net.epoch, false)
	game.waves.set_process(false)
	var world = net.world
	var anna: Player = world.actor(2)
	anna.global_position = Map.ground_pos(-40, 60) + Vector3.UP * 0.3
	var player: Player = game.player
	# ---- the stag, live
	player.global_position = Map.ground_pos(40, 110) + Vector3.UP * 0.3
	for kind in ["zombie_stag", "zombie_dog"]:
		game.spawn_zombie(kind, Vector2(10, 126), 1.0)
		var beast: ZombieBeast = null
		for z in game.zombies_root.get_children():
			if z is ZombieBeast and z.net_kind == kind: beast = z
		var mesh: MeshInstance3D = beast.model.find_children("*", "MeshInstance3D", true, false)[0]
		var worst := INF
		for i in 30:
			for f in 5: await physics_frame
			if not beast.is_on_floor(): continue
			var aabb := mesh.get_aabb()
			var low := INF
			for k in 8: low = minf(low, (mesh.global_transform * aabb.get_endpoint(k)).y)
			worst = minf(worst, low - beast.global_position.y)
		check(worst > -0.12, "The running %s never dips below its feet (lowest %.2f m)" % [kind, worst])
		# hit it: the flinch must not tip it into the ground either
		worst = INF
		for hit in 4:
			beast.damage(beast.max_hp * 0.08, Vector3(0, 0, -1))
			for f in 4:
				await physics_frame
				var aabb := mesh.get_aabb()
				var low := INF
				for k in 8: low = minf(low, (mesh.global_transform * aabb.get_endpoint(k)).y)
				worst = minf(worst, low - beast.global_position.y)
		check(beast.alive and worst > -0.12, "Hit four times, the %s stays on its feet (lowest %.2f m)" % [kind, worst])
		beast.queue_free()
	player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.3
	# ---- the thrown tree is a green conifer
	var tree := ThrownTree.new()
	game.add_child(tree)
	tree.setup(Map.ground_pos(20, 120) + Vector3.UP * 14.0, Map.ground_pos(40, 120), 3.0, null, true)
	var model: Node3D = tree._visual.get_child(1)
	var instance := model.get_child(0) as MeshInstance3D
	var green := false
	if instance:
		for i in instance.mesh.get_surface_count():
			var mat := instance.mesh.surface_get_material(i) as BaseMaterial3D
			if mat and mat.albedo_color.g > mat.albedo_color.r: green = true
	check(instance != null and green, "The thrown tree is one of the forest's green conifers")
	var height := instance.get_aabb().size.y * instance.transform.basis.get_scale().y if instance else 0.0
	check(absf(height - ThrownTree.HEIGHT) < 0.6, "... %.1f m tall" % height)
	tree.queue_free()
	# ---- liberty caps around the party
	var caps := 0
	for item in game.loots:
		if item is Loot and item.kind == "mushroom" and item.id == "kahlkopf" and Vector2(item.global_position.x, item.global_position.z).distance_to(SecretNight.SITE) < 40.0: caps += 1
	check(caps >= 15, "Liberty caps crowd the party site (%d within 40 m)" % caps)
	# ---- the bar
	var night: SecretNight = game.secret_night
	var bar: PartyBar = night.bar
	player.global_position = Map.ground_pos(SecretNight.BAR.x, SecretNight.BAR.y + 2.0) + Vector3.UP * 0.3
	check(bar.prompt(player).is_empty(), "No bar before the party")
	check(bar.buy(player, "goa_sunrise") == "The bar is closed.", "... and no drinks")
	night.begin()
	player.global_position = Map.ground_pos(SecretNight.BAR.x, SecretNight.BAR.y + 2.0) + Vector3.UP * 0.3
	night.step = SecretNight.DANCE_STEP
	check(not bar.prompt(player).is_empty(), "During the party the bar serves (%s)" % bar.prompt(player))
	player.score = 500
	player.hp = 40.0
	var answer := Lang.text(bar.buy(player, "goa_sunrise"))
	check(player.score == 470 and player.hp == 70.0 and player.mushroom_effects.has("goa_sunrise") and Inventory.Mushrooms.multiplier(player.mushroom_effects, "speed") >= 1.25, "A Goa Sunrise costs 30, heals 30 and speeds you up (%s)" % answer)
	bar.buy(player, "bass_booster")
	check(Inventory.Mushrooms.multiplier(player.mushroom_effects, "reload") <= 0.7 and Inventory.Mushrooms.multiplier(player.mushroom_effects, "spread") <= 0.75, "The Bass Booster shortens reloads and tightens the spread")
	bar.buy(player, "neon_punch")
	check(game.hud.tripping() and Inventory.Mushrooms.multiplier(player.mushroom_effects, "damage") >= 1.4, "The Neon Mushroom Punch trips and hits harder")
	bar.buy(player, "clear_head")
	await create_timer(2.0).timeout
	check(not game.hud.tripping(), "The Clear Head sobers you up")
	check(Lang.text(Inventory.Mushrooms.summary(player.mushroom_effects)).contains("Goa Sunrise"), "Drinks show in the effect list")
	var before: int = player.score
	player.score = 10
	check(Lang.text(bar.buy(player, "bass_booster")).begins_with("Not enough") and player.score == 10, "No money, no drink")
	player.score = 400
	var rockets_before := int(game.fireworks.stock(player.peer_id).get("fw_aurora", 0))
	bar.buy(player, "fw_aurora")
	check(int(game.fireworks.stock(player.peer_id).get("fw_aurora", 0)) == rockets_before + 1 and player.score == 340, "The bar sells fireworks too")
	player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.3
	check(bar.buy(player, "moss_mojito") == "Walk up to the bar to order.", "Orders only at the bar")
	player.global_position = Map.ground_pos(SecretNight.BAR.x, SecretNight.BAR.y + 2.0) + Vector3.UP * 0.3
	bar.open()
	check(bar.is_open and bar.list.get_child_count() == Inventory.Mushrooms.DRINKS.size() + PartyBar.FIREWORKS.size(), "The menu lists %d drinks and %d fireworks" % [Inventory.Mushrooms.DRINKS.size(), PartyBar.FIREWORKS.size()])
	bar.close()
	check(not bar.is_open and player.active and not paused, "Close returns to the dance floor")
	bar.open()
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	bar._input(esc)
	check(not bar.is_open and player.active and not game.hud.overlay.visible, "Esc closes the bar without opening the pause menu")
	# ---- a teammate orders through the host (command "bar_order")
	anna.global_position = Map.ground_pos(SecretNight.BAR.x + 1.0, SecretNight.BAR.y + 2.0) + Vector3.UP * 0.3
	anna.score = 100
	anna.hp = 50.0
	world.action(2, "bar_order", ["spirit_shot"])
	check(anna.score == 65 and anna.hp == 70.0 and anna.mushroom_effects.has("spirit_shot"), "A teammate's order is paid and served by the host (%d R, %.0f HP)" % [anna.score, anna.hp])
	var snap: Dictionary = world.snapshot()
	check(snap.players.has(2) and snap.players[2].effects.has("spirit_shot"), "The drink's effect travels to the teammate's client in the snapshot")
	world.action(2, "bar_order", ["no_such_drink"])
	world.action(2, "bar_order", [12])
	check(anna.score == 65, "Unknown or malformed orders are refused")
	anna.global_position = Map.ground_pos(-40, 60) + Vector3.UP * 0.3
	world.action(2, "bar_order", ["moss_mojito"])
	check(anna.score == 65, "A teammate far from the bar cannot order")
	# ---- the party's own fireworks
	night.show_t = 0.0
	var launched := 0
	for i in 40:
		night._update_show(0.5)
	launched = night.show_rockets
	check(launched >= 5, "The party fires its own show (%d rockets in 20 s)" % launched)
	print("BATCH28_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
