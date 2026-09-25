# Mara's search quests, the palisade damage transfer with its HUD arrows, the headshot head burst, the
# 19:00 flashlight and the doubled training prices (25 Sep 2026).
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=forest_finds --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var game: Node
var started_at := Time.get_ticks_msec()
var capture := false

# --render-finds (windowed): artifacts/finds/<label>.png of the trip, the attack arrows and the burst head
func screenshot(label: String) -> void:
	if not capture: return
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/finds")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("FOREST_FINDS_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String, detail := "") -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description + ("" if detail.is_empty() else " (" + detail + ")"))

func run() -> void:
	capture = "--render-finds" in OS.get_cmdline_user_args()
	if capture:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready:
		await process_frame
	game._on_start()
	game.waves.set_process(false)
	var player: Player = game.player
	var progression = game.progression
	for i in 3: await process_frame

	# training prices
	check(Skills.training_cost(Skills.UPGRADES[0], 0) == 200 and Skills.training_cost(Skills.UPGRADES[0], 1) == 300, "Training costs twice the listed base and grows per tier")

	# the finds are placed once the navigation map is ready (place_cache runs from main)
	progression.place_finds()
	for id in ["pond_box", "trip_mushroom", "maze_crate"]:
		check(progression.finds[id].ready, "Find '%s' has a position" % id)
	var pond_pos: Vector3 = progression.finds.pond_box.node.global_position
	check(Map.POND.is_empty() or Vector2(pond_pos.x, pond_pos.z).distance_to(Map.POND.pos) < float(Map.POND.r) + 4.0, "Supply box lies at the pond shore")
	var crate_pos: Vector3 = progression.finds.maze_crate.node.global_position
	var corn = game.cornfield
	if corn and not corn.passages.is_empty():
		var crate_cell := Vector2i((corn.world_to_field(Vector2(crate_pos.x, crate_pos.z)) - corn.ORIGIN) / corn.CELL)
		check(corn.inside_maze(Vector2(crate_pos.x, crate_pos.z)) and corn.passages.has(crate_cell), "Crate stands on a cleared passage inside the maize maze")
		check(crate_cell.y > 0 and crate_cell.y < corn.SIZE - 1, "Crate is not on an entrance row")
	var shroom_pos: Vector3 = progression.finds.trip_mushroom.node.global_position
	check(Map.in_forest(shroom_pos.x, shroom_pos.z) and not Map.on_road(shroom_pos.x, shroom_pos.z, 2.0), "Strange mushroom grows in the forest off the tracks")
	check(Vector2(shroom_pos.x, shroom_pos.z).distance_to(Map.FIRE) > 50.0, "Strange mushroom is a walk away from the fire")

	# finding without the quest is refused, with the quest it counts
	var d: Dictionary = progression.data(1)
	game.waves.completed = 6
	if not d.has("accepted_wave"): d.accepted_wave = {}
	for prerequisite in ["arrival", "forest_basket"]:
		d.accepted[prerequisite] = true
		d.claimed[prerequisite] = true
	for id in ["pond_cache", "trip_mushroom", "maze_crate"]:
		d.accepted_wave[id] = 0
	player.global_position = pond_pos + Vector3(1.6, 0.1, 0)
	await physics_frame
	await physics_frame
	check(progression.nearest(player) == "pond_box", "Standing at the box offers it as the interaction")
	check(Lang.text(progression.prompt("pond_box")).contains("supply box"), "Box prompt names it")
	var refused: String = progression.transact(player, "pond_box", "find", "")
	check(int(progression.team.get("find_pond_box", 0)) == 0 and Lang.text(refused).contains("Mara"), "Box stays shut without Mara's quest", refused)
	d.accepted["pond_cache"] = true
	var found: String = progression.transact(player, "pond_box", "find", "")
	check(int(progression.team.get("find_pond_box", 0)) == 1 and not progression.finds.pond_box.node.visible, "Opening the box records the goal and hides it", found)
	check(progression.goal_value("find_pond_box") == 1 and progression.complete("pond_cache", 1), "Pond quest completes on the goal")
	check(progression.nearest(player) != "pond_box", "An opened box is no longer offered")
	# the mushroom blurs the view for a while
	d.claimed["pond_cache"] = true
	d.accepted["trip_mushroom"] = true
	player.global_position = shroom_pos + Vector3(1.4, 0.1, 0)
	await physics_frame
	await physics_frame
	check(progression.nearest(player) == "trip_mushroom", "Standing at the mushroom offers it")
	progression.transact(player, "trip_mushroom", "find", "")
	check(game.hud.tripping() and game.hud.trip_rect.visible, "Eating the strange mushroom starts the hallucination")
	game.hud._update_trip(4.0)
	check(float(game.hud._trip_material.get_shader_parameter("strength")) > 0.5, "The view swims at full strength mid-trip")
	if capture:
		player.global_position = shroom_pos + Vector3(2.5, 0.1, 0)
		player.rotation.y = PI * 0.5
		player.camera.rotation.x = -0.3
		await screenshot("trip")
		game.hud._update_trip(60.0)
		player.global_position = shroom_pos + Vector3(2.5, 0.1, 0)
		await screenshot("mushroom")
	game.hud._update_trip(60.0)
	check(not game.hud.tripping() and not game.hud.trip_rect.visible, "The hallucination fades out again")
	check(progression.complete("trip_mushroom", 1), "Mushroom quest completes")
	# the crate in the maize
	d.claimed["trip_mushroom"] = true
	d.accepted["maze_crate"] = true
	player.global_position = crate_pos + Vector3(1.2, 0.1, 0)
	await physics_frame
	await physics_frame
	check(progression.nearest(player) == "maze_crate", "Standing at the crate offers it")
	progression.transact(player, "maze_crate", "find", "")
	check(progression.complete("maze_crate", 1), "Maize quest completes")
	var snap: Dictionary = progression.snapshot()
	check(snap.has("finds") and snap.finds.size() == 3, "Co-op snapshot carries the finds")

	# the flashlight comes on at 19:00, once per night
	player.flashlight.visible = false
	game.day_night.clock_seconds = 19.2 * 3600.0
	game._auto_flashlight()
	check(player.flashlight.visible and Lang.text(game.hud.msg_label.text).contains("Flashlight"), "Flashlight switches on at 19:00 with the F hint")
	player.flashlight.visible = false
	game._auto_flashlight()
	check(not player.flashlight.visible, "The player may switch it off again for the rest of the night")
	game.day_night.clock_seconds = 10.0 * 3600.0
	game._auto_flashlight()
	game.day_night.clock_seconds = 19.5 * 3600.0
	game._auto_flashlight()
	check(player.flashlight.visible, "The next evening switches it on again")

	# a swing blocked by the palisade damages the nearest gate and the HUD points there
	var ring: Perimeter = game.perimeter
	var gate: Barricade = game.barricades[1]
	for b in game.barricades: b.build()
	await physics_frame
	await physics_frame
	var wall: Array = ring.walls[0]
	var best_d := 0.0
	for w in ring.walls:
		var mid: Vector2 = ((w[0] as Vector2) + (w[1] as Vector2)) * 0.5
		var dist_gate := mid.distance_to(Vector2(gate.center.x, gate.center.z))
		var far_from_all := true
		for b in game.barricades:
			if mid.distance_to(Vector2(b.center.x, b.center.z)) < 6.0: far_from_all = false
		if far_from_all and (w[0] as Vector2).distance_to(w[1]) > 4.0 and dist_gate > best_d and dist_gate < 60.0:
			best_d = dist_gate
			wall = w
	var a: Vector2 = wall[0]
	var b2: Vector2 = wall[1]
	var mid2 := (a + b2) * 0.5
	var inward := ring.inside_normal(a, b2)
	player.global_position = Map.ground_pos(mid2.x + inward.x * 1.2, mid2.y + inward.y * 1.2) + Vector3.UP * 0.1
	var spawn := mid2 - inward * 1.5
	check(game.spawn_zombie("shambler", spawn, 1.0, ""), "Zombie spawns outside the palisade")
	var z: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	z.global_position = Map.ground_pos(spawn.x, spawn.y) + Vector3.UP * 0.1
	await physics_frame
	await physics_frame
	var nearest: Barricade = null
	var nd := INF
	for b in game.barricades:
		if b.level > 0 and b.distance_to_line(z.global_position) < nd:
			nd = b.distance_to_line(z.global_position)
			nearest = b
	check(not z._can_hit(null) and z._blocked_by_wall, "The palisade blocks the swing at the player behind it")
	var before: float = nearest.hp
	z._hit_palisade(20.0)
	check(is_equal_approx(nearest.hp, before - 20.0 * Zombie.WALL_HIT_SHARE * (1.0 - float(Barricade.tier(nearest.level)["armor"]))), "The nearest gate takes its share of the wall hit", "%s -> %s" % [before, nearest.hp])
	check(nearest.under_attack(), "The wall hit raises the gate's attack alert")
	game.hud._update_attack_dirs(0.016)
	check(game.hud._attack_arrows.size() >= 1 and Lang.text(game.hud._attack_arrows[0][1]) == Lang.text(nearest.slot["name"]), "The HUD draws a red arrow with the gate's name")
	if capture:
		nearest.update_attack_alert(30.0, false)
		for other in game.barricades:
			if other != nearest: other.update_attack_alert(30.0, false)
		await screenshot("attack-arrows")
		for other in game.barricades: other.update_attack_alert(0.0, false)
	nearest.update_attack_alert(0.0, false)
	game.hud._update_attack_dirs(0.016)
	check(game.hud._attack_arrows.is_empty(), "The arrow disappears once the attack stops")

	# a lethal headshot bursts the head
	z.last_headshot = true
	z.die(Vector3.FORWARD)
	await process_frame
	await process_frame
	var rig := z.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var head := rig.find_bone("Head") if rig else -1
	check(z._head_popped and head >= 0, "Headshot kill marks the head as burst")
	var head_scale: Vector3 = rig.get_bone_global_pose(head).basis.get_scale() if head >= 0 else Vector3.ONE
	check(head >= 0 and head_scale.x < 0.01, "The head bone collapses after the animation update", "global %s pose %s" % [head_scale, rig.get_bone_pose_scale(head) if head >= 0 else Vector3.ONE])
	if capture:
		var look := z.global_position + Vector3.UP * 1.0
		player.global_position = z.global_position + Vector3(inward.x, 0.0, inward.y) * -2.6 + Vector3.UP * 0.1
		player.rotation.y = atan2(-(look.x - player.global_position.x), -(look.z - player.global_position.z))
		player.camera.rotation.x = -0.25
		await create_timer(0.8, false).timeout
		await screenshot("headshot")
	game.spawn_zombie("shambler", spawn + Vector2(2, 0), 1.0, "")
	var z2: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	z2.last_headshot = false
	z2.die(Vector3.FORWARD)
	check(not z2._head_popped, "A body shot keeps the head")

	print("FOREST_FINDS_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
