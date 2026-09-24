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

static func prepare(source: PackedScene) -> PackedScene:
	var model: Node3D = source.instantiate()
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not player:
		model.free()
		return source
	var tracks := {}
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
			var path := animation.track_get_path(track)
			if path.get_subname_count() != 1: continue
			var rig := player.get_node(player.root_node).get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
			if not rig: continue
			var bone := rig.find_bone(path.get_subname(0))
			if bone < 0: continue
			for key in animation.track_get_key_count(track):
				var value: Vector3 = animation.track_get_key_value(track, key)
				if not tracks.has(path): tracks[path] = {"rig": rig, "bone": bone, "value": value, "constant": true}
				# Rig coordinates are centimetres. Maximum deviation is one micron.
				if tracks[path].value.distance_to(value) > 0.0001: tracks[path].constant = false
	var constants := {}
	for path: NodePath in tracks:
		if not tracks[path].constant: continue
		var rig: Skeleton3D = tracks[path].rig
		rig.set_bone_pose_position(tracks[path].bone, tracks[path].value)
		constants[path] = true
	if constants.is_empty():
		model.free()
		return source
	for name in player.get_animation_library_list():
		var original := player.get_animation_library(name)
		var library := AnimationLibrary.new()
		for clip in original.get_animation_list():
			var animation := original.get_animation(clip).duplicate(true) as Animation
			for track in range(animation.get_track_count() - 1, -1, -1):
				if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and constants.has(animation.track_get_path(track)):
					animation.remove_track(track)
			library.add_animation(clip, animation)
		player.remove_animation_library(name)
		player.add_animation_library(name, library)
	var prepared := PackedScene.new()
	var result := prepared.pack(model)
	model.free()
	return prepared if result == OK else source
