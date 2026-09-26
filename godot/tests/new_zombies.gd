# The special infected (26 Sep 2026): the spitter's acid, the screamer's call and mark, the stalker's
# cloak in the flashlight, the farm dog and the zombie stag as rig-less beasts, the helmet of the
# armored mutation, their place in the wave plan and their spawns out of the maize.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=new_zombies --smoke-test --no-intro --no-music --no-foliage
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

func last_zombie() -> Zombie:
	var found: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie and z.alive: found = z
	return found

func clear_zombies() -> void:
	for z in game.zombies_root.get_children():
		if z is Zombie:
			game.zombies_root.remove_child(z)
			z.queue_free()
	game._alive_count = 0

func wait_seconds(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.day_night.set_process(false)
	var player: Player = game.player
	player.set_physics_process(false)
	# ---- the tables
	for kind in ["spitter", "screamer", "stalker", "zombie_dog", "zombie_stag"]:
		check(Zombie.TYPES.has(kind) and ResourceLoader.exists("res://assets/models/%s.glb" % Zombie.TYPES[kind].model), "%s is a type with its own model" % kind)
	check(ResourceLoader.exists("res://assets/models/zombie_helmet.glb"), "The helmet model exists")
	check(Zombie.is_beast_kind("zombie_dog") and Zombie.is_beast_kind("zombie_stag") and not Zombie.is_beast_kind("spitter"), "Beasts are the dog and the stag")
	check(Zombie.is_stalker_kind("stalker") and Zombie.can_be_armored("shambler") and not Zombie.can_be_armored("stalker") and not Zombie.can_be_armored("titan"), "Kind helpers")
	# ---- the wave plan
	var waves: Waves = game.waves
	check(Waves.dog_count(2) == 0 and Waves.dog_count(3) == 2 and Waves.dog_count(4) == 0 and Waves.dog_count(31) == 5, "Dogs run in from wave 3 on odd waves, up to five")
	check(Waves.stag_count(4) == 0 and Waves.stag_count(5) == 0 and Waves.stag_count(6) == 1 and Waves.stag_count(13) == 2, "The stag crosses the fields from wave 6, never in a boss wave")
	check(Waves.screamer_count(5) == 0 and Waves.screamer_count(6) == 1 and Waves.screamer_count(20) == 3, "Screamers walk in from wave 6")
	check(Waves.armor_chance(9) == 0.0 and absf(Waves.armor_chance(10) - 0.2) < 0.001 and absf(Waves.armor_chance(40) - 0.45) < 0.001, "Helmets from wave 10, up to 45 %%")
	game.day_night.set_time_hours(12.0)
	game.weather.force("clear")
	game.weather.intensity = 0.0
	check(not waves.stalkers_hidden() and waves.stalker_count(6) == 0, "No stalkers on a clear day")
	game.weather.force("fog")
	game.weather.intensity = 1.0
	check(waves.stalkers_hidden() and waves.stalker_count(6) == 3, "Stalkers rise out of the maize in the fog")
	var plan: Array = waves.plan(7)
	var kinds := {}
	for entry in plan: kinds[entry.type] = int(kinds.get(entry.type, 0)) + 1
	check(int(kinds.get("dog", 0)) == 0 and int(kinds.get("zombie_dog", 0)) == 2 and int(kinds.get("screamer", 0)) == 1 and int(kinds.get("zombie_stag", 0)) == 1 and int(kinds.get("stalker", 0)) == 3, "Wave 7 in the fog: 2 dogs, 1 screamer, 1 stag, 3 stalkers (%s)" % str(kinds))
	var corn_entries := 0
	for entry in plan:
		if entry.get("corn", false): corn_entries += 1
	check(corn_entries == 3, "The stalkers are marked for the maize")
	# 6 % of the regular horde: one plan of about thirty can come out empty by chance (about one in
	# seven), ten plans in a row practically never
	var spitters := 0
	for attempt in 10:
		for entry in waves.plan(12):
			if entry.type == "spitter": spitters += 1
	check(spitters > 0, "Spitters take a share of the horde from wave 4 (%d in ten plans of wave 12)" % spitters)
	var early := 0
	for attempt in 10:
		for entry in waves.plan(3):
			if entry.type == "spitter": early += 1
	check(early == 0, "... and none before wave 4")
	for n in [3, 4, 6, 7, 10]:
		check(waves.preview_count(n) == waves.plan(n).size(), "The intermission preview counts wave %d exactly" % n)
	game.weather.force("clear")
	game.weather.intensity = 0.0
	game.weather.release()
	# ---- the maize spawn
	waves.speed_mul = 1.0
	game.weather.force("fog")
	game.weather.intensity = 1.0
	player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.3
	var corn_spawned: bool = waves._try_corn_spawn("stalker")
	var stalker: Zombie = last_zombie()
	check(corn_spawned and stalker != null and stalker.net_kind == "stalker" and game.cornfield.in_corn(Vector2(stalker.global_position.x, stalker.global_position.z)), "A stalker rises inside the standing maize")
	# ---- the stalker's cloak
	if stalker:
		check(stalker.cloak < 0.1 and not stalker.visible_on_map() and stalker._materials.size() > 0 and stalker._materials[0].albedo_color.a < 0.1, "The stalker starts as a shimmer, off the map")
		player.flashlight.visible = false
		stalker._update_cloak(2.0)
		check(stalker.cloak < 0.1, "Without a beam it stays hidden")
		# the flashlight on it: stand 12 m away and look straight at it
		var to: Vector3 = stalker.global_position - player.global_position
		to.y = 0.0
		player.global_position = stalker.global_position - to.normalized() * 12.0 + Vector3.UP * 0.3
		player.rotation.y = atan2(-to.x, -to.z)
		player.pitch = 0.0
		player.head.rotation.x = 0.0
		player.flashlight.visible = true
		await physics_frame
		await physics_frame
		check(stalker._lit_by_flashlight(), "The flashlight beam finds it")
		stalker._update_cloak(0.5)
		stalker._update_cloak(0.5)
		check(stalker.cloak > 0.9 and stalker.visible_on_map() and stalker._materials[0].albedo_color.a > 0.9, "In the beam it is fully visible (%.2f)" % stalker.cloak)
		player.rotation.y += PI
		await physics_frame
		check(not stalker._lit_by_flashlight(), "Turned away, the beam misses it")
		stalker._update_cloak(1.0)
		stalker._update_cloak(1.0)
		check(stalker.cloak < 0.5, "... and it fades again (%.2f)" % stalker.cloak)
		stalker.die(Vector3.FORWARD)
		stalker._update_cloak(1.0)
		check(stalker.cloak > 0.9, "A dead stalker is plain to see")
	player.flashlight.visible = false
	clear_zombies()
	game.weather.force("clear")
	game.weather.release()
	# ---- the armored mutation
	var open := Vector2(40, 108)
	check(game.spawn_zombie("shambler", open, 1.0, "", 0.0, 1), "An armored shambler spawns")
	var armored: Zombie = last_zombie()
	check(armored != null and armored.armored and armored.helmet_hp == Zombie.HELMET_HP and armored._helmet != null and armored._helmet.get_child_count() == 1, "It wears a helmet on its head bone")
	var body_share: float = armored.hit_helmet(30.0, Vector3.FORWARD)
	check(absf(body_share - 30.0 * Zombie.HELMET_SHARE) < 0.001 and absf(armored.helmet_hp - (Zombie.HELMET_HP - 30.0)) < 0.001, "A headshot rings off the helmet, a fifth reaches the body")
	armored.hit_helmet(100.0, Vector3.FORWARD)
	check(armored.helmet_hp == 0.0 and armored._helmet == null and armored._helmet_gone, "The last hit knocks the helmet off")
	var chunk := false
	for child in game.zombies_root.get_children():
		if child is RigidBody3D: chunk = true
	check(chunk, "The helmet tumbles away as a chunk")
	check(armored.hit_helmet(10.0, Vector3.FORWARD) == 10.0, "Without a helmet the head takes the full round")
	var replica := Zombie.new()
	replica.replica = true
	replica.setup("shambler", player, [], 1.0, Callable())
	game.zombies_root.add_child(replica)
	replica.apply_helmet(Zombie.HELMET_HP, true)
	check(replica.armored and replica._helmet != null, "A replica builds the host's helmet from the snapshot")
	replica.apply_helmet(0.0, true)
	check(replica._helmet == null and replica._helmet_gone, "... and drops it when the host says so")
	var snapshot: Dictionary = NetSession.world.snapshot()
	var entry: Array = snapshot.zombies.values()[0]
	check(entry.size() == 17, "Zombie snapshots carry the helmet fields")
	clear_zombies()
	# ---- the beasts: fit, gallop, the stag's charge, the dog's bite
	check(game.spawn_zombie("zombie_stag", open, 1.0), "A zombie stag spawns")
	var stag: Zombie = last_zombie()
	check(stag is ZombieBeast and stag.model != null and stag.anim == null, "The stag is a rig-less beast")
	if stag:
		var bounds := Barricade._bounds(stag.model)
		check(absf(bounds.size.y - stag.height) < stag.height * 0.2 and absf(bounds.position.y) < 0.25, "The stag stands %.2f m tall on the ground (bounds %.2f)" % [stag.height, bounds.size.y])
		stag._anim_last_pos = stag.global_position
		stag.global_position += Vector3(0.1, 0, 0)
		stag._update_animation(1.0 / 60.0)
		check(stag._ground_speed > 0.0, "The gallop follows the real displacement")
		var far: Vector3 = stag.global_position + Vector3(0, 0, -16.0)
		player.global_position = Map.ground_pos(far.x, far.z) + Vector3.UP * 0.3
		var t := 0.0
		while t < 10.0 and stag.charges == 0:
			await process_frame
			t += root.get_process_delta_time() if root else 1.0 / 60.0
		check(stag.charges >= 1, "The stag charges a player in the open (after %.1f s)" % t)
		var hp_before: float = player.hp
		t = 0.0
		while t < 8.0 and stag.rams == 0 and player.hp >= hp_before:
			await process_frame
			t += root.get_process_delta_time() if root else 1.0 / 60.0
		check(stag.rams >= 1 or player.hp < hp_before, "The charge rams the player (rams %d, hp %.0f)" % [stag.rams, player.hp])
		stag.die(Vector3.FORWARD)
		await process_frame
		check(not stag.alive and stag._fallen, "A dead beast falls onto its side")
	player.hp = player.max_hp
	player.downed = false
	clear_zombies()
	player.global_position = Map.ground_pos(open.x, open.y) + Vector3.UP * 0.3
	check(game.spawn_zombie("zombie_dog", open + Vector2(0, -4), 1.0), "A farm dog spawns")
	var dog: Zombie = last_zombie()
	check(dog is ZombieBeast and dog.height < 1.0, "The dog is a small beast")
	var hp_before_dog: float = player.hp
	var td := 0.0
	while td < 8.0 and player.hp >= hp_before_dog:
		await process_frame
		td += root.get_process_delta_time() if root else 1.0 / 60.0
	check(player.hp < hp_before_dog, "The dog bites (hp %.0f after %.1f s)" % [player.hp, td])
	player.hp = player.max_hp
	player.downed = false
	clear_zombies()
	# ---- the spitter: acid on a gate
	var gate: Barricade = game.barricades[1]
	gate.build()
	var outside: Vector2 = Vector2(gate.center.x, gate.center.z) - gate.normal2 * 10.0
	if game.perimeter.contains(outside): outside = Vector2(gate.center.x, gate.center.z) + gate.normal2 * 10.0
	player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.3
	check(game.spawn_zombie("spitter", outside, 1.0, "east"), "A spitter stands ten metres from a gate")
	var spitter: Zombie = last_zombie()
	var gate_hp: float = gate.hp
	var pool: AcidPool = null
	var ts := 0.0
	while ts < 12.0 and pool == null:
		await process_frame
		ts += root.get_process_delta_time() if root else 1.0 / 60.0
		for child in game.get_children():
			if child is AcidPool: pool = child
	check(spitter != null and pool != null, "The spitter lobs a glob that lands as an acid pool (after %.1f s)" % ts)
	await wait_seconds(2.0)
	check(gate.hp < gate_hp, "The acid eats the gate (%.0f -> %.0f)" % [gate_hp, gate.hp])
	check(pool == null or pool.structure_dealt > 0.0, "The pool reports its structure damage")
	clear_zombies()
	for child in game.get_children():
		if child is AcidPool or child is AcidGlob: child.queue_free()
	# ---- the screamer: the call, the mark, the reinforcements
	waves.phase = "spawning"
	waves.queue.clear()
	waves.total = 0
	player.global_position = Map.ground_pos(open.x, open.y) + Vector3.UP * 0.3
	check(game.spawn_zombie("screamer", open + Vector2(0, -14), 1.0), "A screamer sees the player from 14 m")
	var screamer: Zombie = last_zombie()
	var tc := 0.0
	while tc < 6.0 and (screamer == null or screamer.calls == 0):
		await process_frame
		tc += root.get_process_delta_time() if root else 1.0 / 60.0
	check(screamer != null and screamer.calls == 1 and screamer.state == "scream", "The screamer stops and cries out (after %.1f s)" % tc)
	check(player.marked_t > 0.0 and game.marked_player() == player, "The player is marked for the horde")
	check(waves.queue.size() == 3 and waves.total == 3 and waves.queue[0].type == "runner" and waves.queue[0].get("called", false), "Three runners join the wave from the nearest lane")
	check(Lang.text(game.hud.msg_label.text).begins_with("A screamer's cry"), "The cry is announced")
	check(game.pings.active.size() > 0 and game.pings.active.back().kind == "spotted", "The radio calls the mark")
	game._process(0.1)
	check(game.hud.marked_label.visible, "The HUD shows the mark")
	player.marked_t = 0.0
	game._process(0.1)
	check(not game.hud.marked_label.visible and game.marked_player() == null, "The mark fades")
	waves.queue.clear()
	waves.phase = "idle"
	clear_zombies()
	print("NEW_ZOMBIES_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
