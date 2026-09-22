# Cross-check baked shot volumes against the original native convex hitboxes.
extends SceneTree

var scene: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func query(from: Vector3, to: Vector3, mask: int) -> PhysicsRayQueryParameters3D:
	var ray := PhysicsRayQueryParameters3D.create(from, to, mask)
	ray.collide_with_areas = true
	ray.hit_from_inside = true
	return ray

func actor(kind: String) -> Zombie:
	var zombie := Zombie.new()
	zombie.setup(kind, null, [], 1.0, Callable())
	zombie.replica = true
	scene.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.anim.pause()
	return zombie

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	Zombie.preload_models()
	var variants := {}
	for kind in Zombie.TYPES:
		for skin in Zombie.skin_names(Zombie.TYPES[kind]):
			if not variants.has(skin): variants[skin] = kind
	for skin in variants:
		Zombie.force_skin = skin
		var zombie := actor(variants[skin])
		zombie.position = Vector3(130, 7, -112)
		zombie.rotation.y = 0.7
		var native: Array[Area3D] = []
		for volume in zombie._shot_volumes:
			var area := Area3D.new()
			area.collision_layer = 64
			area.collision_mask = 0
			area.monitoring = false
			area.set_meta("headshot", volume.get_meta("headshot"))
			var shape := CollisionShape3D.new()
			shape.shape = volume.shape
			area.add_child(shape)
			scene.add_child(area)
			native.append(area)
		var mismatches := 0
		var max_error := 0.0
		var head_mismatches := 0
		var bounded := true
		for clip in ["walk", "attack"]:
			for time in [0.0, 0.4, 0.8]:
				zombie.anim.play(clip)
				zombie.anim.seek(time, true)
				zombie.anim.pause()
				await process_frame
				for i in native.size(): native[i].global_transform = zombie._shot_volumes[i].world_transform()
				await physics_frame
				await physics_frame
				for volume in zombie._shot_volumes:
					var point := volume.to_global(volume.center)
					var pose := zombie.model.global_transform.affine_inverse() * volume.world_transform()
					for vertex in volume.shape.points:
						bounded = bounded and AABB(Vector3(-3, -2, -3), Vector3(6, 7, 6)).has_point(pose * vertex)
					for direction in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
						var ray := query(point - direction * 80, point + direction * 80, 64)
						var expected := scene.get_world_3d().direct_space_state.intersect_ray(ray)
						ray.collision_mask = Zombie.HITBOX_LAYER
						var actual := Zombie.cast_ray(scene, ray)
						if expected.is_empty() != actual.is_empty(): mismatches += 1
						if not expected.is_empty() and not actual.is_empty():
							max_error = maxf(max_error, expected.position.distance_to(actual.position))
							if expected.collider.get_meta("headshot") != actual.collider.get_meta("headshot"): head_mismatches += 1
		check(not native.is_empty() and zombie._hitboxes.is_empty(), skin + " uses validated baked volumes")
		check(bounded, skin + " broad bounds enclose all sampled animated vertices")
		check(mismatches == 0, skin + " native/baked rays agree on hits: " + str(mismatches))
		# Jolt's native convex margin/rounding scales with the mesh (including titans).
		check(max_error < 0.003 * zombie.model.scale.x, skin + " native/baked surface distance below 3 mm in model space: " + str(max_error))
		check(head_mismatches == 0, skin + " native/baked rays agree on headshots: " + str(head_mismatches))
		for area in native: area.queue_free()
		zombie.queue_free()
		await process_frame
	Zombie.force_skin = "zombie_shambler"
	var front := actor("shambler")
	var back := actor("shambler")
	front.appearance_seed = back.appearance_seed
	front.model.scale = back.model.scale
	back.position.z = -3
	await process_frame
	var volume := front._shot_volumes[0]
	var point := volume.to_global(volume.center)
	var ray := query(point + Vector3.BACK * 10, point + Vector3.FORWARD * 10, Zombie.HITBOX_LAYER)
	check(Zombie.from_hit(Zombie.cast_ray(scene, ray)) == front, "Nearest animated actor stops ray first")
	ray.exclude = [front.get_rid()]
	check(Zombie.from_hit(Zombie.cast_ray(scene, ray)) == back, "Piercing exclusion skips all front actor bones")
	ray.exclude = [front.get_rid(), back.get_rid()]
	check(Zombie.cast_ray(scene, ray).is_empty(), "Excluded animated actors cannot block ray")
	front.queue_free()
	back.queue_free()
	await process_frame
	# Changing a source mesh hash must retain native precision until rebaked.
	var library: Dictionary = Zombie._volume_library.get_meta("volumes")
	var mesh_key := ""
	for key: String in library:
		if key.begins_with("res://assets/models/zombie_shambler.glb:"): mesh_key = key; break
	var bone: int = library[mesh_key].keys()[0]
	var hash: String = library[mesh_key][bone].hash
	library[mesh_key][bone].hash = "changed-source-fixture"
	var fallback := actor("shambler")
	library[mesh_key][bone].hash = hash
	check(fallback._hitboxes.size() == 1 and not fallback._shot_volumes.is_empty(), "Changed model automatically falls back to native convex collider")
	fallback.queue_free()
	Zombie.force_skin = ""
	print("HORDE_HIT_PRECISION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
