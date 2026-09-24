# Meshy rigs contain position tracks which only repeat constant bone lengths
# plus sub-micrometre exporter noise. Store these once on the skeleton instead
# of blending/writing them for every actor and frame. Moving tracks are intact.
extends RefCounted

const SAMPLES := 32

# Clip metrics of one model, measured once while loading: for every clip its length, the ground speed
# its feet imply ("speed", m/s for the 1.7 m rig, multiply by the model scale) and the moment of the
# strike ("peak", seconds - the fastest hand movement). Zombie plays a gait at speed_scale =
# velocity / speed, so the feet stop sliding, and times a swing so the strike lands on the damage tick.
static func measure(source: PackedScene, host: Node = null) -> Dictionary:
	var info := {}
	var model: Node3D = source.instantiate()
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not player or not rig:
		model.free()
		return info
	if host == null and Engine.get_main_loop() is SceneTree:
		host = (Engine.get_main_loop() as SceneTree).root
	if host: host.add_child(model)
	var hips := rig.find_bone("Hips")
	var feet := [rig.find_bone("LeftFoot"), rig.find_bone("RightFoot")]
	var hands := [rig.find_bone("LeftHand"), rig.find_bone("RightHand")]
	var to_model := model.global_transform.affine_inverse() * rig.global_transform
	for clip in player.get_animation_list():
		var length := player.get_animation(clip).length
		if length <= 0.0: continue
		var foot_pos: Array = [PackedVector3Array(), PackedVector3Array()]
		var hand_pos: Array = [PackedVector3Array(), PackedVector3Array()]
		player.play(clip)
		for i in SAMPLES + 1:
			player.seek(length * float(i) / SAMPLES, true)
			rig.force_update_all_bone_transforms()
			var origin := to_model * rig.get_bone_global_pose(hips).origin if hips >= 0 else Vector3.ZERO
			for f in 2:
				foot_pos[f].append(to_model * rig.get_bone_global_pose(feet[f]).origin - origin if feet[f] >= 0 else Vector3.ZERO)
			for h in 2:
				hand_pos[h].append(to_model * rig.get_bone_global_pose(hands[h]).origin - origin if hands[h] >= 0 else Vector3.ZERO)
		# Ground covered per clip: each foot travels its horizontal range once per step, and it takes one
		# step per two crossings of its mean position (the swing forward and the stance backwards).
		var distance := 0.0
		for f in 2:
			var points: PackedVector3Array = foot_pos[f]
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			var mean := Vector3.ZERO
			for p in points:
				lo = lo.min(p)
				hi = hi.max(p)
				mean += p
			mean /= maxf(points.size(), 1)
			var axis := 0 if hi.x - lo.x > hi.z - lo.z else 2
			var crossings := 0
			for i in range(1, points.size()):
				if (points[i][axis] - mean[axis]) * (points[i - 1][axis] - mean[axis]) < 0.0: crossings += 1
			distance += (hi[axis] - lo[axis]) * maxf(1.0, roundf(crossings / 2.0))
		var peak := 0.0
		var fastest := 0.0
		for h in 2:
			var points: PackedVector3Array = hand_pos[h]
			for i in range(1, points.size()):
				var v := points[i].distance_to(points[i - 1])
				if v > fastest:
					fastest = v
					peak = length * float(i) / SAMPLES
		info[clip] = {"length": length, "speed": distance / length, "peak": peak}
	player.stop()
	if host: host.remove_child(model)
	model.free()
	return info

# Loop clips whose last pose differs from the first by more than this are cut at their best loop point.
const SEAM_DEG := 20.0
const SEAM_SAMPLES := 48
const SEAM_BLEND := 0.12

static func _is_gait(clip: String) -> bool:
	return clip.begins_with("walk") or clip.begins_with("run") or clip.begins_with("idle")

static func _pose_gap(rig: Skeleton3D, a: Array, b: Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, (a[i] as Quaternion).angle_to(b[i] as Quaternion))
	return worst

static func _pose(rig: Skeleton3D) -> Array:
	var out := []
	for b in rig.get_bone_count(): out.append(rig.get_bone_pose_rotation(b))
	return out

# Three fixes applied once per model while loading, so every actor plays clean clips:
# 1. Constant bone-length position tracks are stored on the skeleton and dropped (see above).
# 2. Root motion: Meshy's library gaits and flinches carry the walk in the Hips position track (walk2
#    of the shambler rigs travels 3.4 m per loop, the runner sprints 3 m per 0.5 s), while the body is
#    moved by the navigation. The mesh ran ahead of its collider and snapped back at every loop. The
#    horizontal Hips motion is frozen at its first key for every clip but the deaths (a corpse stays
#    where it fell); the vertical bob stays.
# 3. Loop seams: a gait whose last pose is far from its first (walk2: 44 deg, the library clip starts
#    mid-step) is cut to the window of at least 40 % of its length whose two ends match best, and the
#    last SEAM_BLEND seconds of every gait glide into its first pose, so the loop closes without a jump.
static func prepare(source: PackedScene, host: Node = null) -> PackedScene:
	var model: Node3D = source.instantiate()
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not player or not rig:
		model.free()
		return source
	if host == null and Engine.get_main_loop() is SceneTree:
		host = (Engine.get_main_loop() as SceneTree).root
	if host: host.add_child(model)
	var tracks := {}
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
			var path := animation.track_get_path(track)
			if path.get_subname_count() != 1: continue
			var bone := rig.find_bone(path.get_subname(0))
			if bone < 0: continue
			for key in animation.track_get_key_count(track):
				var value: Vector3 = animation.track_get_key_value(track, key)
				if not tracks.has(path): tracks[path] = {"bone": bone, "value": value, "constant": true}
				# Rig coordinates are centimetres. Maximum deviation is one micron.
				if tracks[path].value.distance_to(value) > 0.0001: tracks[path].constant = false
	var constants := {}
	for path: NodePath in tracks:
		if not tracks[path].constant: continue
		rig.set_bone_pose_position(tracks[path].bone, tracks[path].value)
		constants[path] = true
	# the up axis of the Hips position track (parent-bone space) for the root-motion freeze
	var hips := rig.find_bone("Hips")
	var up_axis := 1
	if hips >= 0:
		var parent := rig.get_bone_parent(hips)
		var rest := rig.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
		var local_up := rest.basis.inverse() * Vector3.UP
		up_axis = 0 if absf(local_up.x) > absf(local_up.y) and absf(local_up.x) > absf(local_up.z) else (2 if absf(local_up.z) > absf(local_up.y) else 1)
	# loop seams of the gaits
	var cuts := {}
	for clip in player.get_animation_list():
		if not _is_gait(clip): continue
		var length := player.get_animation(clip).length
		if length <= 0.2: continue
		player.play(clip)
		var poses := []
		for i in SEAM_SAMPLES + 1:
			player.seek(length * float(i) / SEAM_SAMPLES, true)
			rig.force_update_all_bone_transforms()
			poses.append(_pose(rig))
		var seam := _pose_gap(rig, poses[0], poses[SEAM_SAMPLES])
		if rad_to_deg(seam) <= SEAM_DEG: continue
		var best := Vector2i(0, SEAM_SAMPLES)
		var best_gap := seam
		var min_span := int(SEAM_SAMPLES * 0.4)
		for i in range(0, SEAM_SAMPLES - min_span):
			for j in range(i + min_span, SEAM_SAMPLES + 1):
				var gap := _pose_gap(rig, poses[i], poses[j])
				if gap < best_gap:
					best_gap = gap
					best = Vector2i(i, j)
		if best != Vector2i(0, SEAM_SAMPLES):
			cuts[clip] = Vector2(length * float(best.x) / SEAM_SAMPLES, length * float(best.y) / SEAM_SAMPLES)
	player.stop()
	if constants.is_empty() and hips < 0 and cuts.is_empty():
		if host: host.remove_child(model)
		model.free()
		return source
	for name in player.get_animation_library_list():
		var original := player.get_animation_library(name)
		var library := AnimationLibrary.new()
		for clip in original.get_animation_list():
			var animation := original.get_animation(clip).duplicate(true) as Animation
			for track in range(animation.get_track_count() - 1, -1, -1):
				if animation.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
				var path := animation.track_get_path(track)
				if constants.has(path):
					animation.remove_track(track)
				elif hips >= 0 and path.get_subname_count() == 1 and path.get_subname(0) == rig.get_bone_name(hips) and not clip.begins_with("death"):
					var first: Vector3 = animation.track_get_key_value(track, 0) if animation.track_get_key_count(track) > 0 else Vector3.ZERO
					for key in animation.track_get_key_count(track):
						var value: Vector3 = animation.track_get_key_value(track, key)
						for axis in 3:
							if axis != up_axis: value[axis] = first[axis]
						animation.track_set_key_value(track, key, value)
			if cuts.has(clip): _cut(animation, cuts[clip].x, cuts[clip].y)
			if _is_gait(clip): _close_loop(animation)
			library.add_animation(clip, animation)
		player.remove_animation_library(name)
		player.add_animation_library(name, library)
	if host: host.remove_child(model)
	var prepared := PackedScene.new()
	var result := prepared.pack(model)
	model.free()
	return prepared if result == OK else source

# Keep only the window [start, end] of a clip: a key at the window's start is interpolated in, earlier
# keys go, the rest shift to time zero and the length becomes the window.
static func _cut(animation: Animation, start: float, end: float) -> void:
	for track in animation.get_track_count():
		var kind := animation.track_get_type(track)
		if start > 0.0:
			match kind:
				Animation.TYPE_POSITION_3D: animation.position_track_insert_key(track, start, animation.position_track_interpolate(track, start))
				Animation.TYPE_ROTATION_3D: animation.rotation_track_insert_key(track, start, animation.rotation_track_interpolate(track, start))
				Animation.TYPE_SCALE_3D: animation.scale_track_insert_key(track, start, animation.scale_track_interpolate(track, start))
		for key in range(animation.track_get_key_count(track) - 1, -1, -1):
			var t := animation.track_get_key_time(track, key)
			if t < start - 0.0005 or t > end + 0.0005:
				animation.track_remove_key(track, key)
		for key in animation.track_get_key_count(track):
			animation.track_set_key_time(track, key, maxf(0.0, animation.track_get_key_time(track, key) - start))
	animation.length = end - start

# The last SEAM_BLEND seconds of a loop interpolate into the pose of its first frame: the loop wraps
# without a visible seam whatever the library clip ends on.
static func _close_loop(animation: Animation) -> void:
	var length := animation.length
	var blend := minf(SEAM_BLEND, length * 0.2)
	if blend <= 0.01: return
	for track in animation.get_track_count():
		var kind := animation.track_get_type(track)
		if animation.track_get_key_count(track) < 2: continue
		match kind:
			Animation.TYPE_ROTATION_3D:
				var hold := animation.rotation_track_interpolate(track, length - blend)
				var first := animation.rotation_track_interpolate(track, 0.0)
				for key in range(animation.track_get_key_count(track) - 1, -1, -1):
					if animation.track_get_key_time(track, key) > length - blend + 0.0005: animation.track_remove_key(track, key)
				animation.rotation_track_insert_key(track, length - blend, hold)
				animation.rotation_track_insert_key(track, length, first)
			Animation.TYPE_POSITION_3D:
				var hold := animation.position_track_interpolate(track, length - blend)
				var first := animation.position_track_interpolate(track, 0.0)
				for key in range(animation.track_get_key_count(track) - 1, -1, -1):
					if animation.track_get_key_time(track, key) > length - blend + 0.0005: animation.track_remove_key(track, key)
				animation.position_track_insert_key(track, length - blend, hold)
				animation.position_track_insert_key(track, length, first)
