extends RefCounted

# Distant farmsteads retain their map footprints. Merge their architectural parts
# by material and 64 m cell, so windows/roofs stay together at every quality level.
const CELL_SIZE := 64.0
const PLASTER := [Color(0.92, 0.9, 0.84), Color(0.88, 0.85, 0.76), Color(0.95, 0.93, 0.88), Color(0.86, 0.8, 0.7)]
const SHUTTERS := [Color(0.20, 0.29, 0.22), Color(0.31, 0.16, 0.12), Color(0.25, 0.29, 0.30)]
var _batches := {}
var _materials := {}
var _cube: Array
var _frame := Transform3D.IDENTITY
var _cell := Vector2i.ZERO
var _rng := RandomNumberGenerator.new()
var _building_count := 0

func build() -> Node3D:
	Map._ensure()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_cube = cube.get_mesh_arrays()
	_materials = _make_materials()
	for i in Map.VILLAGE.size():
		_build_house(Map.VILLAGE[i], i)
	var root := Node3D.new()
	root.name = "VillageBuildings"
	var triangles := 0
	for key: String in _batches:
		var batch: Dictionary = _batches[key]
		var surface: SurfaceTool = batch.surface
		surface.index()
		surface.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "Village_%s" % key.replace(":", "_")
		mi.mesh = surface.commit()
		mi.material_override = _materials[batch.material]
		mi.position = batch.origin
		mi.add_to_group("render_backdrop")
		# These buildings lie beyond the sun's shadow range. Their recessed windows,
		# dark soffits and foundation bands carry the small-scale depth cues.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		triangles += mi.mesh.surface_get_array_index_len(0) / 3
	root.set_meta("buildings", _building_count)
	root.set_meta("triangles", triangles)
	return root

func _make_materials() -> Dictionary:
	var result := {}
	# Keep distant facades out of the nearby shadow atlas: receiving its cascades
	# beyond their useful range produces black speckling on the small roof/window faces.
	for pair in [["wood", "planks"], ["tiles", "roof"], ["slate", "ph_roof_dark"], ["stone", "rock"]]:
		var material := Foliage.pbr(pair[1], 0.55)
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
		material.normal_scale = 0.45
		result[pair[0]] = material
	for id in ["plaster", "trim", "glass"]:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = 0.92 if id != "glass" else 0.3
		material.metallic_specular = 0.15 if id != "glass" else 0.4
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
		if id == "plaster":
			material.normal_enabled = true
			material.normal_texture = load("res://assets/textures/ph_concrete_normal.jpg")
			material.normal_scale = 0.12
			material.uv1_scale = Vector3.ONE * 0.8
		result[id] = material
	return result

func _build_house(data: Dictionary, id: int) -> void:
	var pts := PackedVector2Array()
	for p in data.poly:
		pts.append(Vector2(p[0], p[1]))
	if pts.size() < 3:
		return
	var direction := Vector2.RIGHT
	var longest := 0.0
	for i in pts.size():
		var edge := pts[(i + 1) % pts.size()] - pts[i]
		if edge.length_squared() > longest:
			longest = edge.length_squared()
			direction = edge.normalized()
	var side := Vector2(-direction.y, direction.x)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in pts:
		var q := Vector2(p.dot(direction), p.dot(side))
		low = low.min(q)
		high = high.max(q)
	var size := high - low
	if minf(size.x, size.y) < 3.0:
		return
	var mid := (low + high) * 0.5
	var center := direction * mid.x + side * mid.y
	var yaw := -direction.angle()
	# Use one local frame: the ridge always follows the longer building axis.
	if size.y > size.x:
		size = Vector2(size.y, size.x)
		yaw += PI / 2.0
	_frame = Transform3D(Basis(Vector3.UP, yaw), Map.ground_pos(center.x, center.y))
	_cell = Vector2i(floori(center.x / CELL_SIZE), floori(center.y / CELL_SIZE))
	_rng.seed = 81013 + id * 7919
	_building_count += 1
	# Sennhof / Remetschwil (photo 4): white one- or two-storey houses under steep gable roofs, dark timber
	# barns and long Aargau farmhouses with the barn under the same roof. Nothing taller than two floors.
	var area := size.x * size.y
	var kind := "house"
	if area < 60.0:
		kind = "shed"
	elif float(data.h) < 5.0 or (area > 300.0 and size.x / size.y > 1.6 and id % 3 == 0):
		kind = "barn"
	elif area > 240.0:
		kind = "farm"
	var barn := kind == "barn"
	var shed := kind == "shed"
	var farmhouse := kind == "farm"
	var height: float = float({ "house": 5.5, "farm": 5.2, "barn": 4.8, "shed": 2.7 }[kind]) + _rng.randf_range(-0.25, 0.25)
	# steep roofs dominate the silhouette: ~42 deg on houses and farms, ~30 deg on barns and sheds
	var roof_height := clampf(size.y * 0.5 * (0.9 if not (barn or shed) else 0.58) * _rng.randf_range(0.95, 1.05), 1.4, 7.5)
	var wall_color: Color = PLASTER[id % PLASTER.size()]
	var wood_color := Color(0.33, 0.24, 0.17) * _rng.randf_range(0.85, 1.1)
	var shutter_color: Color = SHUTTERS[id % SHUTTERS.size()]
	var roof_material := "slate" if barn or shed or id % 7 == 3 else "tiles"
	var roof_color := (Color(0.62, 0.4, 0.3) if roof_material == "tiles" else Color(0.42, 0.4, 0.38)) * _rng.randf_range(0.85, 1.1)
	# Extend foundations into the hillside instead of letting downhill corners float.
	var lowest := 0.0
	for x: float in [-size.x * 0.5, size.x * 0.5]:
		for z: float in [-size.y * 0.5, size.y * 0.5]:
			var corner := _frame * Vector3(x, 0, z)
			lowest = minf(lowest, Map.ground_height(corner.x, corner.z) - _frame.origin.y - 0.6)
	_box("stone", Vector3(size.x + 0.12, 0.65 - lowest, size.y + 0.12), Vector3(0, (0.65 + lowest) * 0.5, 0), Color(0.52, 0.49, 0.43))
	_box("wood" if barn or shed else "plaster", Vector3(size.x, height - 0.45, size.y), Vector3(0, (height + 0.45) * 0.5, 0), wood_color if barn or shed else wall_color)
	# farmhouse: the barn takes the larger (+x) part of the length in dark boards, the dwelling the rest
	var house_len := size.x
	if farmhouse:
		house_len = clampf(size.x * 0.42, 8.0, 14.0)
		var barn_len := size.x - house_len
		_box("wood", Vector3(barn_len, height - 0.45, size.y + 0.04), Vector3(size.x * 0.5 - barn_len * 0.5, (height + 0.45) * 0.5, 0), wood_color)
	_roof(size, height, roof_height, roof_material, roof_color, wood_color, wall_color if not barn and not shed else wood_color, barn or shed or farmhouse)
	for face in 4:
		var length := size.x if face < 2 else size.y
		var front := _facade(size, face)
		var timber_face := barn or shed or (farmhouse and face == 2)
		if timber_face:
			if face % 2 == 0 or (barn and length > 14.0):
				_gate(front, 0.0, minf(4.0, length * 0.42), minf(3.6, height - 0.5), wood_color)
			# Upright timber posts and the sill beam make barns read at field distance.
			var posts := maxi(2, int(length / 3.8))
			for post in posts + 1:
				var x := lerpf(-length * 0.5 + 0.14, length * 0.5 - 0.14, float(post) / posts)
				_box("wood", Vector3(0.18, height - 0.65, 0.15), front * Vector3(x, (height + 0.65) * 0.5, 0.09), wood_color * 0.55, front.basis)
			continue
		# dwelling facades: one window row per floor, at most three per floor on the long sides
		var span_start := -length * 0.5
		var span_end := length * 0.5
		if farmhouse and face < 2:
			# only the dwelling end of the long side gets windows; the barn part has boards and a gate
			var barn_len := size.x - house_len
			if face == 0:
				span_end = -size.x * 0.5 + house_len
				_gate(front, size.x * 0.5 - barn_len * 0.5, minf(4.0, barn_len * 0.4), minf(3.6, height - 0.5), wood_color)
			else:
				span_start = size.x * 0.5 - house_len
				_gate(front, -(size.x * 0.5 - barn_len * 0.5), minf(3.0, barn_len * 0.3), minf(3.0, height - 0.8), wood_color)
			var posts := maxi(2, int(barn_len / 3.8))
			for post in posts + 1:
				var x := lerpf(size.x * 0.5 - barn_len + 0.14, size.x * 0.5 - 0.14, float(post) / posts) * (1.0 if face == 0 else -1.0)
				_box("wood", Vector3(0.18, height - 0.65, 0.15), front * Vector3(x, (height + 0.65) * 0.5, 0.11), wood_color * 0.55, front.basis)
		var span := span_end - span_start
		var columns := clampi(int(span / 4.6), 1, 3)
		var floors := 2 if height > 4.6 else 1
		for floor_index in floors:
			for column in columns:
				var x := span_start + (float(column) + 0.5) * span / columns
				if face == 0 and floor_index == 0 and column == columns / 2 and not farmhouse:
					_gate(front, x, 1.1, 2.25, shutter_color)
					continue
				_window(front, x, 1.55 + floor_index * 2.55, shutter_color, 0.9)
	# Small gable loft opening, retained as part of the same spatial batch.
	for face in [2, 3]:
		var front := _facade(size, face)
		if not barn and not shed and not (farmhouse and face == 2):
			_window(front, 0.0, height + roof_height * 0.38, shutter_color, 0.65)
		else:
			_box("trim", Vector3(0.7, 0.9, 0.06), front * Vector3(0, height + roof_height * 0.32, 0.05), Color(0.075, 0.065, 0.052), front.basis)
	if not barn and not shed:
		var chimney_z := size.y * 0.15
		var chimney_x := -size.x * 0.22 if not farmhouse else -size.x * 0.5 + house_len * 0.5
		var chimney_bottom := height + roof_height * 0.62
		_box("plaster", Vector3(0.7, 1.5, 0.75), Vector3(chimney_x, chimney_bottom + 0.6, chimney_z), wall_color * 0.72)
		_box("trim", Vector3(0.88, 0.14, 0.93), Vector3(chimney_x, chimney_bottom + 1.4, chimney_z), Color(0.22, 0.21, 0.19))

# The front of every facade is local +z; windows can share the same construction.
func _facade(size: Vector2, side: int) -> Transform3D:
	var offsets := [Vector3(0, 0, size.y * 0.5), Vector3(0, 0, -size.y * 0.5), Vector3(size.x * 0.5, 0, 0), Vector3(-size.x * 0.5, 0, 0)]
	var angles := [0.0, PI, PI / 2.0, -PI / 2.0]
	return Transform3D(Basis(Vector3.UP, angles[side]), offsets[side])

func _window(front: Transform3D, x: float, y: float, shutters: Color, scale: float = 1.0) -> void:
	var width := 1.08 * scale
	var height := 1.38 * scale
	_box("trim", Vector3(width + 0.22, height + 0.22, 0.10), front * Vector3(x, y, 0.075), Color(0.38, 0.35, 0.29), front.basis)
	_box("glass", Vector3(width, height, 0.035), front * Vector3(x, y, 0.14), Color(0.075, 0.105, 0.12), front.basis)
	var frame_color := Color(0.74, 0.71, 0.61)
	_box("trim", Vector3(0.065, height, 0.055), front * Vector3(x, y, 0.17), frame_color, front.basis)
	_box("trim", Vector3(width, 0.065, 0.055), front * Vector3(x, y + 0.12, 0.17), frame_color, front.basis)
	_box("stone", Vector3(width + 0.35, 0.12, 0.32), front * Vector3(x, y - height * 0.5 - 0.12, 0.12), Color(0.73, 0.7, 0.62), front.basis)
	for side: float in [-1.0, 1.0]:
		_box("wood", Vector3(width * 0.43, height + 0.06, 0.09), front * Vector3(x + side * width * 0.78, y, 0.1), shutters, front.basis)

func _gate(front: Transform3D, x: float, width: float, height: float, color: Color) -> void:
	_box("trim", Vector3(width + 0.24, height + 0.15, 0.10), front * Vector3(x, height * 0.5 + 0.42, 0.09), Color(0.10, 0.09, 0.07), front.basis)
	_box("wood", Vector3(width, height, 0.10), front * Vector3(x, height * 0.5 + 0.4, 0.15), color * 0.8, front.basis)
	if width > 2.0:
		_box("trim", Vector3(0.045, height, 0.02), front * Vector3(x, height * 0.5 + 0.4, 0.21), Color(0.075, 0.065, 0.05), front.basis)
		for side: float in [-1.0, 1.0]:
			var brace := front.basis * Basis(Vector3.FORWARD, side * atan2(height * 0.7, width * 0.42))
			_box("wood", Vector3(Vector2(width * 0.42, height * 0.7).length(), 0.13, 0.08), front * Vector3(x + side * width * 0.24, height * 0.5 + 0.4, 0.24), color * 0.55, brace)

func _roof(size: Vector2, height: float, rise: float, material: String, color: Color, wood: Color, gable: Color, timber_gable: bool) -> void:
	var half_width := size.y * 0.5
	var overhang := 0.65
	var pitch := atan2(rise, half_width)
	var run := half_width + overhang
	var edge_y := height - overhang * tan(pitch)
	var slope_length := run / cos(pitch)
	for side: float in [-1.0, 1.0]:
		var slope_basis := Basis(Vector3.RIGHT, side * pitch)
		var center := Vector3(0, (height + rise + edge_y) * 0.5, side * run * 0.5)
		_box("wood", Vector3(size.x + 1.05, 0.18, slope_length + 0.03), center - Vector3.UP * 0.10, wood * 0.4, slope_basis)
		_box(material, Vector3(size.x + 1.15, 0.10, slope_length), center, color, slope_basis)
		# Continuous gutter and overhanging fascia create a legible eave shadow line.
		_box("trim", Vector3(size.x + 1.2, 0.13, 0.15), Vector3(0, edge_y - 0.1, side * (run + 0.02)), Color(0.22, 0.22, 0.2))
		for end: float in [-1.0, 1.0]:
			_box("trim", Vector3(0.095, height - 0.45, 0.095), Vector3(end * (size.x * 0.5 - 0.25), (height + 0.45) * 0.5, side * (half_width + 0.1)), Color(0.3, 0.29, 0.25))
	_box(material, Vector3(size.x + 1.2, 0.16, 0.32), Vector3(0, height + rise + 0.08, 0), color * 0.85)
	for end: float in [-1.0, 1.0]:
		var x := end * size.x * 0.5
		_triangle("wood" if timber_gable else "plaster", [Vector3(x, height - 0.02, -half_width), Vector3(x, height - 0.02, half_width), Vector3(x, height + rise - 0.1, 0)], Vector3(end, 0, 0), gable * 0.85)

func _surface(material: String) -> SurfaceTool:
	var key := "%d_%d:%s" % [_cell.x, _cell.y, material]
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"surface": surface, "material": material, "origin": Vector3(_cell.x * CELL_SIZE, 0, _cell.y * CELL_SIZE)}
	return _batches[key].surface

func _box(material: String, size: Vector3, center: Vector3, color: Color, rotation: Basis = Basis.IDENTITY) -> void:
	var surface := _surface(material)
	var vertices: PackedVector3Array = _cube[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = _cube[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = _cube[Mesh.ARRAY_INDEX]
	var origin := Vector3(_cell.x * CELL_SIZE, 0, _cell.y * CELL_SIZE)
	for i in indices:
		var p := vertices[i] * size
		var n := normals[i]
		var uv := Vector2(p.x, p.y)
		if absf(n.y) > 0.5:
			uv = Vector2(p.x, p.z)
		elif absf(n.x) > 0.5:
			uv = Vector2(p.z, p.y)
		surface.set_uv(uv)
		surface.set_color(color)
		surface.set_normal(_frame.basis * rotation * n)
		surface.add_vertex(_frame * (rotation * p + center) - origin)

func _triangle(material: String, vertices: Array, normal: Vector3, color: Color) -> void:
	var surface := _surface(material)
	var origin := Vector3(_cell.x * CELL_SIZE, 0, _cell.y * CELL_SIZE)
	if (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).dot(normal) > 0.0:
		vertices = [vertices[0], vertices[2], vertices[1]]
	for p: Vector3 in vertices:
		surface.set_uv(Vector2(p.z, p.y))
		surface.set_color(color)
		surface.set_normal(_frame.basis * normal)
		surface.add_vertex(_frame * p - origin)
