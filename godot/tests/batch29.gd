# The user's own Meshy web models (27 Sep 2026, tools/new_zombies.py): five new skins with full library clip
# sets, repaired skin weights and baked normal maps, the spawn rise ("arise": forest floor, maize, secret
# night, cheat menu) and the wretched bride who leads every boss wave and wails like a screamer.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=batch29 --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

# skin -> the type that wears it
const SKINS := {"zombie_businessman": "shambler", "zombie_wanderer": "shambler", "zombie_wastelander": "runner",
	"zombie_wraith": "stalker", "zombie_bride": "bride"}
const CLIPS := ["walk", "attack", "attack2", "death", "death2", "death3", "death4", "hit", "hit2", "idle", "scream", "arise"]
const RUNS := ["zombie_wastelander", "zombie_wraith", "zombie_bride"]
const BONES := ["Hips", "Spine", "neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]

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

# lowest foot / toe bone over a clip against the rest pose, in rig metres (the ground check of ground_clips.mjs
# on the bones: a floating clip lifts every foot sample above the rest height)
func foot_gap(scene: PackedScene, clip: String) -> float:
	var model: Node3D = scene.instantiate()
	root.add_child(model)
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var to_model := model.global_transform.affine_inverse() * rig.global_transform
	var bones := ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"].map(func(n): return rig.find_bone(n))
	var rest := INF
	for b in bones: rest = minf(rest, (to_model * rig.get_bone_global_rest(b).origin).y)
	var low := INF
	var length := player.get_animation(clip).length
	player.play(clip)
	for i in 25:
		player.seek(length * i / 24.0, true)
		rig.force_update_all_bone_transforms()
		for b in bones: low = minf(low, (to_model * rig.get_bone_global_pose(b).origin).y)
	player.stop()
	model.queue_free()
	return low - rest

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
	for skin in SKINS:
		var kind: String = SKINS[skin]
		check(ResourceLoader.exists("res://assets/models/%s.glb" % skin), "%s exists" % skin)
		check(Zombie.skin_names(Zombie.TYPES[kind]).has(skin), "%s is a skin of the %s" % [skin, kind])
	check(Zombie.TYPES.bride.model == "zombie_bride" and Zombie.TYPES.bride.has("screamer") and not Zombie.is_boss_kind("bride") and not Zombie.can_be_armored("bride"), "The bride: own model, a screamer's wail, a common body (hit volumes, gore), no helmet")
	# ---- models: rig, clips, budget, materials
	Zombie.preload_models(game)
	for skin in SKINS:
		var path := "res://assets/models/%s.glb" % skin
		var scene: PackedScene = Zombie._scenes.get(path)
		check(scene != null, "%s loads and is prepared" % skin)
		if scene == null: continue
		var model: Node3D = scene.instantiate()
		var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var missing_bones := BONES.filter(func(b): return rig == null or rig.find_bone(b) < 0)
		check(missing_bones.is_empty(), "%s carries the Meshy bone names the game uses (%s missing)" % [skin, str(missing_bones)])
		var wanted: Array = CLIPS.duplicate()
		if skin in RUNS: wanted.append("run")
		var missing_clips := wanted.filter(func(c): return anim == null or not anim.has_animation(c))
		check(missing_clips.is_empty(), "%s has the full clip set with the rise (%s missing)" % [skin, str(missing_clips)])
		var triangles := 0
		var material: StandardMaterial3D = null
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
				if not material: material = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		check(triangles >= 8000 and triangles <= 45000, "%s is a game mesh (%d triangles, the sources had up to 2 M)" % [skin, triangles])
		if skin == "zombie_wanderer":
			check(material != null and material.metallic < 0.05 and not material.emission_enabled, "The wanderer is matte (no ORM map: metallic 0 instead of chrome) and does not glow")
		else:
			check(material != null and material.normal_enabled and material.normal_texture != null and material.albedo_texture != null and material.metallic_texture != null, "%s has base colour, baked normal map and ORM" % skin)
		model.free()
		# measured clips: gaits carry a pace, swings a strike moment, the deaths a direction
		var info := Zombie.clip_info(path)
		check(float(info.get("walk", {}).get("speed", 0.0)) > 0.1, "%s walk has a measured pace (%.2f m/s)" % [skin, float(info.get("walk", {}).get("speed", 0.0))])
		var peak := float(info.get("attack", {}).get("peak", -1.0))
		check(peak > 0.05 and peak < float(info.get("attack", {}).get("length", 0.0)), "%s attack strike measured at %.2f s" % [skin, peak])
		var falls := 0
		for c in info:
			if String(c).begins_with("death") and not Zombie.is_plank(info[c]): falls += 1
		check(falls >= 3, "%s has %d usable falls" % [skin, falls])
		# grounded clips (tools/ground_clips.mjs): the feet reach their rest height in every standing clip
		for clip in ["walk", "idle", "attack"]:
			var gap := foot_gap(scene, clip)
			check(gap < 0.06, "%s %s keeps the feet on the ground (lowest foot %.3f m over rest)" % [skin, clip, gap])
	# ---- the rise
	var waves: Waves = game.waves
	waves.phase = "spawning"
	var open := Vector2(40, 108)
	player.global_position = Map.ground_pos(open.x, open.y) + Vector3.UP * 0.3
	Zombie.force_skin = "zombie_businessman"
	check(game.spawn_zombie("shambler", open + Vector2(0, -20), 1.0, "", 0.0, -1, true), "A businessman spawns rising, 20 m from the player")
	var riser: Zombie = last_zombie()
	check(riser != null and riser.state == "arise" and riser.clip == "arise" and riser.anim.current_animation == "arise", "It enters lying on the ground (state arise, clip arise)")
	var to_player := player.global_position - riser.global_position
	check(absf(angle_difference(riser.rotation.y, atan2(to_player.x, to_player.z))) < 0.2, "It gets up facing its prey")
	await wait_seconds(0.3)
	var start := riser.global_position
	await wait_seconds(0.9)
	check(riser.state == "arise" and Vector2(riser.global_position.x - start.x, riser.global_position.z - start.z).length() < 0.05, "Rooted while it gets up")
	await wait_seconds(1.4)
	check(riser.state != "arise" and riser.alive, "Standing after the clip it walks on (%s)" % riser.state)
	# killed on the ground it sinks back down
	check(game.spawn_zombie("shambler", open + Vector2(4, -20), 1.0, "", 0.0, -1, true), "A second one rises")
	var victim: Zombie = last_zombie()
	await wait_seconds(0.5)
	var position_before: float = victim.anim.current_animation_position
	victim.damage(99999.0, Vector3.FORWARD)
	check(not victim.alive and victim.state == "death" and victim.clip == "arise" and victim.anim.speed_scale < 0.0, "Shot before it stands, the body sinks back (the rise runs backwards)")
	await wait_seconds(0.2)
	check(victim.anim.current_animation_position < position_before, "... towards the lying pose (%.2f -> %.2f s)" % [position_before, victim.anim.current_animation_position])
	# a head turn would twist a body lying face down
	player.global_position = Map.ground_pos(open.x + 8, open.y - 24) + Vector3.UP * 0.3
	check(game.spawn_zombie("shambler", open + Vector2(8, -20), 1.0, "", 0.0, -1, true), "A third one rises 4 m from the player")
	var close: Zombie = last_zombie()
	await wait_seconds(0.6)
	check(close.state == "arise" and (close._head_look == null or close._head_look.influence < 0.05), "No head tracking while it gets up")
	# rigs without the clip spawn standing, as before
	Zombie.force_skin = "zombie_shambler"
	check(game.spawn_zombie("shambler", open + Vector2(-4, -20), 1.0, "", 0.0, -1, true), "An older skin spawns with rise requested")
	check(last_zombie().state == "walk", "... and simply stands (no arise clip)")
	Zombie.force_skin = ""
	clear_zombies()
	# co-op: a replica created while the host raises the body enters lying too
	var replica := Zombie.new()
	replica.replica = true
	Zombie.force_skin = "zombie_wraith"
	replica.setup("stalker", player, game.barricades, 1.0, Callable())
	replica.rise_on_spawn = true
	game.zombies_root.add_child(replica)
	replica.global_position = Map.ground_pos(open.x, open.y - 18)
	check(replica.state == "arise" and replica.clip == "arise", "A co-op replica of a rising body starts lying (snapshot state arise)")
	replica.play("walk")
	check(replica.state == "walk", "... and stands when the host's state moves on")
	Zombie.force_skin = ""
	clear_zombies()
	# ---- hit volumes and gore on every new skin
	for skin in SKINS:
		Zombie.force_skin = skin
		check(game.spawn_zombie(SKINS[skin], open + Vector2(0, -18), 1.0), "%s spawns" % skin)
		var z: Zombie = last_zombie()
		check(z.model_path.ends_with(skin + ".glb"), "%s is the model worn" % skin)
		check(z._shot_volumes.size() >= 12 and z._hitboxes.is_empty(), "%s uses baked shot volumes only (%d volumes, %d fallback areas)" % [skin, z._shot_volumes.size(), z._hitboxes.size()])
		check(z._gore_parts.size() >= 4, "%s can lose head and limbs (%d parts)" % [skin, z._gore_parts.size()])
		clear_zombies()
	Zombie.force_skin = ""
	# ---- the wretched bride
	check(Waves.bride_count(4) == 0 and Waves.bride_count(5) == 1 and Waves.bride_count(7) == 0 and Waves.bride_count(15) == 1 and Waves.bride_count(20) == 2 and Waves.bride_count(40) == 2, "One bride leads every boss wave, two from wave 20")
	for n in [5, 10, 20]:
		var brides := waves.plan(n).filter(func(e): return e.type == "bride")
		check(brides.size() == Waves.bride_count(n) and brides.all(func(e): return e.get("forest", false)), "Wave %d plans %d bride(s), rising in the forest" % [n, brides.size()])
		check(waves.preview_count(n) == waves.plan(n).size(), "The intermission preview counts wave %d exactly" % n)
	check(waves.plan(6).filter(func(e): return e.type == "bride").is_empty(), "No bride outside the boss waves")
	waves.queue.clear()
	waves.total = 0
	player.global_position = Map.ground_pos(open.x, open.y) + Vector3.UP * 0.3
	check(game.spawn_zombie("bride", open + Vector2(0, -14), 1.0), "The bride spawns 14 m from the player")
	var bride: Zombie = last_zombie()
	check(bride.net_kind == "bride" and bride.model_path.ends_with("zombie_bride.glb") and bride.hp >= 950.0, "She wears her own model and %d HP" % int(bride.hp))
	check(Lang.text(game.hud.msg_label.text).begins_with("THE WRETCHED BRIDE"), "Her arrival is announced")
	var tc := 0.0
	while tc < 8.0 and bride.calls == 0:
		await process_frame
		tc += root.get_process_delta_time() if root else 1.0 / 60.0
	check(bride.calls == 1 and bride.state == "scream", "She stops and wails (after %.1f s)" % tc)
	check(player.marked_t > 0.0 and game.marked_player() == player, "The player is marked for the horde")
	check(waves.queue.size() == 4 and waves.queue.all(func(e): return e.type == "runner" and e.get("called", false)), "Four runners answer her call")
	check(Lang.text(game.hud.msg_label.text).begins_with("The wretched bride wails"), "Her wail has its own message")
	player.marked_t = 0.0
	waves.queue.clear()
	waves.phase = "idle"
	clear_zombies()
	# ---- the stalker's maize spawn with the wraith: rising and still cloaked
	game.weather.force("fog")
	game.weather.intensity = 1.0
	player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3.UP * 0.3
	Zombie.force_skin = "zombie_wraith"
	var corn: bool = waves._try_corn_spawn("stalker")
	var wraith: Zombie = last_zombie()
	check(corn and wraith != null and wraith.state == "arise" and wraith.cloak < 0.1, "The wraith rises out of the maize as a shimmer")
	Zombie.force_skin = ""
	game.weather.release()
	clear_zombies()
	print("BATCH29_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
