# Prints the bone tree of a zombie rig: --suite=rig_bones [--model=zombie_shambler]
extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var model := "zombie_shambler"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="): model = arg.get_slice("=", 1)
	var scene: PackedScene = load("res://assets/models/%s.glb" % model)
	var root: Node3D = scene.instantiate()
	get_root().add_child(root)
	var rig := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig:
		print("NO_SKELETON")
		quit(1)
		return
	for i in rig.get_bone_count():
		var parent := rig.get_bone_parent(i)
		var length := 0.0
		for c in rig.get_bone_children(i):
			length = maxf(length, rig.get_bone_rest(c).origin.length())
		print("BONE %d %s parent=%s len=%.3f pos=%s" % [i, rig.get_bone_name(i), rig.get_bone_name(parent) if parent >= 0 else "-", length, rig.get_bone_global_rest(i).origin])
	print("RIG_BONES_DONE")
	quit(0)
