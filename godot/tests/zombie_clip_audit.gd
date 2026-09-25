# Clip audit of every zombie rig (headless):
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=zombie_clip_audit
# For every clip: the root (Hips) drift over the clip in the rig's XZ plane (a gait that walks away from
# its origin snaps back on the loop), the hip height range, the loop seam of the gaits (pose difference
# between the last and the first frame) and the final hip height of the death clips (a corpse must lie
# on the ground, not float). Prints CLIP_AUDIT lines and fails on drift, a hard seam or a floating corpse.
extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func _initialize() -> void: call_deferred("run")

func pose(rig: Skeleton3D) -> Array:
	var out := []
	for b in rig.get_bone_count():
		out.append(rig.get_bone_pose_rotation(b))
	return out

var worst_bone := -1

func pose_diff(a: Array, b: Array) -> float:
	var worst := 0.0
	worst_bone = -1
	for i in a.size():
		var q: Quaternion = a[i]
		var r: Quaternion = b[i]
		var gap := q.angle_to(r)
		if gap > worst:
			worst = gap
			worst_bone = i
	return worst

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var skins := {}
	for spec: Dictionary in Zombie.TYPES.values():
		# worms have their own rig rules; the hovering Forest Spirit (a boss of its own kind, locally rigged,
		# feet never on the floor by design) has its own suite
		if spec.get("worm", false) or spec.get("boss", false): continue
		for skin in Zombie.skin_names(spec): skins[skin] = true
	for skin in skins:
		var path := "res://assets/models/%s.glb" % skin
		if not ResourceLoader.exists(path): continue
		var scene: PackedScene = preload("res://scripts/zombie_animation.gd").prepare(load(path), host)
		var model: Node3D = scene.instantiate()
		host.add_child(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
		if not player or not rig:
			model.queue_free()
			continue
		var hips := rig.find_bone("Hips")
		var feet := [rig.find_bone("LeftFoot"), rig.find_bone("RightFoot")]
		var to_model := model.global_transform.affine_inverse() * rig.global_transform
		for clip in player.get_animation_list():
			var length := player.get_animation(clip).length
			player.play(clip)
			var samples := 40
			var origins := PackedVector3Array()
			var foot_min := INF
			var first_pose: Array = []
			var last_pose: Array = []
			for i in samples + 1:
				player.seek(length * float(i) / samples, true)
				rig.force_update_all_bone_transforms()
				var o := to_model * rig.get_bone_global_pose(hips).origin
				origins.append(o)
				for f in feet:
					if f >= 0: foot_min = minf(foot_min, (to_model * rig.get_bone_global_pose(f).origin).y)
				if i == 0: first_pose = pose(rig)
				if i == samples: last_pose = pose(rig)
			var drift := Vector2(origins[-1].x - origins[0].x, origins[-1].z - origins[0].z).length()
			var hy_min := INF
			var hy_max := -INF
			for o in origins:
				hy_min = minf(hy_min, o.y)
				hy_max = maxf(hy_max, o.y)
			var seam := rad_to_deg(pose_diff(first_pose, last_pose))
			var seam_bone := rig.get_bone_name(worst_bone) if worst_bone >= 0 else "-"
			var gait := clip.begins_with("walk") or clip.begins_with("run") or clip.begins_with("idle")
			print("CLIP_AUDIT %s %s len=%.2f drift=%.3f hips_y=%.2f..%.2f end_y=%.2f foot_min=%.2f seam=%.1fdeg(%s)" % [skin, clip, length, drift, hy_min, hy_max, origins[-1].y, foot_min, seam, seam_bone])
			if gait:
				check(drift < 0.15, "%s %s stays in place (drift %.2f m)" % [skin, clip, drift])
				check(seam < 8.0, "%s %s loops without a seam (%.1f deg on %s)" % [skin, clip, seam, seam_bone])
			if clip.begins_with("death"):
				check(origins[-1].y < 0.45, "%s %s ends on the ground (hips at %.2f m)" % [skin, clip, origins[-1].y])
			check(foot_min > -0.25, "%s %s keeps the feet above the floor (lowest %.2f m)" % [skin, clip, foot_min])
		player.stop()
		model.queue_free()
	print("ZOMBIE_CLIP_AUDIT_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
