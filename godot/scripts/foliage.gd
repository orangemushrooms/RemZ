# Visual building blocks: PBR materials from the texture folder, blended terrain shader,
# scattered ground leaves, wind-swayed grass, canopy cards, falling leaves, campfire.
class_name Foliage

const TEX := "res://assets/textures/"

static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

# StandardMaterial3D with albedo / normal / roughness / AO maps of a Poly Haven set
static func pbr(short: String, uv_scale: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(TEX + short + "_albedo.jpg")
	m.albedo_color = tint
	var n := _tex(TEX + short + "_normal.jpg")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 1.0
	var r := _tex(TEX + short + "_rough.jpg")
	if r:
		m.roughness_texture = r
	m.roughness = 1.0
	var ao := _tex(TEX + short + "_ao.jpg")
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# Terrain: forest floor / meadow / gravel blended by the fine map cover mask.
const TERRAIN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D litter_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D litter_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_rough : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_rough : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec3 grass_tint : source_color = vec3(0.52, 0.53, 0.33);
uniform vec3 leaf_tint : source_color = vec3(0.72, 0.64, 0.54);
uniform vec3 gravel_tint : source_color = vec3(0.46, 0.45, 0.42);
uniform float scale_grass = 0.22;
uniform float scale_leaf = 0.2;
uniform float scale_gravel = 0.55;
uniform sampler2D cover_map : filter_linear, repeat_disable;
uniform vec2 cover_origin;
uniform vec2 cover_size;
varying vec3 w;
varying vec2 wuv;
varying float vdist;
void vertex() {
	w = COLOR.rgb;
	// Asphalt is a separate ribbon; its mask leaves the terrain weights empty.
	// Keep a gravel bed underneath so exposed shoulders never become untextured,
	// zero-roughness patches at the edge of the ribbon.
	w.b += max(1.0 - (w.r + w.g + w.b), 0.0);
	wuv = VERTEX.xz;
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
vec3 tex2(sampler2D t, vec2 uv) {
	vec3 a = texture(t, uv).rgb;
	if (vdist > 45.0) {
		return a;
	}
	vec2 uv2 = vec2(uv.y, -uv.x) * 0.71 + vec2(13.7, 4.2);
	return mix(a, texture(t, uv2).rgb, 0.5);
}
void fragment() {
	// Exact world alignment, independent of the cover mask's resolution.
	vec2 cover_uv = (wuv - cover_origin) / cover_size + 0.5 / vec2(textureSize(cover_map, 0));
	vec3 cover = texture(cover_map, cover_uv).rgb;
	cover.b += max(1.0 - cover.r - cover.g - cover.b, 0.0);
	vec2 ug = wuv * scale_grass;
	vec2 ul = wuv * scale_leaf;
	vec2 uk = wuv * scale_gravel;
	// Most fragments belong to a single layer: skip the texture reads of the absent ones (up to 22 samples saved).
	bool has_l = cover.r > 0.02;
	bool has_g = cover.g > 0.02;
	bool has_k = cover.b > 0.02;
	vec3 la = vec3(0.4); vec3 ln = vec3(0.5, 0.5, 1.0); float lr = 1.0;
	vec3 ga = vec3(0.4); vec3 gn = vec3(0.5, 0.5, 1.0); float gr = 1.0;
	vec3 ka = vec3(0.5); vec3 kn = vec3(0.5, 0.5, 1.0); float kr = 1.0;
	if (has_l) {
		// forest floor: brown leaf litter with patches of the bare photo floor, slow large-scale darkening (soil, moss)
		float patch = sin(wuv.x * 0.11 + 1.3) * sin(wuv.y * 0.09 + 0.4) * 0.5 + 0.5;
		float dark = 0.75 + 0.25 * (sin(wuv.x * 0.05) * sin(wuv.y * 0.043 + 2.0) * 0.5 + 0.5);
		float pk = smoothstep(0.7, 0.95, patch);
		la = mix(tex2(litter_albedo, ul * 1.3) * vec3(0.9, 0.8, 0.65), tex2(leaf_albedo, ul) * leaf_tint, pk) * dark;
		ln = mix(tex2(litter_normal, ul * 1.3), tex2(leaf_normal, ul), pk);
		lr = texture(leaf_rough, ul).r;
	}
	if (has_g) {
		ga = tex2(grass_albedo, ug) * grass_tint;
		gn = tex2(grass_normal, ug);
		gr = texture(grass_rough, ug).r;
	}
	if (has_k) {
		// Compacted small gravel with irregular earthy wear, directly on the
		// terrain: no raised road slab or intersections between two surfaces.
		// Photographic soil variation avoids periodic waves in the road colour.
		vec3 soil = tex2(leaf_albedo, wuv * 0.32);
		float dirt = smoothstep(0.12, 0.48, dot(soil, vec3(0.333)));
		ka = mix(tex2(gravel_albedo, uk) * vec3(0.44,0.40,0.33), soil * vec3(0.37,0.29,0.20), 0.12 + dirt * 0.25);
		kn = tex2(gravel_normal, uk);
		kr = texture(gravel_rough, uk).r;
	}
	// sharpen the blend with the texture brightness so edges look natural
	vec3 ww = cover + vec3((la.r - 0.4) * 0.3, (ga.g - 0.4) * 0.3, (ka.r - 0.5) * 0.3);
	ww = max(ww - 0.15, vec3(0.0));
	ww = pow(ww, vec3(3.0));
	ww /= max(ww.r + ww.g + ww.b, 0.001);
	ALBEDO = la * ww.r + ga * ww.g + ka * ww.b;
	NORMAL_MAP = normalize(ln * ww.r + gn * ww.g + kn * ww.b);
	NORMAL_MAP_DEPTH = 0.35;
	ROUGHNESS = lr * ww.r + gr * ww.g + kr * ww.b;
}
"""

static func terrain_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("cover_map", load("res://assets/map/ground.png"))
	m.set_shader_parameter("cover_origin", Map.extent().position)
	m.set_shader_parameter("cover_size", Map.extent().size + Vector2.ONE)
	m.set_shader_parameter("litter_albedo", _tex(TEX + "leaves_albedo.jpg"))
	m.set_shader_parameter("litter_normal", _tex(TEX + "leaves_normal.jpg"))
	for pair in [["grass", "ph_meadow"], ["leaf", "ph_forestfloor"], ["gravel", "ph_gravel"]]:
		m.set_shader_parameter(pair[0] + "_albedo", _tex(TEX + pair[1] + "_albedo.jpg"))
		m.set_shader_parameter(pair[0] + "_normal", _tex(TEX + pair[1] + "_normal.jpg"))
		m.set_shader_parameter(pair[0] + "_rough", _tex(TEX + pair[1] + "_rough.jpg"))
	return m

# Instanced sprite shader: INSTANCE_CUSTOM.x = atlas cell, .y = brightness, .z = wind amount
const SPRITE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 cells = vec2(4.0, 2.0);
uniform float wind = 0.0;
uniform bool meadow_distance_thinning = false;
uniform vec3 tint : source_color = vec3(1.0);
varying float bright;
void vertex() {
	float cell = INSTANCE_CUSTOM.x;
	bright = INSTANCE_CUSTOM.y;
	vec2 c = vec2(mod(cell, cells.x), floor(cell / cells.x));
	UV = (UV + c) / cells;
	float sway = INSTANCE_CUSTOM.z * wind * (1.0 - UV.y * cells.y + floor(cell / cells.x));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.6 + wp.x * 0.35 + wp.z * 0.27;
	VERTEX.x += sin(t) * sway * 0.12;
	VERTEX.z += cos(t * 0.8) * sway * 0.08;
	if (meadow_distance_thinning) {
		// Keep the close field dense, but avoid drawing layers of sub-pixel blades behind it.
		float distance_to_camera = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
		float keep = mix(1.0, 0.22, smoothstep(10.0, 45.0, distance_to_camera));
		// A stable per-tuft rank and gradual shrinking avoid flicker or abrupt disappearance.
		VERTEX *= smoothstep(INSTANCE_CUSTOM.w - 0.055, INSTANCE_CUSTOM.w + 0.055, keep);
	}
}
void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * tint * bright * mix(1.0, 0.55, UV.y * cells.y - floor(UV.y * cells.y)) * (wind > 0.5 ? 1.0 : 1.0);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
"""

static func sprite_material(atlas_path: String, cells: Vector2, wind: float, tint: Color = Color.WHITE) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SPRITE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("atlas", load(atlas_path))
	m.set_shader_parameter("cells", cells)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m

static func _multimesh(mesh: Mesh, count: int, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# ---------------------------------------------------------------- ground cover
# Grass tufts, woodland grass, ferns and leaf litter come from fixed seeds, so every build of the map
# yields the very same instances. Placing them takes some two million terrain samples - 25 s in the
# editor, several seconds in the export, all of it on the main thread until September 2026, which
# froze the window long enough for Windows to offer "Programm schliessen" on every return to the
# menu. Now the first build of a run places them on a worker thread while the loading screen keeps
# drawing, and every later build ("Nochmal", "Hauptmenü", a new co-op round) reuses the finished
# MultiMeshes at once. Nothing edits these MultiMeshes after they are made, so sharing them is safe.
const COVER_CELL := 16.0
const LEAF_SEED := 4243          # leaf litter used the map's shared generator before; now its own
static var _cover: Array = []    # finished layers: {name, parent, category, material, cells: [[origin, MultiMesh]]}
static var _cover_specs: Array = []
static var _cover_result: Array = []
static var _cover_task := -1

# Starts placing the requested layers on a worker thread, once per run.
static func prepare_ground_cover(leaves: bool, grass: bool) -> void:
	if not _cover.is_empty() or _cover_task != -1 or not (leaves or grass): return
	# Meshes and materials are made here on the main thread; the worker only needs their bounds.
	var specs: Array = []
	if leaves:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.16)
		quad.orientation = PlaneMesh.FACE_Y
		specs.append({"layer": "leaves", "name": &"Leaves", "parent": "", "category": "leaves", "mesh": quad,
			"material": sprite_material("res://assets/sprites/leaves.png", Vector2(4, 2), 0.0, Color(0.7, 0.6, 0.5))})
	if grass:
		var meadow := sprite_material("res://assets/sprites/grass.png", Vector2(4, 1), 1.0, Color(0.5, 0.52, 0.3))
		meadow.set_shader_parameter("meadow_distance_thinning", true)
		specs.append({"layer": "meadow", "name": &"MeadowGrass", "parent": "", "category": "grass", "mesh": _tuft_mesh(0.82, 0.4), "material": meadow})
		specs.append({"layer": "woodland_grass", "name": &"WoodlandGrass", "parent": "ForestFloor", "category": "grass", "mesh": _tuft_mesh(0.7, 0.45),
			"material": sprite_material("res://assets/sprites/grass.png", Vector2(4, 1), 0.65, Color(0.62, 0.64, 0.4))})
		specs.append({"layer": "woodland_ferns", "name": &"WoodlandFerns", "parent": "ForestFloor", "category": "grass", "mesh": _tuft_mesh(1.25, 0.65),
			"material": sprite_material("res://assets/sprites/leaf_fern.png", Vector2.ONE, 0.55, Color(0.68, 0.75, 0.5))})
	for spec: Dictionary in specs: spec["bounds"] = (spec.mesh as Mesh).get_aabb()
	_cover_specs = specs
	var work: Array = []
	for spec: Dictionary in specs: work.append({"layer": spec.layer, "bounds": spec.bounds})
	_cover_task = WorkerThreadPool.add_task(_place_cover.bind(work), false, "Ground cover")

# True once the MultiMeshes exist; converts the worker's output the first time it is asked.
static func ground_cover_ready() -> bool:
	if not _cover.is_empty(): return true
	if _cover_task == -1 or not WorkerThreadPool.is_task_completed(_cover_task): return false
	_finish_cover()
	return true

# Blocks until the placement is done (leaving the scene while the worker still runs).
static func finish_ground_cover() -> void:
	if _cover_task != -1: _finish_cover()

static func _finish_cover() -> void:
	WorkerThreadPool.wait_for_task_completion(_cover_task)
	_cover_task = -1
	for i in _cover_specs.size():
		var spec: Dictionary = _cover_specs[i]
		var cells: Array = []
		for cell: Dictionary in _cover_result[i]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = spec.mesh
			mm.instance_count = cell.count
			mm.buffer = cell.buffer
			mm.custom_aabb = cell.aabb
			cells.append([cell.origin, mm])
		_cover.append({"name": spec.name, "parent": spec.parent, "category": spec.category, "material": spec.material, "cells": cells})
	_cover_result = []

# Fresh nodes for this scene around the shared MultiMeshes, one per 16 m cell so they still cull.
static func attach_ground_cover(scene: Node3D) -> void:
	var parents := {}
	for layer: Dictionary in _cover:
		var root := Node3D.new()
		root.name = layer.name
		for cell: Array in layer.cells:
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = cell[1]
			instance.material_override = layer.material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.position = cell[0]
			instance.add_to_group("render_" + str(layer.category))
			root.add_child(instance)
		if str(layer.parent).is_empty():
			scene.add_child(root)
			continue
		if not parents.has(layer.parent):
			var holder := Node3D.new()
			holder.name = layer.parent
			scene.add_child(holder)
			parents[layer.parent] = holder
		parents[layer.parent].add_child(root)

# ---- worker thread: plain data only, no nodes, no RenderingServer calls
static func _place_cover(work: Array) -> void:
	var result: Array = []
	var woodland: Array = []
	for job: Dictionary in work:
		var placed: Array
		match str(job.layer):
			"leaves": placed = _place_leaves(100000)
			"meadow": placed = _place_meadow()
			"woodland_grass":
				woodland = _place_woodland()
				placed = woodland[0]
			"woodland_ferns":
				if woodland.is_empty(): woodland = _place_woodland()
				placed = woodland[1]
		result.append(_pack_cells(placed[0], placed[1], job.bounds))
	_cover_result = result

# A whole-map MultiMesh cannot cull individual tufts: 16 m cells, each with a conservative bound for
# the shader's wind. MultiMesh buffer layout: the 3x4 transform row by row, then the custom data.
static func _pack_cells(transforms: Array[Transform3D], colors: Array[Color], mesh_bounds: AABB) -> Array:
	var cells := {}
	for i in transforms.size():
		var p := transforms[i].origin
		var cell := Vector2i(floori(p.x / COVER_CELL), floori(p.z / COVER_CELL))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(i)
	var packed: Array = []
	for cell: Vector2i in cells:
		var indices: Array = cells[cell]
		var origin := Vector3(cell.x * COVER_CELL, 0, cell.y * COVER_CELL)
		var buffer := PackedFloat32Array()
		buffer.resize(indices.size() * 16)
		var bounds := AABB()
		for i in indices.size():
			var t := transforms[indices[i]]
			t.origin -= origin
			var c := colors[indices[i]]
			var k := i * 16
			buffer[k] = t.basis.x.x; buffer[k + 1] = t.basis.y.x; buffer[k + 2] = t.basis.z.x; buffer[k + 3] = t.origin.x
			buffer[k + 4] = t.basis.x.y; buffer[k + 5] = t.basis.y.y; buffer[k + 6] = t.basis.z.y; buffer[k + 7] = t.origin.y
			buffer[k + 8] = t.basis.x.z; buffer[k + 9] = t.basis.y.z; buffer[k + 10] = t.basis.z.z; buffer[k + 11] = t.origin.z
			buffer[k + 12] = c.r; buffer[k + 13] = c.g; buffer[k + 14] = c.b; buffer[k + 15] = c.a
			var aabb := t * mesh_bounds
			bounds = aabb if i == 0 else bounds.merge(aabb)
		packed.append({"origin": origin, "count": indices.size(), "buffer": buffer, "aabb": bounds.grow(0.25)})
	return packed

# Roads buffered once instead of scanning every road segment for every tuft.
static func _road_buffers(margin: float) -> Array:
	var buffers: Array = []
	for road in Map.ROADS:
		for polygon in Geometry2D.offset_polyline(PackedVector2Array(road.pts), road.width * 0.5 + margin, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon:
				bounds = bounds.expand(point)
			buffers.append({"bounds": bounds, "polygon": polygon})
	return buffers

static func _by_road(point: Vector2, buffers: Array) -> bool:
	for buffer in buffers:
		if buffer.bounds.has_point(point) and Geometry2D.is_point_in_polygon(point, buffer.polygon):
			return true
	return false

# Flat leaves lying on the ground, thickest under the trees, thin on tracks and in clearings.
static func _place_leaves(count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = LEAF_SEED
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var x: float = rng.randf_range(-110.0, 110.0)
		var z: float = rng.randf_range(-120.0, 100.0)
		if rng.randf() > Map.leaf_weight(x, z) * 0.9 + 0.05:
			continue
		if Map.on_road(x, z) and rng.randf() > 0.25:
			continue
		if Map.in_building(x, z) or (Map.in_clearing(x, z) and rng.randf() > 0.45):
			continue
		var p := Map.ground_pos(x, z)
		var b := Basis().rotated(Vector3.UP, rng.randf() * TAU)
		b = b.rotated(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf() * 0.25)
		b = b.scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		transforms.append(Transform3D(b, p + Vector3(0, 0.015, 0)))
		colors.append(Color(float(rng.randi() % 8), rng.randf_range(0.7, 1.1), 0.0, 0.0))
		placed += 1
	return [transforms, colors]

static func _tuft_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var ang := k * PI / 3.0
		var dx := cos(ang) * w / 2.0
		var dz := sin(ang) * w / 2.0
		var verts := [Vector3(-dx, 0, -dz), Vector3(dx, 0, dz), Vector3(dx, h, dz), Vector3(-dx, h, -dz)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[idx])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[idx])
	return st.commit()

# Dense meadow cover: jittered spacing fills the gaps left by independent random clumps.
static func _place_meadow() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 34127
	var patches := FastNoiseLite.new()
	patches.seed = 34127
	patches.frequency = 0.06
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	# Include a border beyond the playable bounds so the field does not end at the player limit.
	var area := Map.BOUNDS.grow(20.0).intersection(Map.extent())
	var road_buffers := _road_buffers(0.7)
	var cornfield := preload("res://scripts/cornfield.gd")
	var spacing := 0.28
	for row in ceili(area.size.y / spacing):
		for column in ceili(area.size.x / spacing):
			var x := area.position.x + (column + rng.randf_range(0.12, 0.88)) * spacing
			var z := area.position.y + (row + rng.randf_range(0.12, 0.88)) * spacing
			var point := Vector2(x, z)
			if not area.has_point(point):
				continue
			if cornfield.field_ground(point): continue
			var cover := Map.meadow_weight(x, z)
			if cover < 0.5 or (cover < 0.85 and rng.randf() > cover):
				continue
			if Map.in_building(x, z, 0.8) or Map.in_clearing(x, z):
				continue
			if _by_road(point, road_buffers):
				continue
			if not Map.POND.is_empty() and point.distance_to(Map.POND.pos) < Map.POND.r + 1.0:
				continue
			var normal := Map.ground_normal(x, z)
			if normal.y < 0.72:
				continue
			var patch := clampf(patches.get_noise_2d(x, z) * 1.5 + 0.5, 0.0, 1.0)
			var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, rng.randf() * TAU)
			var width := rng.randf_range(0.9, 1.3)
			var height := rng.randf_range(0.7, 1.15) * lerpf(0.85, 1.15, patch)
			var pos := Map.ground_pos(x, z) - Vector3.UP * 0.025
			transforms.append(Transform3D(basis * Basis.from_scale(Vector3(width, height, width)), pos))
			colors.append(Color(float(rng.randi() % 4), rng.randf_range(0.75, 1.05), 1.0, rng.randf_range(0.0, 0.9)))
	return [transforms, colors]

# Low woodland cover across the playable map, including the approach to the hut.
# A jittered grid fills gaps; broad patches vary density, height and fern abundance.
# Its own seed leaves trees, pickups and the meadow distribution unchanged.
# Returns [[grass transforms, grass colours], [fern transforms, fern colours]].
static func _place_woodland() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 62017
	var patches := FastNoiseLite.new()
	patches.seed = 62017
	patches.frequency = 0.055
	var grasses: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var ferns: Array[Transform3D] = []
	var fern_colors: Array[Color] = []
	var area := Map.BOUNDS.intersection(Map.extent())
	var road_buffers := _road_buffers(0.7)
	var spacing := 0.65
	for row in ceili(area.size.y / spacing):
		for column in ceili(area.size.x / spacing):
			var x := area.position.x + (column + rng.randf_range(0.1, 0.9)) * spacing
			var z := area.position.y + (row + rng.randf_range(0.1, 0.9)) * spacing
			var cover := Map.leaf_weight(x, z)
			if cover < 0.6:
				continue
			var patch := clampf(patches.get_noise_2d(x, z) * 1.5 + 0.5, 0.0, 1.0)
			if rng.randf() > lerpf(0.62, 0.98, patch) * cover:
				continue
			if Map.in_building(x, z, 1.3) or Map.in_clearing(x, z):
				continue
			if _by_road(Vector2(x, z), road_buffers):
				continue
			if not Map.POND.is_empty() and Vector2(x, z).distance_to(Map.POND.pos) < Map.POND.r + 1.0:
				continue
			var normal := Map.ground_normal(x, z)
			if normal.y < 0.72:
				continue
			var pos := Map.ground_pos(x, z) - Vector3.UP * 0.035
			var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, rng.randf() * TAU)
			var width := rng.randf_range(1.15, 1.85)
			var height := rng.randf_range(0.6, 1.05) * lerpf(0.8, 1.15, patch)
			grasses.append(Transform3D(basis * Basis.from_scale(Vector3(width, height, width)), pos))
			grass_colors.append(Color(float(rng.randi() % 4), rng.randf_range(0.75, 1.15), 0.45, 0.0))
			if rng.randf() < lerpf(0.08, 0.35, patch):
				var size := rng.randf_range(0.65, 1.15)
				ferns.append(Transform3D(basis * Basis.from_scale(Vector3(size, size, size)), pos))
				fern_colors.append(Color(0.0, rng.randf_range(0.7, 1.1), 0.3, 0.0))
	return [[grasses, grass_colors], [ferns, fern_colors]]

# Foliage cards around tree crowns: crowns = Array of [Vector3 center, float radius]
static func canopy(crowns: Array, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var per := 5
	var mi := _multimesh(quad, crowns.size() * per, sprite_material("res://assets/sprites/canopy.png", Vector2(1, 1), 0.35, Color(1.0, 0.92, 0.8)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mm := mi.multimesh
	var i := 0
	for c in crowns:
		var center: Vector3 = c[0]
		var r: float = c[1]
		for k in per:
			var off := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.4), rng.randf_range(-0.5, 0.5)) * r
			var b := Basis().rotated(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
			b = b.scaled(Vector3.ONE * r * rng.randf_range(1.2, 1.8))
			mm.set_instance_transform(i, Transform3D(b, center + off))
			mm.set_instance_custom_data(i, Color(0.0, rng.randf_range(0.6, 1.05), 0.6, 0.0))
			i += 1
	return mi

# Slowly falling leaves in a box around the player area
static func falling_leaves(center: Vector3, extents: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = extents
	mat.direction = Vector3(0.3, -1.0, 0.1)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 0.9
	mat.gravity = Vector3(0, -0.35, 0)
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.angle_min = 0.0
	mat.angle_max = 360.0
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 1.2
	mat.turbulence_noise_scale = 2.5
	mat.scale_min = 0.6
	mat.scale_max = 1.2
	mat.anim_offset_min = 0.0
	mat.anim_offset_max = 1.0
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.16)
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://assets/sprites/leaves.png")
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sm.alpha_scissor_threshold = 0.45
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.particles_anim_h_frames = 4
	sm.particles_anim_v_frames = 2
	sm.particles_anim_loop = false
	sm.roughness = 0.9
	quad.material = sm
	p.draw_pass_1 = quad
	p.amount = 900
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.visibility_aabb = AABB(-extents * 1.2, extents * 2.4)
	p.position = center
	return p

# Campfire: flames, embers, smoke and a flickering light. Returns the root node; light is child "Light".
static func campfire(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	# stones ring
	var stone_mat := pbr("rock", 1.0, Color(0.7, 0.68, 0.62))
	for i in 9:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.24
		s.mesh = sm
		s.material_override = stone_mat
		var a := i / 9.0 * TAU
		s.position = Vector3(cos(a) * 0.7, 0.06, sin(a) * 0.7)
		s.scale = Vector3(1.0 + randf() * 0.4, 0.7, 1.0 + randf() * 0.4)
		root.add_child(s)
	# logs
	var log_mat := pbr("bark", 1.0)
	for i in 4:
		var l := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.08
		cm.height = 0.9
		l.mesh = cm
		l.material_override = log_mat
		l.rotation = Vector3(PI / 2.0 - 0.5, i * TAU / 4.0 + 0.3, 0)
		l.position = Vector3(0, 0.14, 0)
		root.add_child(l)
	# flames
	var fire := GPUParticles3D.new()
	var fm := ParticleProcessMaterial.new()
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 0.22
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 12.0
	fm.initial_velocity_min = 0.8
	fm.initial_velocity_max = 1.6
	fm.gravity = Vector3(0, 1.5, 0)
	fm.scale_min = 0.5
	fm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	fm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	grad.add_point(0.4, Color(1.0, 0.45, 0.08, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.6, 0.1, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	fm.color_ramp = gt
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 0.6
	fire.process_material = fm
	var fq := QuadMesh.new()
	fq.size = Vector2(0.5, 0.7)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fmat.vertex_color_use_as_albedo = true
	fmat.albedo_texture = _soft_dot()
	fq.material = fmat
	fire.draw_pass_1 = fq
	fire.add_to_group("day_night_flames")
	fire.amount = 140
	fire.lifetime = 0.9
	fire.position.y = 0.15
	root.add_child(fire)
	# Buoyant smoke: a slow, coherent plume with gentle drift and small eddies.
	# Avoid the old constant 0.5 m/s² lift, which accelerated puffs out of the fire.
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	var smm := ParticleProcessMaterial.new()
	smm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smm.emission_sphere_radius = 0.18
	smm.direction = Vector3(0.06, 1, 0.02)
	smm.spread = 7.0
	smm.initial_velocity_min = 0.38
	smm.initial_velocity_max = 0.58
	smm.gravity = Vector3(0.018, 0.045, 0.008)
	smm.damping_min = 0.035
	smm.damping_max = 0.055
	var speed := Curve.new()
	speed.add_point(Vector2(0, 0.7))
	speed.add_point(Vector2(0.45, 0.6))
	speed.add_point(Vector2(1, 0.45))
	var speed_texture := CurveTexture.new()
	speed_texture.curve = speed
	smm.velocity_limit_curve = speed_texture
	smm.angle_min = -180.0
	smm.angle_max = 180.0
	smm.angular_velocity_min = -3.0
	smm.angular_velocity_max = 3.0
	smm.scale_min = 0.85
	smm.scale_max = 1.25
	var ssc := Curve.new()
	ssc.max_value = 4.0
	ssc.add_point(Vector2(0, 0.35))
	ssc.add_point(Vector2(0.22, 1.0))
	ssc.add_point(Vector2(0.6, 2.2))
	ssc.add_point(Vector2(1, 3.4))
	var ssct := CurveTexture.new()
	ssct.curve = ssc
	smm.scale_curve = ssct
	var sg := Gradient.new()
	sg.set_color(0, Color(0.48, 0.46, 0.43, 0.0))
	sg.set_color(1, Color(0.59, 0.6, 0.61, 0.0))
	sg.add_point(0.08, Color(0.49, 0.48, 0.46, 0.16))
	sg.add_point(0.24, Color(0.53, 0.53, 0.52, 0.22))
	sg.add_point(0.55, Color(0.57, 0.58, 0.58, 0.12))
	sg.add_point(0.82, Color(0.59, 0.6, 0.61, 0.035))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	smm.color_ramp = sgt
	smm.turbulence_enabled = true
	smm.turbulence_noise_strength = 0.16
	smm.turbulence_noise_scale = 4.0
	smm.turbulence_noise_speed = Vector3(0.025, 0.018, 0.01)
	smm.turbulence_noise_speed_random = 0.0
	smm.turbulence_influence_min = 0.03
	smm.turbulence_influence_max = 0.06
	var eddies := Curve.new()
	eddies.add_point(Vector2(0, 0.0))
	eddies.add_point(Vector2(0.3, 0.4))
	eddies.add_point(Vector2(1, 1.0))
	var eddy_texture := CurveTexture.new()
	eddy_texture.curve = eddies
	smm.turbulence_influence_over_life = eddy_texture
	smoke.process_material = smm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.8, 0.8)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = _smoke_texture()
	smat.roughness = 1.0
	smat.metallic_specular = 0.0
	smat.proximity_fade_enabled = true
	smat.proximity_fade_distance = 0.6
	sq.material = smat
	smoke.draw_pass_1 = sq
	smoke.amount = 120
	smoke.lifetime = 10.0
	smoke.preprocess = 10.0
	smoke.fixed_fps = 30
	smoke.interpolate = true
	smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(11, 12, 10))
	smoke.position.y = 0.8
	root.add_child(smoke)
	# light
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 5.0
	light.omni_range = 16.0
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 1.5
	light.position.y = 0.7
	root.add_child(light)
	return root

static var _dot: ImageTexture
static var _smoke: ImageTexture

# Shared, softly broken-up density instead of a stack of identical round dots.
# Generated once; motion comes from the particles, so the texture never jitters.
static func _smoke_texture() -> ImageTexture:
	if _smoke:
		return _smoke
	var noise := FastNoiseLite.new()
	noise.seed = 2718
	noise.frequency = 0.055
	noise.fractal_octaves = 3
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var radius := Vector2(x - 63.5, y - 63.5).length() / 63.5
			var edge := 1.0 - smoothstep(0.15, 1.0, radius)
			var density := clampf(0.55 + noise.get_noise_2d(x, y) * 0.65, 0.15, 0.95)
			img.set_pixel(x, y, Color(1, 1, 1, edge * edge * density))
	img.generate_mipmaps()
	_smoke = ImageTexture.create_from_image(img)
	return _smoke

static func _soft_dot() -> ImageTexture:
	if _dot:
		return _dot
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dot = ImageTexture.create_from_image(img)
	return _dot
