class_name RenderOptimizer
extends RefCounted

# Small spatial batches retain frustum culling and use the imported mesh LODs.
# Physics bodies stay in place; only repeated, static visual leaves are replaced.
const CELL_SIZE := 24.0

static func _has_dynamic_owner(node: Node, root: Node) -> bool:
	while node != null and node != root:
		if node.is_in_group("render_dynamic"):
			return true
		node = node.get_parent()
	return false

static func optimize(root: Node3D) -> Dictionary:
	for instance in root.find_children("*", "MultiMeshInstance3D", true, false):
		if not instance.is_in_group("render_grass") and not instance.is_in_group("render_leaves"):
			instance.add_to_group("render_trees")
	var batches := {}
	var source_count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.mesh or mi.skin or mi.get_child_count() > 0:
			continue
		var size := (mi.global_transform * mi.get_aabb()).size
		if maxf(size.x, size.z) > 80.0:
			continue # Terrain and long road ribbons must remain visible everywhere.
		var category := "trees" if size.y > 4.0 else ("detail" if size.length() < 2.5 else "props")
		mi.add_to_group("render_" + category)
		mi.set_meta("render_category", category)
		# Keep normal distance culling, but never detach pickup/door visuals from their owner.
		if _has_dynamic_owner(mi, root):
			continue
		var p := mi.global_position
		var cell := Vector2i(floori(p.x / CELL_SIZE), floori(p.z / CELL_SIZE))
		var key := "%s:%s:%s:%s:%s" % [mi.mesh.get_instance_id(), cell, category, mi.cast_shadow, mi.layers]
		key += ":%s" % (mi.material_override.get_instance_id() if mi.material_override else 0)
		for surface in mi.mesh.get_surface_count():
			var material := mi.get_surface_override_material(surface)
			key += ":%s" % (material.get_instance_id() if material else 0)
		if not batches.has(key):
			batches[key] = []
		batches[key].append(mi)
		source_count += 1
	var removed := 0
	var batch_count := 0
	for nodes: Array in batches.values():
		if nodes.size() < 3:
			continue
		var first: MeshInstance3D = nodes[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = first.mesh
		# Surface overrides must survive the conversion, without modifying shared meshes.
		for surface in first.mesh.get_surface_count():
			if first.get_surface_override_material(surface):
				mm.mesh = first.mesh.duplicate()
				for s in first.mesh.get_surface_count():
					if first.get_surface_override_material(s):
						mm.mesh.surface_set_material(s, first.get_surface_override_material(s))
				break
		mm.instance_count = nodes.size()
		var instance := MultiMeshInstance3D.new()
		instance.name = "StaticBatch%d" % batch_count
		instance.multimesh = mm
		instance.material_override = first.material_override
		instance.cast_shadow = first.cast_shadow
		instance.layers = first.layers
		var category: String = first.get_meta("render_category")
		instance.add_to_group("render_" + category)
		root.add_child(instance)
		instance.global_position = first.global_position
		var inverse := instance.global_transform.affine_inverse()
		var bounds := AABB()
		for i in nodes.size():
			var mesh_instance: MeshInstance3D = nodes[i]
			var transform := inverse * mesh_instance.global_transform
			mm.set_instance_transform(i, transform)
			var aabb := transform * mesh_instance.get_aabb()
			bounds = aabb if i == 0 else bounds.merge(aabb)
			mesh_instance.free()
		mm.custom_aabb = bounds
		removed += nodes.size() - 1
		batch_count += 1
	return {"source_meshes": source_count, "batches": batch_count, "removed_render_nodes": removed}
