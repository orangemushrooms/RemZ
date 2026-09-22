# Meshy rigs contain position tracks which only repeat constant bone lengths
# plus sub-micrometre exporter noise. Store these once on the skeleton instead
# of blending/writing them for every actor and frame. Moving tracks are intact.
extends RefCounted

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
