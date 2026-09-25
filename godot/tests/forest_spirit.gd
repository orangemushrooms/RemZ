# The Forest Spirit boss (added by the second session, 26 Sep 2026; forest_spirit.gd): the locally rigged
# model with its clips and bone-following shot volumes, the hover, the pulse that throws players back,
# the boss state on a replica, its place in the wave plan and the forest spawn, the death.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=forest_spirit --smoke-test --no-intro --no-music --no-foliage
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

func spirit() -> ForestSpirit:
	for z in game.zombies_root.get_children():
		if z is ForestSpirit and z.alive: return z
	return null

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
	# ---- tables and assets
	check(Zombie.TYPES.has("forest_spirit") and Zombie.is_boss_kind("forest_spirit") and not Zombie.is_titan_kind("forest_spirit"), "The Forest Spirit is a boss of its own kind")
	check(ResourceLoader.exists("res://assets/models/zombie_forest_spirit.glb"), "Its model exists")
	var scene: PackedScene = load("res://assets/models/zombie_forest_spirit.glb")
	var probe: Node3D = scene.instantiate()
	var anim := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips: Array = Array(anim.get_animation_list()) if anim else []
	check(anim != null and clips.has("walk") and clips.has("attack") and clips.has("pulse") and clips.has("death") and clips.has("idle"), "The local rig carries walk, attack, pulse, death and idle clips (%s)" % str(clips))
	var triangles := 0
	for mesh: MeshInstance3D in probe.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	check(triangles > 50000 and triangles < 260000, "The reduced mesh stays in budget (%d triangles)" % triangles)
	probe.free()
	# ---- the wave plan and the forest spawn
	var planned := 0
	for attempt in 60:
		for entry in game.waves.plan(14):
			if entry.type == "forest_spirit": planned += 1
	check(planned > 0, "Lesser-titan waves sometimes bring the Forest Spirit (%d of 60 plans)" % planned)
	check(planned < 60, "... but not every time")
	game.waves.wave = 14
	game.waves.speed_mul = 1.0
	player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.3
	var spawned: bool = game.waves._try_spawn({"type": "forest_spirit", "lane": "north", "forest": true})
	var boss := spirit()
	check(spawned and boss != null, "The spirit enters from a lane like a titan")
	check(Lang.text(game.hud.msg_label.text).begins_with("THE FOREST SPIRIT"), "Its arrival is announced")
	if boss:
		check(absf(boss.height - 3.4) < 0.01 and boss.max_hp > 1650.0 * 0.9, "It stands 3.4 m tall with a boss's health (%.0f)" % boss.max_hp)
		check(boss._hitboxes.size() == 5 and boss.collision_layer & Zombie.HITBOX_LAYER, "Five bone volumes plus the capsule take the shots")
		var head := false
		for area in boss._hitboxes:
			if area.get_meta("headshot", false): head = true
		check(head, "The head volume counts as a headshot")
		check(boss.anim != null and boss.state == "walk", "It walks its rig")
		check(boss._pulse_ring != null and not boss._pulse_ring.visible, "The pulse ring waits hidden")
		boss.queue_free()
		await process_frame
	# ---- the pulse: close to a player it winds up and throws them back
	player.global_position = Map.ground_pos(40, 108) + Vector3.UP * 0.3
	check(game.spawn_zombie("forest_spirit", Vector2(40, 102), 1.0), "A spirit stands six metres from the player")
	boss = spirit()
	var t := 0.0
	while t < 8.0 and boss and boss._pulse_t <= 0.0:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
		# the pulse wants 3.5 to 10 m: keep the player six metres ahead of the gliding spirit
		if boss:
			var away: Vector3 = player.global_position - boss.global_position
			away.y = 0.0
			if away.length() < 5.0:
				var kept: Vector3 = boss.global_position + away.normalized() * 6.0
				player.global_position = Map.ground_pos(kept.x, kept.z) + Vector3.UP * 0.3
	await physics_frame
	await physics_frame
	check(boss != null and boss._pulse_t > 0.0 and boss._pulse_ring.visible and boss.state == "pulse", "It winds up a pulse within reach (after %.1f s)" % t)
	var hp_before: float = player.hp
	t = 0.0
	while t < 4.0 and boss and boss._pulse_serial == 0:
		await process_frame
		t += root.get_process_delta_time() if root else 1.0 / 60.0
	check(boss != null and boss._pulse_serial == 1 and boss._pulse_cool > 5.0, "The pulse fires and goes on cooldown")
	check(player.hp < hp_before or player.downed, "The pulse hurts the player (%.0f -> %.0f)" % [hp_before, player.hp])
	check(player._shove.length() > 0.0 or player.wobble > 0.0, "... and throws them back")
	player.downed = false
	player.hp = player.max_hp
	# ---- boss state on a replica, the snapshot
	var state: Array = boss.boss_state()
	check(state.size() == 2 and int(state[1]) == 1, "The boss state carries the pulse serial")
	var snapshot: Dictionary = NetSession.world.snapshot()
	var carried := false
	for entry in snapshot.zombies.values():
		if entry[0] == "forest_spirit" and entry[8] is Array and entry[8].size() == 2: carried = true
	check(carried, "The co-op snapshot carries its boss state")
	var replica := ForestSpirit.new()
	replica.replica = true
	replica.setup("forest_spirit", player, [], 1.0, Callable())
	game.zombies_root.add_child(replica)
	replica.apply_boss_state([0.7, 3], true)
	check(absf(replica._pulse_t - 0.7) < 0.001 and replica._pulse_serial == 3, "A replica mirrors the pulse")
	replica.queue_free()
	# ---- damage and death
	var before: float = boss.hp
	boss.damage(100.0, Vector3.FORWARD)
	check(boss.hp == before - 100.0 and boss._stagger == 0.0, "It takes damage without being knocked around")
	boss.die(Vector3.FORWARD)
	await process_frame
	check(not boss.alive and boss.state == "death" and not boss._pulse_ring.visible, "It dies with its clip and hides the ring")
	print("FOREST_SPIRIT_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
