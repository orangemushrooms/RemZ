extends SceneTree

var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var render := false
var folder := ProjectSettings.globalize_path("res://../artifacts/tower-effects/")

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func shot(name: String) -> void:
	if not render: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + name + ".png")

func run() -> void:
	render = "--render-towers" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(folder)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	game.day_night.set_process(false)
	game.day_night.set_time_hours(12)
	var defence: DefenceSystem = game.defences
	var origin := Map.ground_pos(60, 112)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.make_current()
	game.player.global_position = origin + Vector3(0, 0, 3)
	for kind in DefenceTower.TYPES:
		var tower: DefenceTower = defence.create_tower(origin, 1, 0, false, kind)
		tower.set_physics_process(false)
		if kind == "mortar": tower.gun.rotation.x = 0.8
		var start := tower.muzzle.global_position
		var seat := tower.seat_position()
		var aim := start + Vector3(0, -0.6, -1).normalized() * tower.attack_range()
		camera.global_position = origin + Vector3(5, 5, 5)
		camera.look_at(origin + Vector3(0, 2.9, -6))
		tower.fire_at(aim)
		var audio: Node3D = tower.shot_audio
		check(audio.voice.playing and audio.voice.stream is AudioStreamWAV, kind + " plays the prepared user recording on a real shot")
		check(audio.voice.global_position.is_equal_approx(start) and audio.voice.max_distance >= 70, kind + " sound comes from the muzzle with distance attenuation")
		check(audio.voice.stream.get_length() < float(tower.spec().rate) if kind in ["mortar", "tesla"] else audio.voice.max_polyphony <= 3, kind + " playback is bounded for its firing rate")
		# Disable acquisition, leaving the visual tick running for exact recoil/tracer checks.
		tower.replica = true
		tower._physics_process(0.015)
		check(tower.muzzle.global_position.is_equal_approx(start) and tower.seat_position().is_equal_approx(seat), kind + " recoil leaves aiming and operator seat stable")
		if kind in ["standard", "mg42", "mortar"]:
			check(tower._weapon_model.position.z > tower._model_rest.z, kind + " has mechanical recoil")
		if kind == "standard":
			check(tower.tracer.global_position.distance_to(start) > 1 and tower.tracer.scale.z < 3, "Bullet streak travels instead of drawing a full-range laser")
		if kind == "tesla":
			var bolt = tower._lightning
			check(bolt.visible and bolt.used_vertices > 0 and bolt.global_transform == Transform3D.IDENTITY, "Tesla lightning buffer draws world-space links")
			var mesh_id: int = bolt.mesh.get_instance_id()
			var material_id: int = bolt.material.get_instance_id()
			var links := PackedVector3Array([start, start + Vector3.FORWARD * 34])
			for link in 5:
				var last: Vector3 = links[links.size() - 1]
				links.append(last)
				links.append(last + Vector3.RIGHT * 7)
			for repeat in 3: bolt.fire(links)
			check(bolt.used_vertices == (51 + 5 * 11) * 6 and bolt.used_vertices < bolt.VERTEX_CAPACITY, "Lightning buffer preserves full level-three range and all five jumps")
			check(bolt.mesh.get_instance_id() == mesh_id and bolt.material.get_instance_id() == material_id, "Repeated lightning reuses GPU mesh and material")
			bolt._process(0.19)
			check(not bolt.visible and not bolt.is_processing(), "Tesla lightning fades and stops processing after its original duration")
		if kind == "flame":
			check(tower.flame.mesh is QuadMesh and not tower.flame.local_coords, "Flame uses soft world-space sprites, not polygon spheres")
			for i in 10:
				tower.fire_at(start + Vector3.FORWARD * tower.attack_range())
				await create_timer(0.075, false).timeout
			check(tower.shot_audio.voice.playing and tower.shot_audio.gain > 0.9, "Flame sustains one looping voice across repeated shots")
			await shot("flame-side")
			tower.replica = false
			defence.mount(game.player, tower.tower_id)
			game.player.camera.make_current()
			for i in 8:
				tower.fire_at(start + Vector3.FORWARD * tower.attack_range())
				await create_timer(0.075, false).timeout
			await shot("flame-operated")
			defence.release_tower(tower)
			camera.make_current()
			tower.level = 3
			tower.fire_at(start + Vector3.FORWARD * tower.attack_range())
			check(is_equal_approx(tower.flame.lifetime * tower.flame.initial_velocity_max, tower.attack_range()), "Upgraded flame travel reaches its actual advertised range")
			await create_timer(0.32, false).timeout
			check(not tower.flame.emitting, "Flame emission stops after trigger updates cease")
			check(not tower.shot_audio.voice.playing, "Flame sound fades out after firing stops")
			defence.begin_rotation(tower)
			defence._process(0.1)
			check(defence.preview_range() == 26 and defence.range_marker.shown_radius == 26, "Rotating an upgraded tower previews the upgraded range")
			check(Lang.text(defence.hint.text).contains("26 m"), "Build hint agrees with upgraded range marker")
			camera.global_position = origin + Vector3(18, 23, 23)
			camera.look_at(origin + Vector3(0, 0, -6))
			await process_frame
			await shot("range-preview")
			defence.cancel_placement()
			tower.level = 1
			var target := StaticBody3D.new()
			target.collision_layer = 1
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2, 2, 1)
			shape.shape = box
			target.add_child(shape)
			game.add_child(target)
			game.player.camera.global_position = start + Vector3(0.4, 0.2, 1)
			for distance in [8.0, 22.0]:
				target.global_position = start + Vector3.FORWARD * distance
				game.player.camera.look_at(target.global_position)
				await physics_frame
				await physics_frame
				var readout := defence.aim_readout(tower)
				check(readout.distance > 0 and readout.within == (distance == 8.0), "Aim readout distinguishes a reachable target from one beyond range")
			target.queue_free()
			game.player.camera.position = Vector3.ZERO
		if kind == "mortar":
			tower.replica = false
			tower.fire_at(start + Vector3.FORWARD * 200)
			check(start.distance_to(tower.last_impact) <= tower.attack_range() + 0.01, "Mortar aim cannot exceed its advertised maximum range")
			await create_timer(0.8, false).timeout
			await shot("mortar-flight")
			preload("res://scripts/tower_effects.gd").explosion(game, origin + Vector3(0, 1, -10))
			await create_timer(0.12, false).timeout
			await shot("mortar-impact")
		elif kind != "flame":
			await create_timer(0.2, false).timeout
			tower.fire_at(aim)
			await process_frame
			await shot(kind)
		tower._physics_process(2.0)
		check(absf(tower._recoil) < 0.001, kind + " returns smoothly to its rest position")
		var mirror := DefenceSystem.new()
		mirror.game = game
		game.add_child(mirror)
		mirror.set_process(false)
		var state := defence.snapshot()
		mirror.apply_snapshot(state, true)
		var remote: DefenceTower = mirror.towers[tower.tower_id]
		remote.set_physics_process(false)
		check(remote._flash_t == 0, kind + " late join does not replay an old shot")
		check(remote.shot_audio == null, kind + " late join stays silent for historical shots")
		state[tower.tower_id][6] += 1
		mirror.apply_snapshot(state, false)
		check(remote._flash_t > 0 and remote.fx.remaining > 0, kind + " replicated shot starts the same new effects")
		check(remote.shot_audio.voice.playing, kind + " replicated new shot plays its user recording")
		remote.shot_audio.voice.stop()
		mirror.apply_snapshot(state, false)
		check(not remote.shot_audio.voice.playing, kind + " repeated snapshot does not replay the sound")
		var sound_ref: WeakRef = weakref(tower.shot_audio) if tower.shot_audio else null
		mirror.apply_snapshot({}, false)
		mirror.queue_free()
		tower.queue_free()
		await process_frame
		if sound_ref: check(sound_ref.get_ref() == null, kind + " destruction removes its sound emitter")
	print("TOWER_EFFECTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
