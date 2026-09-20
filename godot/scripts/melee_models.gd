extends RefCounted

# Shared lightweight geometry for first-person weapons and remote survivors.
static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Knife" if id == "knife" else "Hatchet"
	var steel := _material(Color(0.38, 0.43, 0.47), 0.85, 0.3)
	var edge := _material(Color(0.72, 0.77, 0.8), 0.9, 0.19)
	var grip := _material(Color(0.105, 0.12, 0.10), 0.0, 0.9)
	var wood := _material(Color(0.32, 0.17, 0.075), 0.0, 0.8)
	if id == "knife":
		# Contoured grip scales over a full tang; exposed rivets and pommel.
		var satin := _material(Color(0.48,0.53,0.56),0.48,0.34)
		var bevel := _material(Color(0.8,0.83,0.85),0.62,0.23)
		var dark := _material(Color(0.065,0.08,0.075),0.12,0.72)
		var handle := [Vector2(-0.015,-0.12),Vector2(0.015,-0.12),Vector2(0.02,-0.09),Vector2(0.015,-0.065),Vector2(0.018,-0.01),Vector2(0.013,0.029),Vector2(-0.015,0.029),Vector2(-0.02,-0.02),Vector2(-0.022,-0.09)]
		_blade(root,handle,0.012,satin)
		_blade(root,handle,0.029,dark)
		for i in 7:
			_box(root,Vector3(0.034,0.003,0.031),Vector3(-0.001,-0.1+i*0.017,0),grip)
		for y in [-0.094,-0.01]:
			for side in [-1,1]:
				var pin := MeshInstance3D.new()
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = 0.004
				cylinder.bottom_radius = 0.004
				cylinder.height = 0.002
				cylinder.radial_segments = 12
				pin.mesh = cylinder
				pin.material_override = satin
				pin.rotation.x = PI/2
				pin.position = Vector3(0,y,side*0.016)
				root.add_child(pin)
		_box(root,Vector3(0.037,0.012,0.032),Vector3(0,-0.12,0),satin)
		_box(root,Vector3(0.063,0.012,0.035),Vector3(0,0.033,0),satin)
		# Broad drop-point blade, ground silver bevel and raised satin flats.
		_blade(root,[Vector2(-0.021,0.04),Vector2(0.024,0.04),Vector2(0.026,0.13),Vector2(0.02,0.185),Vector2(0.007,0.225),Vector2(-0.015,0.252),Vector2(-0.022,0.195)],0.002,bevel)
		_blade(root,[Vector2(-0.02,0.044),Vector2(0.012,0.044),Vector2(0.014,0.13),Vector2(0.009,0.18),Vector2(-0.002,0.215),Vector2(-0.015,0.245),Vector2(-0.021,0.193)],0.006,satin)
		for i in 5:
			_box(root,Vector3(0.005,0.004,0.007),Vector3(-0.02,0.054+i*0.008,0),dark)

	else:
		_box(root, Vector3(0.037, 0.58, 0.033), Vector3(0, 0.14, 0), wood)
		_box(root, Vector3(0.043, 0.16, 0.039), Vector3(0, -0.065, 0), grip)
		_box(root, Vector3(0.085, 0.085, 0.055), Vector3(-0.005, 0.37, 0), steel)
		_blade(root, [Vector2(0.02, 0.335), Vector2(0.15, 0.29), Vector2(0.18, 0.31), Vector2(0.18, 0.44), Vector2(0.14, 0.46), Vector2(0.02, 0.41)], 0.035, steel)
		_blade(root, [Vector2(0.15, 0.30), Vector2(0.18, 0.31), Vector2(0.18, 0.44), Vector2(0.15, 0.455)], 0.037, edge)
	return root

static func _material(color: Color, metal: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = roughness
	return material

static func _box(root: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

static func _blade(root: Node3D, outline: Array, depth: float, material: Material) -> void:
	var points := PackedVector2Array(outline)
	var triangles := Geometry2D.triangulate_polygon(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sign in [-1.0, 1.0]:
		for i in range(0, triangles.size(), 3):
			for j in ([2, 1, 0] if sign > 0 else [0, 1, 2]):
				var p := points[triangles[i + j]]
				surface.add_vertex(Vector3(p.x, p.y, sign * depth * 0.5))
	for i in points.size():
		var a := Vector3(points[i].x, points[i].y, -depth * 0.5)
		var b := Vector3(points[(i + 1) % points.size()].x, points[(i + 1) % points.size()].y, -depth * 0.5)
		for vertex in [a, b + Vector3.BACK * depth, b, a, a + Vector3.BACK * depth, b + Vector3.BACK * depth]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
