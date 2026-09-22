extends RefCounted

const MODEL := "res://assets/models/forest_gravel_cluster.glb"

static func build(parent: Node3D) -> void:
	if not ResourceLoader.exists(MODEL): return
	var source: Node3D = load(MODEL).instantiate()
	parent.add_child(source)
	var pieces := source.find_children("*", "MeshInstance3D", true, false)
	var bounds := AABB()
	var first := true
	for piece: MeshInstance3D in pieces:
		var box: AABB = (source.global_transform.affine_inverse() * piece.global_transform) * piece.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		parent.remove_child(source)
		source.queue_free()
		return
	var scale_factor := 0.32 / maxf(bounds.size.x, bounds.size.z)
	var normalize := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * scale_factor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 726421
	var chunks := {}
	for road in Map.ROADS:
		if road.surface == "asphalt": continue
		var points: Array = road.pts
		for i in points.size() - 1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var length := a.distance_to(b)
			var direction := (b - a).normalized()
			var side := Vector2(-direction.y, direction.x)
			for j in int(length / 1.8):
				var center := a.lerp(b, (float(j) + rng.randf()) * 1.8 / length)
				# Loose gravel accumulates at the shoulders; a few stones remain in the centre.
				var offset := rng.randf_range(-0.3, 0.3) if j % 4 == 0 else rng.randf_range(0.30, 0.47) * float(road.width) * (-1 if j % 2 == 0 else 1)
				var point := center + side * offset
				var ground := Vector3(point.x, Map.surface_height(point.x, point.y), point.y)
				var normal := Map.ground_normal(point.x, point.y)
				var tangent := normal.cross(Vector3.FORWARD).normalized()
				var basis := Basis(tangent, normal, tangent.cross(normal)).rotated(normal, rng.randf() * TAU)
				basis = basis.scaled(Vector3.ONE * rng.randf_range(0.65, 1.3))
				var key := Vector2i(floori(point.x / 24), floori(point.y / 24))
				if not chunks.has(key): chunks[key] = []
				chunks[key].append(Transform3D(basis, ground + normal * 0.008) * normalize)
	var root := Node3D.new()
	root.name = "ForestRoadGravel"
	# Keep our short distance budget instead of the generic tree-batch range.
	root.add_to_group("render_dynamic")
	parent.add_child(root)
	for key: Vector2i in chunks:
		var origin := Vector3(key.x * 24, 0, key.y * 24)
		for piece: MeshInstance3D in pieces:
			var mesh := MultiMesh.new()
			mesh.transform_format = MultiMesh.TRANSFORM_3D
			mesh.mesh = piece.mesh
			mesh.instance_count = chunks[key].size()
			for i in chunks[key].size():
				var transform: Transform3D = chunks[key][i] * (source.global_transform.affine_inverse() * piece.global_transform)
				transform.origin -= origin
				mesh.set_instance_transform(i, transform)
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = mesh
			instance.position = origin
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = 48
			instance.visibility_range_end_margin = 10
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(instance)
	parent.remove_child(source)
	source.queue_free()
