extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var skins := {}
	for spec: Dictionary in Zombie.TYPES.values():
		for skin in Zombie.skin_names(spec): skins[skin] = true
	for skin: String in skins:
		var packed := load("res://assets/models/%s.glb" % skin) as PackedScene
		var source: Node3D = packed.instantiate()
		var prepared: Node3D = preload("res://scripts/zombie_animation.gd").prepare(packed).instantiate()
		root.add_child(source)
		root.add_child(prepared)
		var old_anim: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
		var new_anim: AnimationPlayer = prepared.find_child("AnimationPlayer", true, false)
		var old_rig: Skeleton3D = source.find_child("Skeleton3D", true, false)
		var new_rig: Skeleton3D = prepared.find_child("Skeleton3D", true, false)
		var difference := 0.0
		var rotations := 0.0
		for clip in old_anim.get_animation_list():
			for fraction in [0.0, 0.25, 0.5, 0.75, 0.99]:
				var time: float = old_anim.get_animation(clip).length * fraction
				old_anim.play(clip)
				new_anim.play(clip)
				old_anim.seek(time, true)
				new_anim.seek(time, true)
				old_anim.pause()
				new_anim.pause()
				await process_frame
				for bone in old_rig.get_bone_count():
					var before := old_rig.global_transform * old_rig.get_bone_global_pose(bone)
					var after := new_rig.global_transform * new_rig.get_bone_global_pose(bone)
					difference = maxf(difference, before.origin.distance_to(after.origin))
					rotations = maxf(rotations, (before.basis.x - after.basis.x).length())
		check(new_anim.get_animation("walk").get_track_count() < old_anim.get_animation("walk").get_track_count(), skin + " removes constant position tracks")
		check(difference < 0.00001 and rotations < 0.000001, skin + " preserves all sampled clips below 0.01 mm: position=" + str(difference) + " rotation=" + str(rotations))
		source.queue_free()
		prepared.queue_free()
		await process_frame
	print("HORDE_ANIMATION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
