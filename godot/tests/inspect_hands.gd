extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for side in ["right", "left"]:
		var model: Node3D = load("res://assets/viewmodel/%s_glove.fbx" % side).instantiate()
		root.add_child(model)
		print("HAND ", side)
		for node in model.find_children("*", "", true, false):
			if node is Node3D:
				print("NODE ", node.get_path(), " transform=", node.transform)
			if node is Skeleton3D:
				for i in node.get_bone_count():
					print("BONE ", i, " ", node.get_bone_name(i), " parent=", node.get_bone_parent(i), " rest=", node.get_bone_rest(i))
			if node is MeshInstance3D:
				print("MESH bounds=", node.get_aabb(), " surfaces=", node.mesh.get_surface_count())
		model.queue_free()
	quit()
