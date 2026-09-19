# Prints the AABB of every model in assets/models (or the names given after --) so prop scale and
# orientation can be checked without opening the editor:
#   Godot.exe --headless --path godot --script res://tests/prop_info.gd -- log_fountain waste_bin
extends SceneTree

func _initialize() -> void:
	var names: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			names.append(a)
	if names.is_empty():
		for f in DirAccess.get_files_at("res://assets/models"):
			if f.ends_with(".glb"):
				names.append(f.get_basename())
	for n in names:
		var path := "res://assets/models/%s.glb" % n
		if not ResourceLoader.exists(path):
			print("PROP %s missing" % n)
			continue
		var scene: PackedScene = load(path)
		var inst: Node3D = scene.instantiate()
		root.add_child(inst)
		var aabb := AABB()
		var first := true
		var tris := 0
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var b: AABB = inst.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3 if mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] else mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
		print("PROP %s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f) tris=%d" % [n, aabb.size.x, aabb.size.y, aabb.size.z, aabb.position.x, aabb.position.y, aabb.position.z, tris])
		inst.free()
	quit()
