# Tool input for tools/bake_zombie_hit_shapes.py; no game save data is touched.
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Zombie.preload_models()
	var data := {}
	for key in Zombie._hitbox_shapes:
		var bones := {}
		for bone in Zombie._hitbox_shapes[key]:
			var shape: ConvexPolygonShape3D = Zombie._hitbox_shapes[key][bone]
			var points: Array = []
			for point in shape.points: points.append([point.x, point.y, point.z])
			bones[str(bone)] = {"points": points, "hash": var_to_bytes(shape.points).hex_encode().sha256_text()}
		data[key] = bones
	var path := ProjectSettings.globalize_path("res://../artifacts/zombie-hit-shapes.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(data))
	output.close()
	print("HIT_SHAPES_EXPORTED models=",data.size())
	quit(0)
