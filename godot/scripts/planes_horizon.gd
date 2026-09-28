extends Node3D
## Static northeast skyline, using the existing Meshy distant tree meshes.
## No processing, colliders or shadow passes for this inaccessible backdrop.
func build() -> void:
	name = "NortheastForest"
	for variant in 2:
		var source: Node3D = load("res://assets/planes/tree_%s_far.glb" % ["a","b"][variant]).instantiate()
		var part := Trees._first_mesh(source,Transform3D.IDENTITY)
		var mesh: Mesh = part[0].duplicate()
		var bounds := Barricade._bounds(source)
		for surface in mesh.get_surface_count():
			var material := StandardMaterial3D.new()
			material.vertex_color_use_as_albedo = true
			material.albedo_color = Color(0.20,0.48,0.18)
			material.roughness = 1.0
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(surface,material)
		var groups := {}
		var trees: Array = Map._d.get("horizon_trees",[])
		for i in range(variant,trees.size(),2):
			var tree: Array = trees[i]
			var at := Map.ground_pos(tree[0],tree[1])
			var scale_factor := float(tree[2])/bounds.size.y
			var basis := Basis(Vector3.UP,deg_to_rad(tree[3])).scaled(Vector3.ONE*scale_factor)
			var fit: Transform3D = Transform3D(basis,at-basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z))*part[1]
			var cell := Vector2i(floori(at.x/128),floori(at.z/128))
			if not groups.has(cell): groups[cell] = []
			groups[cell].append(fit)
		for cell in groups:
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.mesh = mesh
			batch.instance_count = groups[cell].size()
			for i in batch.instance_count: batch.set_instance_transform(i,groups[cell][i])
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = batch
			# Already reduced offline: another automatic LOD destroys the crowns.
			instance.lod_bias = 128.0
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
		source.free()
