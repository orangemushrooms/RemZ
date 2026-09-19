class_name WeaponSkins
extends RefCounted

const SHADER = preload("res://shaders/weapon_finish.gdshader")

static func apply(root: Node3D, finish: String, marked_only := false) -> void:
	var palette := {
		"forest": [Color("303d24"), Color("676341"), Color("202b20"), 0.12, 0.75, 0],
		"bronze": [Color("63442b"), Color("b78443"), Color("242827"), 0.78, 0.36, 1],
		"bone": [Color("b5ae8f"), Color("e2d7b8"), Color("222a29"), 0.25, 0.6, 2],
	}
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if marked_only and not mesh.has_meta("weapon_surface"): continue
		for i in mesh.mesh.get_surface_count():
			var key := "original_material_%d" % i
			if not mesh.has_meta(key): mesh.set_meta(key, mesh.get_active_material(i))
			var source: Material = mesh.get_meta(key)
			if not palette.has(finish):
				mesh.set_surface_override_material(i, source)
				continue
			if not source is StandardMaterial3D: continue
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			var colors: Array = palette[finish]
			mat.set_shader_parameter("base_tex", source.albedo_texture)
			mat.set_shader_parameter("normal_tex", source.normal_texture)
			mat.set_shader_parameter("has_normal", source.normal_enabled and source.normal_texture != null)
			mat.set_shader_parameter("color_a", colors[0])
			mat.set_shader_parameter("color_b", colors[1])
			mat.set_shader_parameter("color_c", colors[2])
			mat.set_shader_parameter("finish_metal", colors[3])
			mat.set_shader_parameter("finish_roughness", colors[4])
			mat.set_shader_parameter("pattern", colors[5])
			mesh.set_surface_override_material(i, mat)
