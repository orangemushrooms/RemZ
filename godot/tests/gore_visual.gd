# Windowed look at the deaths and the dismemberment (25 Sep 2026):
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=gore_visual --smoke-test --no-intro --no-music
# Five bodies stand on the meadow in daylight, the camera looks at them from the side: a front shot, a shot
# from behind, a headshot, an arm shot off (alive, walking on), a leg shot off. Frames go to
# artifacts/gore/<label>-<t>.png at several moments of the fall, plus a filmstrip per body.
extends SceneTree

var game: Node
var frames := {}

func _initialize() -> void:
	call_deferred("run")

func shot(label: String) -> void:
	for i in 2: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/gore")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))
	print("GORE_SHOT ", label)

# the camera 'distance' metres from 'at', at eye height 'eye', looking at 'at'
func aim(player: Player, at: Vector3, distance: float, eye: float, side := 0.0) -> void:
	var from := at + Vector3(side, 0.0, distance)
	player.global_position = Map.ground_pos(from.x, from.z) + Vector3.UP * 0.1
	var cam_pos := player.global_position + Vector3.UP * Player.EYE
	var to := at - cam_pos
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = clampf(atan2(to.y + eye - Player.EYE, Vector2(to.x, to.z).length()), -1.3, 1.3)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.day_night.set_time_hours(14.0)
	var player: Player = game.player
	player.set_physics_process(false)
	Zombie.force_skin = "zombie_shambler"
	# a row on the meadow south of the fork, the camera 7 m in front of it looking north
	var base := Vector2(20.0, 75.0)
	var kinds := ["front", "behind", "headshot", "arm", "leg"]
	var bodies: Array[Zombie] = []
	for i in kinds.size():
		var at := base + Vector2(i * 2.4 - 4.8, 0)
		game.spawn_zombie("shambler", at, 1.0, "", 0.0)
		var z: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
		z.global_position = Map.ground_pos(at.x, at.y) + Vector3.UP * 0.1
		z.rotation.y = PI       # facing the camera (south), the rig's front is +Z after the yaw
		z.set_physics_process(false)
		bodies.append(z)
	player.global_position = Map.ground_pos(base.x, base.y + 7.5) + Vector3.UP * 0.1
	player.rotation.y = 0.0
	player.camera.rotation.x = -0.12
	await create_timer(0.8, false).timeout
	for z in bodies:
		z.set_physics_process(true)
		z.play("idle")
	await create_timer(0.3, false).timeout
	await shot("00-lineup")
	var toward_camera := (player.global_position - bodies[0].global_position)
	toward_camera.y = 0.0
	var from_camera := -toward_camera.normalized()          # the bullet's direction from the player
	# 1 front shot, 2 shot from behind, 3 headshot
	bodies[0].last_hit_bone = "Spine"
	bodies[0].damage(9999.0, from_camera)
	bodies[1].last_hit_bone = "Spine"
	bodies[1].damage(9999.0, -from_camera)
	bodies[2].last_headshot = true
	bodies[2].damage(9999.0, from_camera)
	# 4 the left arm off, still alive; 5 the right leg off
	bodies[3].last_hit_bone = "LeftForeArm"
	bodies[3].damage(bodies[3].max_hp * 0.35, from_camera)
	bodies[4].last_hit_bone = "RightLeg"
	bodies[4].damage(bodies[4].max_hp * 0.35, from_camera)
	for i in bodies.size():
		var local: Vector3 = bodies[i].model.global_basis.inverse() * from_camera
		print("GORE_DIR ", kinds[i], " local_z=%.2f" % local.z, " clip=", bodies[i].clip, " travel_z=", Zombie.clip_info(bodies[i].model_path).get(bodies[i].clip, {}).get("travel_z", "-"))
	print("GORE_CLIPS front=", bodies[0].clip, " behind=", bodies[1].clip, " headshot=", bodies[2].clip, " leg=", bodies[4].clip, " arm_alive=", bodies[3].alive, " arm_severed=", bodies[3].limb_severed("LeftArm"))
	var elapsed := 0.0
	for t in [0.25, 0.6, 1.0, 1.5, 2.2, 3.2]:
		await create_timer(float(t) - elapsed, false).timeout
		elapsed = float(t)
		await shot("%02d-t%.1f" % [1 + int(elapsed * 10) / 10, elapsed])
	# close-ups: the arm zombie still walking, the stumps, the chunks on the ground, the corpses
	aim(player, bodies[3].global_position + Vector3.UP * 1.1, 2.6, 1.3)
	await shot("10-arm-alive-front")
	aim(player, bodies[3].global_position + Vector3.UP * 1.1, 2.4, 1.3, 2.0)
	await shot("11-arm-alive-side")
	aim(player, bodies[4].global_position + Vector3.UP * 0.3, 2.8, 1.0)
	await shot("12-leg-corpse")
	aim(player, bodies[2].global_position + Vector3.UP * 0.3, 2.6, 1.0)
	await shot("13-headshot-corpse")
	aim(player, bodies[0].global_position + Vector3.UP * 0.3, 3.0, 1.2)
	await shot("14-front-corpse")
	aim(player, bodies[1].global_position + Vector3.UP * 0.3, 3.0, 1.2)
	await shot("15-behind-corpse")
	var chunk_count := 0
	for node in game.zombies_root.get_children():
		if node is RigidBody3D and node.name.begins_with("Chunk_"):
			chunk_count += 1
			if chunk_count == 1:
				aim(player, node.global_position, 1.6, 0.6)
				await shot("16-chunk")
	print("GORE_CHUNKS ", chunk_count)
	print("GORE_VISUAL_DONE")
	quit(0)
