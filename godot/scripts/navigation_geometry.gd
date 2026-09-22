# Immutable source geometry for runtime palisade changes. Scene parsing happens
# once during loading; rebakes only append the four small cached wall sections.
extends RefCounted

var base: NavigationMeshSourceGeometryData3D
var sections: Array[NavigationMeshSourceGeometryData3D] = []

func prepare(root: Node3D, mesh: NavigationMesh, perimeter: Perimeter) -> void:
	var included: Array[Node] = []
	if perimeter:
		for body in perimeter._section_bodies:
			if body.is_in_group("navsource"):
				included.append(body)
				body.remove_from_group("navsource")
	base = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, base, root)
	for body in included: body.add_to_group("navsource")
	if not perimeter: return
	var inverse := root.global_transform.affine_inverse()
	for body in perimeter._section_bodies:
		var data := NavigationMeshSourceGeometryData3D.new()
		for shape: CollisionShape3D in body.get_children():
			var box := BoxMesh.new()
			box.size = (shape.shape as BoxShape3D).size
			data.add_faces(box.get_faces(), inverse * shape.global_transform)
		sections.append(data)

func layout_mask(perimeter: Perimeter) -> int:
	var mask := 0
	if perimeter:
		for i in sections.size():
			if perimeter._section_bodies[i].is_in_group("navsource"): mask |= 1 << i
	return mask

# Worker input contains only immutable Resources and a value mask. No worker
# reads the live SceneTree, physics bodies or a navigation mesh being rendered.
func bake(mesh: NavigationMesh, mask: int, completed: Callable) -> void:
	var start := Time.get_ticks_usec()
	var data := for_layout(mask)
	NavigationServer3D.bake_from_source_geometry_data(mesh, data)
	if completed.is_valid(): completed.call_deferred(mesh, (Time.get_ticks_usec() - start) / 1000.0)

func for_layout(mask: int) -> NavigationMeshSourceGeometryData3D:
	var data := NavigationMeshSourceGeometryData3D.new()
	data.append_arrays(base.get_vertices(), base.get_indices())
	data.set_projected_obstructions(base.get_projected_obstructions())
	for i in sections.size():
		if mask & (1 << i): data.merge(sections[i])
	return data
