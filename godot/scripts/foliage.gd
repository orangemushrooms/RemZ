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

# Terrain: leaf litter (weight from vertex COLOR.r) blended over meadow grass
const TERRAIN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_rough : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D leaf_ao : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec3 grass_tint : source_color = vec3(0.95, 0.9, 0.6);
uniform vec3 leaf_tint : source_color = vec3(1.1, 0.9, 0.7);
uniform float scale_grass = 0.35;
uniform float scale_leaf = 0.5;
varying float w;
varying vec2 wuv;
void vertex() {
	w = COLOR.r;
	wuv = VERTEX.xz;
}
void fragment() {
	vec2 ug = wuv * scale_grass;
	vec2 ul = wuv * scale_leaf;
	// break tiling with a second rotated sample
	vec2 ul2 = vec2(ul.y, -ul.x) * 0.71 + vec2(13.7, 4.2);
	vec3 la = mix(texture(leaf_albedo, ul).rgb, texture(leaf_albedo, ul2).rgb, 0.5) * leaf_tint;
	vec3 ln = mix(texture(leaf_normal, ul).rgb, texture(leaf_normal, ul2).rgb, 0.5);
	float lr = texture(leaf_rough, ul).r;
	float lao = texture(leaf_ao, ul).r;
	vec3 ga = texture(grass_albedo, ug).rgb * grass_tint;
	vec3 gn = texture(grass_normal, ug).rgb;
	float gr = texture(grass_rough, ug).r;
	float k = smoothstep(0.35, 0.65, w + (la.r - 0.35) * 0.4);
	ALBEDO = mix(ga, la, k);
	NORMAL_MAP = mix(gn, ln, k);
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = mix(gr, lr, k);
	AO = mix(1.0, lao, k);
	AO_LIGHT_AFFECT = 0.6;
}
"""

static func terrain_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("grass_albedo", _tex(TEX + "grass_albedo.jpg"))
	m.set_shader_parameter("grass_normal", _tex(TEX + "grass_normal.jpg"))
	m.set_shader_parameter("grass_rough", _tex(TEX + "grass_rough.jpg"))
	m.set_shader_parameter("leaf_albedo", _tex(TEX + "leaves_albedo.jpg"))
	m.set_shader_parameter("leaf_normal", _tex(TEX + "leaves_normal.jpg"))
	m.set_shader_parameter("leaf_rough", _tex(TEX + "leaves_rough.jpg"))
	m.set_shader_parameter("leaf_ao", _tex(TEX + "leaves_ao.jpg"))
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

# Flat leaves lying on the ground. sampler(rng) -> Vector3 position or null
static func ground_leaves(count: int, sampler: Callable, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.16)
	quad.orientation = PlaneMesh.FACE_Y
	var mi := _multimesh(quad, count, sprite_material("res://assets/sprites/leaves.png", Vector2(4, 2), 0.0, Color(1.0, 0.95, 0.85)))
	var mm := mi.multimesh
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
		mm.set_instance_transform(placed, Transform3D(b, p + Vector3(0, 0.015, 0)))
		mm.set_instance_custom_data(placed, Color(float(rng.randi() % 8), rng.randf_range(0.7, 1.1), 0.0, 0.0))
		placed += 1
	mm.visible_instance_count = placed
	return mi

# Crossed grass tufts with wind sway
static func grass(count: int, sampler: Callable, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.55
	var w := 0.5
	for k in 2:
		var ang := k * PI / 2.0
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
	var mi := _multimesh(mesh, count, sprite_material("res://assets/sprites/grass.png", Vector2(4, 1), 1.0, Color(1.0, 0.9, 0.55)))
	var mm := mi.multimesh
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var p = sampler.call(rng)
		if p == null:
			continue
		var b := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.7, 1.3), rng.randf_range(0.8, 1.4)))
		mm.set_instance_transform(placed, Transform3D(b, p))
		mm.set_instance_custom_data(placed, Color(float(rng.randi() % 4), rng.randf_range(0.75, 1.1), 1.0, 0.0))
		placed += 1
	mm.visible_instance_count = placed
	return mi

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
