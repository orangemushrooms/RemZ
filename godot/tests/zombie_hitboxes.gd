extends SceneTree

var checks := 0
var failures := 0
var scene: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func shoot(point: Vector3, direction := Vector3.FORWARD) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point - direction * 10, point + direction * 10, 1 | 2 | 8 | Zombie.HITBOX_LAYER)
	ray.collide_with_areas = true
	ray.hit_from_inside = true
	return scene.get_world_3d().direct_space_state.intersect_ray(ray)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	# Loading consumers also checks their shared collider resolution compiles.
	check(load("res://scripts/weapons.gd").can_instantiate(), "Weapons script compiles")
	check(load("res://scripts/defence_tower.gd").can_instantiate(), "Tower script compiles")
	var zombie := Zombie.new()
	zombie.setup("brute", null, [], 1.0, Callable())
	zombie.replica = true
	zombie.appearance_seed = 42
	scene.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.anim.pause()
	zombie.anim.seek(0.0, true)
	await process_frame
	await physics_frame
	await physics_frame
	check(zombie._hitboxes.size() >= 10, "Brute has separate animated body and limb hitboxes")
	var tested_limbs := 0
	var outside_capsule := 0
	var head_point := Vector3.ZERO
	for area in zombie._hitboxes:
		var shape: ConvexPolygonShape3D = area.get_child(0).shape
		var center := Vector3.ZERO
		for point in shape.points: center += point
		center /= shape.points.size()
		var aim := area.to_global(center)
		if Vector2(aim.x, aim.z).length() > 0.4: outside_capsule += 1
		check(Zombie.from_hit(shoot(aim)) == zombie, "Ray hits animated " + str(area.get_parent().bone_name))
		if area.get_meta("headshot"): head_point = aim
		tested_limbs += 1
	check(tested_limbs > 0 and outside_capsule >= 4, "Visible limbs outside the old capsule are hittable")
	check(head_point.y > 1.5 and head_point.y < 4.0, "Hitbox transforms match the model's actual metre scale")
	var head_hit := shoot(head_point)
	check(not head_hit.is_empty() and head_hit.collider.get_meta("headshot", false), "Visible head registers a headshot")
	var close_ray := PhysicsRayQueryParameters3D.create(head_point, head_point + Vector3.FORWARD, Zombie.HITBOX_LAYER)
	close_ray.collide_with_areas = true
	close_ray.hit_from_inside = true
	check(Zombie.from_hit(scene.get_world_3d().direct_space_state.intersect_ray(close_ray)) == zombie, "Point-blank shots hit even when the camera is inside the hitbox")
	zombie.anim.play("attack")
	zombie.anim.seek(0.4, true)
	zombie.anim.pause()
	await process_frame
	await physics_frame
	await physics_frame
	for area in zombie._hitboxes:
		if "Hand" not in str(area.get_parent().bone_name): continue
		var points: PackedVector3Array = area.get_child(0).shape.points
		var center := Vector3.ZERO
		for point in points: center += point
		center /= points.size()
		check(Zombie.from_hit(shoot(area.to_global(center))) == zombie, "Hand remains hittable during attack animation")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 0.3)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	scene.add_child(wall)
	wall.position.z = 5
	await physics_frame
	await physics_frame
	check(shoot(head_point).get("collider") == wall, "World geometry still blocks bullets before a hitbox")
	wall.queue_free()
	zombie.die(Vector3.ZERO)
	await physics_frame
	await physics_frame
	check(shoot(head_point).is_empty(), "Dead zombies no longer block shots")
	for skin in ["zombie_titan", "zombie_colossus"]:
		Zombie.force_skin = skin
		var giant := Zombie.new()
		giant.setup("titan", null, [], 1.0, Callable())
		giant.replica = true
		scene.add_child(giant)
		giant.set_physics_process(false)
		giant.anim.pause()
		giant.anim.seek(0.0, true)
		await process_frame
		await physics_frame
		await physics_frame
		check(giant._hitboxes.size() >= 10, skin + " has model-fitted hitboxes")
		var hits := 0
		for area in giant._hitboxes:
			var points: PackedVector3Array = area.get_child(0).shape.points
			var center := Vector3.ZERO
			for point in points: center += point
			center /= points.size()
			if Zombie.from_hit(shoot(area.to_global(center))) == giant: hits += 1
		check(hits == giant._hitboxes.size(), skin + " hitboxes scale with the giant model")
		giant.queue_free()
		await process_frame
	Zombie.force_skin = ""
	print("ZOMBIE_HITBOXES_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
