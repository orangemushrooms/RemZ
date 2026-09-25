# Titan phases (26 Sep 2026): the arm lost at 65 % (bones collapse, a stump), the trees it throws from
# then on, the leg lost at 35 % and the crawl (the rig's own crawl clip on hands and knees, the contact
# bones on the ground - no tilted, sunken model), and the replica that mirrors both from the boss state.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=titan_phases --smoke-test --no-intro --no-music --no-foliage
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

func bone_scale(titan: Zombie, bone_name: String) -> Vector3:
	var rig := titan.model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig: return Vector3.ONE
	var bone := rig.find_bone(bone_name)
	return rig.get_bone_pose_scale(bone) if bone >= 0 else Vector3.ONE

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.waves.wave = 6
	var player: Player = game.player
	player.set_physics_process(false)
	var field := Vector2(10, 126)
	player.global_position = Map.ground_pos(field.x + 40.0, field.y) + Vector3.UP * 0.3
	check(game.spawn_zombie("titan", field, 1.0, "east"), "A field titan rises on the meadow")
	var titan: Titan = null
	for z in game.zombies_root.get_children():
		if z is Titan: titan = z
	check(titan != null and titan.lost == 0 and not titan.crawling, "It starts whole")
	if titan == null:
		quit(1)
		return
	var full_radius: float = titan.blast_radius()
	var full_windup: float = titan.windup()
	# ---- the arm
	titan.hp = titan.max_hp * 0.64
	titan.damage(1.0, Vector3(1, 0, 0))
	check(titan.lost & Titan.LOST_ARM and not (titan.lost & Titan.LOST_LEG), "Below 65 %% the right arm comes off")
	check(bone_scale(titan, "RightArm").x < 0.01 and bone_scale(titan, "RightHand").x < 0.01, "The arm's bones collapse")
	var rig := titan.model.find_child("Skeleton3D", true, false) as Skeleton3D
	check(rig.get_node_or_null("Stump_right_arm") != null, "A stump hangs on the shoulder")
	check(Lang.text(game.hud.msg_label.text).contains("lost an arm"), "The arm loss is announced")
	check(titan._throw_t <= 3.5, "The first tree comes soon")
	# ---- the throw
	titan._throw_t = 0.0
	var t := 0.0
	while t < 8.0 and titan.strike_phase != "throw":
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	check(titan.strike_phase == "throw", "The titan winds up a throw at a player 40 m away (after %.1f s)" % t)
	t = 0.0
	while t < 4.0 and titan.throws == 0:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	var tree: ThrownTree = null
	for child in game.get_children():
		if child is ThrownTree: tree = child
	check(titan.throws == 1 and titan.throw_serial == 1 and tree != null, "A tree leaves its hand")
	check(tree != null and tree.to.distance_to(player.global_position) < 6.0 and tree.from.y > titan.global_position.y + titan.height * 0.5, "The tree flies from the hand towards the player")
	var hp_before: float = player.hp
	t = 0.0
	while t < 6.0 and tree != null and not tree.landed:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	check(tree != null and tree.landed, "The tree lands (after %.1f s)" % t)
	check(player.hp < hp_before or player.downed, "The impact hurts the player under it (%.0f -> %.0f)" % [hp_before, player.hp])
	player.downed = false
	player.hp = player.max_hp
	check(titan.strike_phase == "recovery" or titan.strike_phase == "walk", "The titan recovers after the throw")
	# a gate under the impact
	var gate: Barricade = game.barricades[1]
	gate.build()
	var gate_hp: float = gate.hp
	var second := ThrownTree.new()
	game.add_child(second)
	second.setup(titan.global_position + Vector3.UP * 20.0, gate.center, 0.7, titan, false)
	await create_timer(1.2).timeout
	check(second.landed and gate.hp < gate_hp, "A tree on a gate crushes it (%.0f -> %.0f)" % [gate_hp, gate.hp])
	# ---- the leg
	titan.strike_phase = "walk"
	titan.play("walk")
	titan.hp = titan.max_hp * 0.34
	titan.damage(1.0, Vector3(1, 0, 0))
	check(titan.lost & Titan.LOST_LEG and titan.crawling, "Below 35 %% the left leg comes off and the titan crawls")
	check(bone_scale(titan, "LeftLeg").x < 0.01 and rig.get_node_or_null("Stump_left_leg") != null, "The leg's bones collapse into a stump")
	check(titan.has_crawl_clip() and titan.crawl_bones.size() >= 5, "The rig carries the crawl clip and knows its hands and knees")
	# the loss comes with a rage roar (the scream clip roots the giant for its length); the crawl follows it
	t = 0.0
	while t < 6.0 and titan.clip != "crawl":
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	check(titan.clip == "crawl" and titan.anim.current_animation == "crawl", "It plays the crawl on hands and knees after the roar (clip %s after %.1f s)" % [titan.clip, t])
	check(absf(titan.model.rotation.x) < 0.001, "The model is not tilted into the ground")
	check(titan.anim.get_animation("crawl").loop_mode == Animation.LOOP_LINEAR, "The crawl loops like a gait")
	t = 0.0
	while t < 1.6:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	var lowest := INF
	for index in titan.crawl_bones:
		var joint: Vector3 = rig.to_global(rig.get_bone_global_pose(index).origin)
		lowest = minf(lowest, joint.y - Map.ground_height(joint.x, joint.z))
	check(lowest > -0.4 and lowest < 1.2, "Hands and knees rest on the terrain (lowest contact %.2f m above it)" % lowest)
	check(titan.blast_radius() < full_radius and titan.windup() < full_windup, "The slam becomes a shorter, quicker sweep")
	check(Lang.text(game.hud.msg_label.text).contains("lost a leg"), "The leg loss is announced")
	# ---- the replica mirrors the boss state
	var state: Array = titan.boss_state()
	check(state.size() == 6 and int(state[4]) == (Titan.LOST_ARM | Titan.LOST_LEG) and int(state[5]) == 1, "The boss state carries the lost limbs and the throw count")
	var replica := Titan.new()
	replica.replica = true
	replica.setup("titan", player, [], 1.0, Callable())
	replica.model_path = titan.model_path
	replica.appearance_seed = titan.appearance_seed
	replica.height = titan.height
	game.zombies_root.add_child(replica)
	replica.global_position = titan.global_position + Vector3(30, 0, 0)
	replica.apply_boss_state(state, true)
	check(replica.lost == titan.lost and replica.crawling, "A replica loses the same limbs and crawls")
	check(bone_scale(replica, "RightArm").x < 0.01 and bone_scale(replica, "LeftLeg").x < 0.01, "... with the same collapsed bones")
	print("TITAN_PHASES_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
