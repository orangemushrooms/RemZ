extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player := Player.new()
	scene.add_child(player)
	player.active = true
	player.global_position = Vector3(2, 0, 0)
	player._motion_from = Vector3(1, 0, 0)
	player._motion_to = player.global_position
	player._motion_ready = true
	for i in 5:
		player._update_camera_motion(i / 4.0)
		check(is_equal_approx(player.camera.global_position.x, 1.0 + i / 4.0), "Camera advances evenly between physics ticks: %d" % i)
	var eye := player.camera.global_position
	player.rotation.y += 0.5
	player._update_camera_motion(1.0)
	check(player.camera.global_position.is_equal_approx(eye), "Mouse look does not orbit a stale camera offset")
	check(is_equal_approx(angle_difference(player.camera.global_rotation.y, player.rotation.y), 0), "Mouse rotation remains immediate")
	player.global_position = Vector3(80, 4, -30)
	player._update_camera_motion(0.2)
	check(player.camera.global_position.is_equal_approx(player.global_position + Vector3.UP * Player.EYE), "Teleport snaps instead of interpolating through geometry")
	player._motion_from = player.global_position - Vector3.RIGHT
	player._motion_to = player.global_position
	player._motion_ready = true
	player._update_camera_motion(0.25)
	player.active = false
	player._update_camera_motion(0.75)
	check(player.camera.position.is_zero_approx(), "Inactive player restores the exact camera transform")
	player.set_physics_process(false)
	Sfx.prewarm()
	var voices := Node3D.new()
	scene.add_child(voices)
	for i in 80: Sfx.play_at(voices, "hit", Vector3.ZERO, -80)
	check(voices.get_child_count() == Sfx.MAX_VOICES, "Simultaneous hits allocate only the bounded voice pool")
	var ids: Array = []
	for voice in voices.get_children(): ids.append(voice.get_instance_id())
	await process_frame
	await process_frame
	for i in 80: Sfx.play_at(voices, "hit", Vector3.ONE, -80)
	check(voices.get_children().all(func(voice: Node): return voice.get_instance_id() in ids), "Further hits reuse the same audio nodes")
	var owner := Node3D.new()
	scene.add_child(owner)
	await process_frame
	await process_frame
	Sfx.play_at(owner, "hit", Vector3(3, 4, 5), -80)
	check(owner.get_child_count() == 1 and owner.get_child(0).global_position == Vector3(3, 4, 5), "A reused voice follows its new owner and world position")
	var cache_size := Sfx._cache.size()
	for surface: String in Sfx.STEP_SURFACES:
		for variant in 3: Sfx._step_texture(surface, variant)
	check(Sfx._cache.size() == cache_size, "Every footstep texture is prepared before play")
	var effects = preload("res://scripts/elemental_effects.gd")
	var tracer = effects.Tracer.new()
	tracer.mesh = effects.tracer_mesh()
	scene.add_child(tracer)
	tracer.start = Vector3(2, 1, 3)
	tracer.endpoint = Vector3(-5, 6, -10)
	tracer.align()
	check((tracer.global_transform * Vector3(0, -0.5, 0)).is_equal_approx(tracer.start), "Shared tracer geometry starts at the muzzle")
	check((tracer.global_transform * Vector3(0, 0.5, 0)).is_equal_approx(tracer.endpoint), "Shared tracer geometry ends at the impact")
	var mesh: Mesh = tracer.mesh
	tracer.endpoint += Vector3(1, 2, 4)
	tracer.align()
	check(tracer.mesh == mesh and is_equal_approx(mesh.height, 1.0), "Moving tracers never rebuild their mesh")
	var achievements := Achievements.new()
	achievements._save_path = "user://frame-pacing-save-test.json"
	scene.add_child(achievements)
	achievements.unlocked["first"] = true
	achievements._save()
	achievements.unlocked["latest"] = true
	achievements._save()
	while achievements._save_task != -1 or achievements._save_pending:
		achievements._poll_save()
		await process_frame
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(achievements._save_path))
	check(saved.unlocked.has("first") and saved.unlocked.has("latest"), "Overlapping background saves retain the latest unlocks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(achievements._save_path))
	achievements.queue_free()
	print("FRAME_PACING_GUARDS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
