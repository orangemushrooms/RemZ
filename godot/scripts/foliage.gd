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

# Terrain: forest floor / meadow / gravel blended by the vertex colour (r, g, b) from the map's cover mask
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
uniform vec3 grass_tint : source_color = vec3(0.55, 0.62, 0.38);
uniform vec3 leaf_tint : source_color = vec3(0.72, 0.64, 0.54);
uniform vec3 gravel_tint : source_color = vec3(0.46, 0.45, 0.42);
uniform float scale_grass = 0.22;
uniform float scale_leaf = 0.2;
uniform float scale_gravel = 0.2;
varying vec3 w;
varying vec2 wuv;
void vertex() {
	w = COLOR.rgb;
	wuv = VERTEX.xz;
}
vec3 tex2(sampler2D t, vec2 uv) {
	vec2 uv2 = vec2(uv.y, -uv.x) * 0.71 + vec2(13.7, 4.2);
	return mix(texture(t, uv).rgb, texture(t, uv2).rgb, 0.5);
}
void fragment() {
	vec2 ug = wuv * scale_grass;
	vec2 ul = wuv * scale_leaf;
	vec2 uk = wuv * scale_gravel;
	// forest floor: brown leaf litter with patches of the bare photo floor, slow large-scale darkening (soil, moss)
	float patch = sin(wuv.x * 0.11 + 1.3) * sin(wuv.y * 0.09 + 0.4) * 0.5 + 0.5;
	float dark = 0.75 + 0.25 * (sin(wuv.x * 0.05) * sin(wuv.y * 0.043 + 2.0) * 0.5 + 0.5);
	vec3 la = mix(tex2(litter_albedo, ul * 1.3) * vec3(0.9, 0.8, 0.65), tex2(leaf_albedo, ul) * leaf_tint, smoothstep(0.7, 0.95, patch)) * dark;
	vec3 ln = mix(tex2(litter_normal, ul * 1.3), tex2(leaf_normal, ul), smoothstep(0.7, 0.95, patch));
	vec3 ga = tex2(grass_albedo, ug) * grass_tint;
	vec3 gn = tex2(grass_normal, ug);
	// worn gravel: low-frequency brown dirt patches and slightly lighter compacted lanes
	float wear = sin(wuv.x * 0.23 + 0.7) * sin(wuv.y * 0.19 + 1.9) * 0.5 + 0.5;
	float fine = sin(wuv.x * 1.7) * sin(wuv.y * 1.3) * 0.5 + 0.5;
	vec3 ka = mix(tex2(gravel_albedo, uk) * gravel_tint, tex2(litter_albedo, uk * 1.5) * vec3(0.55, 0.47, 0.38), smoothstep(0.62, 0.9, wear * 0.8 + fine * 0.2));
	vec3 kn = tex2(gravel_normal, uk);
	// sharpen the blend with the texture brightness so edges look natural
	vec3 ww = w + vec3((la.r - 0.4) * 0.3, (ga.g - 0.4) * 0.3, (ka.r - 0.5) * 0.3);
	ww = max(ww - 0.15, vec3(0.0));
	ww = pow(ww, vec3(3.0));
	ww /= max(ww.r + ww.g + ww.b, 0.001);
	ALBEDO = la * ww.r + ga * ww.g + ka * ww.b;
	NORMAL_MAP = normalize(ln * ww.r + gn * ww.g + kn * ww.b);
	NORMAL_MAP_DEPTH = 0.35;
	ROUGHNESS = texture(leaf_rough, ul).r * ww.r + texture(grass_rough, ug).r * ww.g + texture(gravel_rough, uk).r * ww.b;
}
"""

static func terrain_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
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

# A whole-map MultiMesh cannot cull individual tufts. Partition the generated
# transforms into local cells, including a conservative bound for shader wind.
static func _partition(mesh: Mesh, material: Material, transforms: Array[Transform3D], colors: Array[Color], category: String) -> Node3D:
	var root := Node3D.new()
	root.name = category.capitalize()
	var cells := {}
	for i in transforms.size():
		var p := transforms[i].origin
		var cell := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(i)
	for cell: Vector2i in cells:
		var indices: Array = cells[cell]
		var instance := _multimesh(mesh, indices.size(), material)
		instance.position = Vector3(cell.x * 16.0, 0, cell.y * 16.0)
		instance.add_to_group("render_" + category)
		var bounds := AABB()
		for i in indices.size():
			var transform := transforms[indices[i]]
			transform.origin -= instance.position
			instance.multimesh.set_instance_transform(i, transform)
			instance.multimesh.set_instance_custom_data(i, colors[indices[i]])
			var aabb := transform * mesh.get_aabb()
			bounds = aabb if i == 0 else bounds.merge(aabb)
		instance.multimesh.custom_aabb = bounds.grow(0.25)
		root.add_child(instance)
	return root

# Flat leaves lying on the ground. sampler(rng) -> Vector3 position or null
static func ground_leaves(count: int, sampler: Callable, rng: RandomNumberGenerator) -> Node3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.16)
	quad.orientation = PlaneMesh.FACE_Y
	var material := sprite_material("res://assets/sprites/leaves.png", Vector2(4, 2), 0.0, Color(0.7, 0.6, 0.5))
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var p = sampler.call(rng)
		if p == null:
			continue
		var b := Basis().rotated(Vector3.UP, rng.randf() * TAU)
		b = b.rotated(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf() * 0.25)
		b = b.scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		transforms.append(Transform3D(b, p + Vector3(0, 0.015, 0)))
		colors.append(Color(float(rng.randi() % 8), rng.randf_range(0.7, 1.1), 0.0, 0.0))
		placed += 1
	return _partition(quad, material, transforms, colors, "leaves")

# Crossed grass tufts with wind sway
static func grass(count: int, sampler: Callable, rng: RandomNumberGenerator) -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.45
	var w := 0.7
	for k in 3:
		var ang := k * PI / 3.0
		var dx := cos(ang) * w / 2.0
		var dz := sin(ang) * w / 2.0
		var base := st.get_primitive_type()
		var verts := [Vector3(-dx, 0, -dz), Vector3(dx, 0, dz), Vector3(dx, h, dz), Vector3(-dx, h, -dz)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[idx])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[idx])
	var mesh := st.commit()
	var material := sprite_material("res://assets/sprites/grass.png", Vector2(4, 1), 1.0, Color(0.55, 0.68, 0.32))
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var p = sampler.call(rng)
		if p == null:
			continue
		var b := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.7, 1.3), rng.randf_range(0.8, 1.4)))
		transforms.append(Transform3D(b, p))
		colors.append(Color(float(rng.randi() % 4), rng.randf_range(0.75, 1.1), 1.0, 0.0))
		placed += 1
	return _partition(mesh, material, transforms, colors, "grass")

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
	# smoke
	var smoke := GPUParticles3D.new()
	var smm := ParticleProcessMaterial.new()
	smm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smm.emission_sphere_radius = 0.2
	smm.direction = Vector3(0.2, 1, 0)
	smm.spread = 15.0
	smm.initial_velocity_min = 0.5
	smm.initial_velocity_max = 0.9
	smm.gravity = Vector3(0.15, 0.5, 0.05)
	smm.scale_min = 0.8
	smm.scale_max = 1.6
	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.3))
	ssc.add_point(Vector2(1, 2.5))
	var ssct := CurveTexture.new()
	ssct.curve = ssc
	smm.scale_curve = ssct
	var sg := Gradient.new()
	sg.set_color(0, Color(0.5, 0.45, 0.4, 0.35))
	sg.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	smm.color_ramp = sgt
	smm.turbulence_enabled = true
	smm.turbulence_noise_strength = 0.8
	smoke.process_material = smm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.8, 0.8)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = _soft_dot()
	sq.material = smat
	smoke.draw_pass_1 = sq
	smoke.amount = 90
	smoke.lifetime = 6.0
	smoke.preprocess = 6.0
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
