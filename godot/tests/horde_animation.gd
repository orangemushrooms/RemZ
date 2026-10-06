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
		if not old_anim or not old_rig:
			check(new_anim == null or new_rig == null, skin + " static model survives preparation without a rig")
			source.queue_free()
			prepared.queue_free()
			await process_frame
			continue
		check(old_anim.get_animation_list() == new_anim.get_animation_list() and old_rig.get_bone_count() == new_rig.get_bone_count(), skin + " retains animation catalogue and bones")
		var finite := true
		var combat_preserved := true
		var removed_constants := true
		var loops_closed := true
		var root_fixed := true
		var hips := old_rig.find_bone("Hips")
		var up_axis := 1
		if hips >= 0:
			var parent := old_rig.get_bone_parent(hips)
			var rest := old_rig.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
			up_axis = (rest.basis.inverse() * Vector3.UP).abs().max_axis_index()
		for clip in old_anim.get_animation_list():
			var original := old_anim.get_animation(clip)
			var animation := new_anim.get_animation(clip)
			var gait := clip.begins_with("walk") or clip.begins_with("run") or clip.begins_with("idle") or clip.begins_with("crawl")
			for old_track in original.get_track_count():
				var kind := original.track_get_type(old_track)
				var path := original.track_get_path(old_track)
				var track := animation.find_track(path, kind)
				if track < 0:
					var bone := new_rig.find_bone(path.get_subname(0)) if path.get_subname_count() == 1 else -1
					removed_constants = removed_constants and kind == Animation.TYPE_POSITION_3D and bone >= 0
					if kind == Animation.TYPE_POSITION_3D and bone >= 0:
						for key in original.track_get_key_count(old_track):
							removed_constants = removed_constants and (original.track_get_key_value(old_track, key) as Vector3).distance_to(new_rig.get_bone_pose_position(bone)) <= 0.00011
					continue
				var freeze_root := kind == Animation.TYPE_POSITION_3D and path.get_subname_count() == 1 and path.get_subname(0) == "Hips" and not clip.begins_with("death")
				for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var time: float = animation.length * fraction
					if freeze_root:
						var value := animation.position_track_interpolate(track, time)
						var first := original.position_track_interpolate(old_track, 0)
						for axis in 3:
							if axis != up_axis: root_fixed = root_fixed and absf(value[axis] - first[axis]) < 0.0001
					if gait: continue # Gaits intentionally change to close loops; combat timing must stay intact.
					match kind:
						Animation.TYPE_ROTATION_3D: combat_preserved = combat_preserved and original.rotation_track_interpolate(old_track, time).is_equal_approx(animation.rotation_track_interpolate(track, time))
						Animation.TYPE_SCALE_3D: combat_preserved = combat_preserved and original.scale_track_interpolate(old_track, time).is_equal_approx(animation.scale_track_interpolate(track, time))
						Animation.TYPE_POSITION_3D:
							var a := original.position_track_interpolate(old_track, time)
							var b := animation.position_track_interpolate(track, time)
							combat_preserved = combat_preserved and (absf(a[up_axis] - b[up_axis]) < 0.0001 if freeze_root else a.distance_to(b) < 0.0001)
				if gait and animation != original and animation.track_get_key_count(track) >= 2:
					match kind:
						Animation.TYPE_ROTATION_3D: loops_closed = loops_closed and animation.rotation_track_interpolate(track, 0).is_equal_approx(animation.rotation_track_interpolate(track, animation.length))
						Animation.TYPE_POSITION_3D: loops_closed = loops_closed and animation.position_track_interpolate(track, 0).distance_to(animation.position_track_interpolate(track, animation.length)) < 0.0001
			for fraction in [0.0, 0.25, 0.5, 0.75, 0.99]:
				new_anim.play(clip, 0)
				new_anim.seek(animation.length * fraction, true)
				new_anim.pause()
				new_rig.force_update_all_bone_transforms()
				for bone in new_rig.get_bone_count():
					var pose := new_rig.get_bone_global_pose(bone)
					finite = finite and pose.is_finite() and absf(pose.basis.determinant()) > 0.00001
		check(removed_constants, skin + " stripped tracks preserve constant bone offsets")
		check(combat_preserved, skin + " preserves combat rotations, vertical motion and death travel")
		check(root_fixed, skin + " horizontal root motion stays aligned with the collider")
		check(loops_closed, skin + " prepared gait loops close without a pose snap")
		check(finite, skin + " all clips produce finite nonsingular poses")
		source.queue_free()
		prepared.queue_free()
		await process_frame
	print("HORDE_ANIMATION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
