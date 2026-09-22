# Reusable dynamic vertex buffer: no new GPU mesh/material per lightning link.
extends MeshInstance3D

const VERTEX_CAPACITY := 1536
var vertices := PackedVector3Array()
var surface: ArrayMesh
var material: StandardMaterial3D
var remaining := 0.0
var used_vertices := 0

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color(0.25, 0.58, 1)
	material.emission_energy_multiplier = 4.5
	material_override = material
	vertices.resize(VERTEX_CAPACITY)
	vertices.fill(Vector3.ZERO)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	surface = ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh = surface
	visible = false
	set_process(false)

func fire(links: PackedVector3Array) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera or links.size() < 2: return
	used_vertices = 0
	var bounds := AABB(links[0], Vector3.ZERO)
	for link in range(0, links.size() - 1, 2):
		var from := links[link]
		var to := links[link + 1]
		var previous := from
		var segments := maxi(6, ceili(from.distance_to(to) * 1.5))
		for i in range(1, segments + 1):
			if used_vertices + 6 > VERTEX_CAPACITY: break
			var point := from.lerp(to, float(i) / segments)
			if i < segments: point += Vector3(randf_range(-0.16, 0.16), randf_range(-0.22, 0.22), randf_range(-0.16, 0.16))
			var side := (point - previous).cross(camera.global_position - previous).normalized() * 0.035
			for vertex in [previous-side, previous+side, point+side, previous-side, point+side, point-side]:
				vertices[used_vertices] = vertex
				used_vertices += 1
				bounds = bounds.expand(vertex)
			previous = point
	# Unused triangles collapse to a point; the entire capacity stays allocated.
	for i in range(used_vertices, vertices.size()): vertices[i] = links[0]
	surface.custom_aabb = bounds.grow(0.01)
	surface.surface_update_vertex_region(0, 0, vertices.to_byte_array())
	material.albedo_color = Color(0.48, 0.76, 1, 0.95)
	remaining = 0.18
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	material.albedo_color.a = 0.95 * remaining / 0.18
	if remaining <= 0.0:
		visible = false
		set_process(false)
