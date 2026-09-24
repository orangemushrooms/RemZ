# Procedural trees for the Remetschwil forest: beech (Buche), oak (Eiche), spruce (Fichte).
# Trunks and branches are generated meshes with bark cut from the site photos, crowns are leaf cards in a
# MultiMesh with sphere-like fake normals. Everything is instanced per species variant and partitioned into cells.
class_name Trees

const SPECIES := {
	"beech":  { "height": 26.0, "radius": 0.36, "crown_r": 6.0, "crown_lo": 0.33, "cards": 40, "card": 4.8, "bark": ["ph_bark_beech", "ph_bark_beech2"], "tint": Color(0.42, 0.4, 0.37), "leaf": "leaf_beech", "shade": Vector2(0.85, 1.15) },
	"oak":    { "height": 22.0, "radius": 0.5, "crown_r": 7.5, "crown_lo": 0.28, "cards": 40, "card": 5.0, "bark": ["ph_bark_oak", "ph_bark_ivy"], "tint": Color(0.45, 0.4, 0.35), "leaf": "leaf_oak", "shade": Vector2(0.8, 1.1) },
	"spruce": { "height": 29.0, "radius": 0.32, "crown_r": 3.2, "crown_lo": 0.2, "cards": 36, "card": 3.4, "bark": ["ph_bark_oak"], "tint": Color(0.45, 0.34, 0.26), "leaf": "leaf_spruce", "shade": Vector2(0.7, 1.0) },
}
const VARIANTS := 5
const CELL := 48.0
# cells whose shadow casting follows the player (see update_shadows); [MultiMeshInstance3D, Vector2 centre, radius]
static var shadow_cells: Array = []

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float wind = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float autumn = 0.25;
varying vec3 ccenter;
varying float shade;
varying float treehash;
void vertex() {
	ccenter = INSTANCE_CUSTOM.xyz;
	shade = INSTANCE_CUSTOM.a;
	// one random number per tree (the crown centre is shared by all cards of a tree)
	treehash = fract(sin(dot(ccenter.xz, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.3 + wp.x * 0.21 + wp.z * 0.17;
	VERTEX.x += sin(t) * 0.07 * wind;
	VERTEX.z += cos(t * 0.9) * 0.05 * wind;
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// per-tree hue and value variation, plus a September touch of yellow on some trees
	vec3 col = c.rgb * tint;
	float h = treehash;
	col *= mix(vec3(0.86, 0.94, 0.82), vec3(1.1, 1.04, 0.92), h);
	float yellowing = smoothstep(0.55, 1.0, fract(h * 7.31)) * autumn;
	vec3 lum = vec3(dot(col, vec3(0.3, 0.59, 0.11)));
	col = mix(col, lum * vec3(1.55, 1.25, 0.55), yellowing);
	ALBEDO = col * shade;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(wpos - ccenter + vec3(0.0, 0.8, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	// sunlight through the leaf: the canopy glows when the sun is behind it
	BACKLIGHT = col * 0.55;
	AO = 0.55 + 0.45 * shade;
	AO_LIGHT_AFFECT = 0.5;
}
"""

# ---------------------------------------------------------------- meshes
static func _tube(st: SurfaceTool, pts: Array, radii: Array, segs: int, circ_tex: float, v0: float) -> void:
	var rings: Array = []
	var v := v0
	var prev_p: Vector3 = pts[0]
	for i in pts.size():
		var p: Vector3 = pts[i]
		var dir: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var fwd := side.cross(dir).normalized()
		v += p.distance_to(prev_p) / 5.0
		prev_p = p
		var ring: Array = []
		for k in segs + 1:
			var a := TAU * k / segs
			var n := side * cos(a) + fwd * sin(a)
			ring.append([p + n * radii[i], n, Vector2(float(k) / segs * TAU * radii[i] / circ_tex, v)])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in segs:
			var a: Array = rings[i][k]; var b: Array = rings[i][k + 1]
			var c: Array = rings[i + 1][k]; var d: Array = rings[i + 1][k + 1]
			for q in [a, c, b, b, c, d]:
				st.set_normal(q[1]); st.set_uv(q[2]); st.add_vertex(q[0])

static func _trunk_mesh(kind: String, rng: RandomNumberGenerator) -> ArrayMesh:
	var sp: Dictionary = SPECIES[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = sp["height"]
	var r0: float = sp["radius"]
	var lean := Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03))
	var pts: Array = []
	var radii: Array = []
	var n := 9
	var wobble := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	for i in n + 1:
		var t := float(i) / n
		var y := t * h
		var p := Vector3(0, y, 0) + lean * y + wobble * sin(t * PI)
		if i == 0:
			p.y = -0.7   # buried, root flare
		pts.append(p)
		var flare := 1.0 + 0.7 * maxf(0.0, 1.0 - y / 1.2)
		radii.append(r0 * flare * (1.0 - 0.82 * pow(t, 0.9 if kind == "spruce" else 0.7)))
	_tube(st, pts, radii, 10, 1.2, 0.0)
	# close the bottom so the trunk never shows as a hollow tube where the ground falls away
	var b0: Vector3 = pts[0]
	for k in 10:
		var a0 := TAU * k / 10
		var a1 := TAU * (k + 1) / 10
		var r: float = radii[0]
		for q in [b0, b0 + Vector3(sin(a1) * r, 0, cos(a1) * r), b0 + Vector3(sin(a0) * r, 0, cos(a0) * r)]:
			st.set_normal(Vector3.DOWN); st.set_uv(Vector2(q.x, q.z)); st.add_vertex(q)
	# branches
	var nb: int = 5 if kind != "spruce" else 0
	var lo: float = sp["crown_lo"]
	for b in nb:
		var t := lo + (1.0 - lo) * (0.05 + 0.75 * b / nb) + rng.randf_range(-0.03, 0.03)
		var base: Vector3 = pts[int(t * n)].lerp(pts[mini(int(t * n) + 1, n)], fmod(t * n, 1.0))
		var yaw := rng.randf() * TAU
		var up := rng.randf_range(0.35, 0.8) if kind == "beech" else rng.randf_range(0.15, 0.6)
		var dir := Vector3(cos(yaw), up, sin(yaw)).normalized()
		var len: float = sp["crown_r"] * rng.randf_range(0.7, 1.05) * (1.0 - 0.4 * t)
		var bp: Array = [base]
		var br: Array = [r0 * 0.55 * (1.0 - t)]
		for k in range(1, 4):
			var f := float(k) / 3.0
			bp.append(base + dir * len * f + Vector3(0, 0.35 * f * f, 0) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)) * f)
			br.append(br[0] * (1.0 - 0.85 * f))
		_tube(st, bp, br, 6, 1.2, rng.randf() * 3.0)
	if kind == "spruce":
		for b in 7:
			var t := 0.2 + 0.7 * b / 7.0
			var base: Vector3 = pts[int(t * n)].lerp(pts[mini(int(t * n) + 1, n)], fmod(t * n, 1.0))
			var yaw := rng.randf() * TAU
			var dir := Vector3(cos(yaw), -0.15, sin(yaw)).normalized()
			var len: float = sp["crown_r"] * (1.0 - 0.8 * t) * 1.1
			_tube(st, [base, base + dir * len], [r0 * 0.25 * (1.0 - t), 0.03], 5, 1.2, rng.randf())
	st.generate_tangents()
	return st.commit()

# Bark: photo albedo / normal / roughness with a forest-shade term. There is no GI, so without it the low
# sun turns every trunk in the forest interior into a white pillar; AO darkens ambient and direct light.
const BARK_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float shade = 0.4;
void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = max(texture(rough_tex, UV).r, 0.85);
	SPECULAR = 0.1;
	AO = shade;
	AO_LIGHT_AFFECT = 0.85;
}
"""
static var _bark_shader: Shader

static func _bark_material(tex: String, tint: Color, shade: float = 0.4) -> ShaderMaterial:
	if not _bark_shader:
		_bark_shader = Shader.new()
		_bark_shader.code = BARK_SHADER
	var m := ShaderMaterial.new()
	m.shader = _bark_shader
	m.set_shader_parameter("albedo_tex", Foliage._tex(Foliage.TEX + tex + "_albedo.jpg"))
	m.set_shader_parameter("normal_tex", Foliage._tex(Foliage.TEX + tex + "_normal.jpg"))
	m.set_shader_parameter("rough_tex", Foliage._tex(Foliage.TEX + tex + "_rough.jpg"))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("shade", shade)
	return m

# ---------------------------------------------------------------- crowns
static func _crown_cards(kind: String, scale: float, yaw: float, base: Vector3, rng: RandomNumberGenerator, out: Array, detail: float = 1.0) -> void:
	var sp: Dictionary = SPECIES[kind]
	var h: float = sp["height"] * scale
	var cr: float = sp["crown_r"] * scale
	var lo: float = sp["crown_lo"] * h
	# detail < 1: fewer but larger cards (distant border forest)
	var cards: int = maxi(6, int(sp["cards"] * clampf(scale, 0.7, 1.4) * detail))
	var card: float = sp["card"] * scale / sqrt(maxf(detail, 0.2))
	var center := base + Vector3(0, (lo + h) * 0.5, 0)
	var sh: Vector2 = sp["shade"]
	for i in cards:
		var p: Vector3
		var b: Basis
		if kind == "spruce":
			# cone: level t from bottom of the crown to the tip, radius shrinks upward
			var t := pow(rng.randf(), 0.8)
			var y := lo + (h - lo) * t
			var rr := cr * (1.0 - t) * rng.randf_range(0.5, 1.0)
			var a := rng.randf() * TAU
			p = base + Vector3(cos(a) * rr, y, sin(a) * rr)
			# tilted downward-hanging branch fans, plus some vertical ones
			b = Basis().rotated(Vector3.UP, a + PI / 2.0).rotated(Vector3(cos(a), 0, sin(a)).normalized(), rng.randf_range(-0.6, -0.2) if i % 3 else rng.randf_range(0.8, 1.4))
			b = b.scaled(Vector3(card * (1.0 - 0.5 * t) * 1.2, card * (1.0 - 0.5 * t), 1.0))
		else:
			# ellipsoid shell, denser towards the outside
			var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * pow(rng.randf(), 0.4)
			p = center + Vector3(v.x * cr, v.y * (h - lo) * 0.5, v.z * cr)
			b = Basis().rotated(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.9, 0.9))
			b = b.scaled(Vector3.ONE * card * rng.randf_range(0.8, 1.2))
		out.append([Transform3D(b, p), Color(center.x, center.y, center.z, rng.randf_range(sh.x, sh.y))])

static func _leaf_material(kind: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = LEAF_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", load("res://assets/sprites/%s.png" % SPECIES[kind]["leaf"]))
	m.set_shader_parameter("wind", 0.6 if kind == "spruce" else 1.0)
	m.set_shader_parameter("tint", Vector3(0.66, 0.74, 0.52))
	m.set_shader_parameter("autumn", 0.0 if kind == "spruce" else 0.3)
	return m

static func _multimesh_cells(mesh: Mesh, items: Array, mat: Material, near: Vector2, shadow_dist: float, shadows_only: bool = false) -> Node3D:
	var root := Node3D.new()
	var cells := {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var c := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		if not cells.has(c):
			cells[c] = []
		cells[c].append(it)
	for c: Vector2i in cells:
		var list: Array = cells[c]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		var origin := Vector3(c.x * CELL, 0, c.y * CELL)
		var bounds := AABB()
		for i in list.size():
			var t: Transform3D = list[i][0]
			t.origin -= origin
			mm.set_instance_transform(i, t)
			mm.set_instance_custom_data(i, list[i][1])
			var ab := t * mesh.get_aabb()
			bounds = ab if i == 0 else bounds.merge(ab)
		mm.custom_aabb = bounds.grow(1.0)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.position = origin
		var cell_center := Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)
		var on := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadows_only else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.cast_shadow = on if cell_center.distance_to(near) < shadow_dist else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shadow_dist > 0.0 and shadow_dist < 500.0:
			shadow_cells.append([mi, cell_center, shadow_dist, on])
		root.add_child(mi)
	return root

# Called by main every half second: only the cells near the player throw shadows. Cheaper than a fixed circle
# around the fire and it never leaves the player standing in a shadowless patch at the map edge.
static func update_shadows(at: Vector2, radius: float) -> void:
	var r2 := (radius + CELL * 0.71) * (radius + CELL * 0.71)
	for cell in shadow_cells:
		var mi: MultiMeshInstance3D = cell[0]
		if not is_instance_valid(mi):
			continue
		var want: int = cell[3] if (cell[1] as Vector2).distance_squared_to(at) < r2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.cast_shadow != want:
			mi.cast_shadow = want

# ---------------------------------------------------------------- build
# trees: [x, z, kind, scale, yaw_deg]; shrubs: [x, z, scale, yaw_deg]; near: the fire (shadow radius centre)
static func build(parent: Node3D, trees: Array, shrubs: Array, near: Vector2, rng: RandomNumberGenerator, with_collision: bool = true, detail: float = 1.0, shadow_radius: float = 110.0) -> Dictionary:
	var trunk_items := {}     # "kind:variant" -> Array of [Transform3D, Color]
	var leaf_items := {}      # kind -> Array
	var shadow_items := {}    # kind -> Array: coarse shadow-only proxy crowns (a third of the cards, larger)
	var meshes := {}
	var mats := {}
	var crowns: Array = []
	var colliders := StaticBody3D.new()
	colliders.collision_layer = 1
	colliders.add_to_group("navsource")
	for k in SPECIES:
		leaf_items[k] = []
		shadow_items[k] = []
		for v in VARIANTS:
			var r2 := RandomNumberGenerator.new()
			r2.seed = hash(k) + v * 7919
			meshes["%s:%d" % [k, v]] = _trunk_mesh(k, r2)
			trunk_items["%s:%d" % [k, v]] = []
			var barks: Array = SPECIES[k]["bark"]
			mats["%s:%d" % [k, v]] = _bark_material(barks[v % barks.size()], SPECIES[k]["tint"])
	for t in trees:
		if Vector2(t[0], t[1]).distance_to(SecretNight.SITE) < 21.0: continue
		var kind: String = t[2]
		var s: float = t[3]
		var yaw := deg_to_rad(float(t[4]))
		var pos := Map.ground_pos(t[0], t[1])
		var v := rng.randi() % VARIANTS
		var b := Basis().rotated(Vector3.UP, yaw).scaled(Vector3.ONE * s)
		trunk_items["%s:%d" % [kind, v]].append([Transform3D(b, pos), Color.WHITE])
		_crown_cards(kind, s, yaw, pos, rng, leaf_items[kind], detail)
		if shadow_radius > 0.0:
			_crown_cards(kind, s, yaw, pos, rng, shadow_items[kind], 0.35)
		crowns.append([pos + Vector3(0, SPECIES[kind]["height"] * s * 0.7, 0), SPECIES[kind]["crown_r"] * s])
		if with_collision:
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = SPECIES[kind]["radius"] * s * 1.15 + 0.1
			cyl.height = 8.0
			cs.shape = cyl
			cs.position = pos + Vector3(0, 3.5, 0)
			colliders.add_child(cs)
	# shrubs: low clusters of beech cards (young beeches, brambles at the forest edges)
	for sh in shrubs:
		if Vector2(sh[0], sh[1]).distance_to(SecretNight.SITE) < 21.0: continue
		var pos := Map.ground_pos(sh[0], sh[1])
		var s: float = sh[2]
		var center := pos + Vector3(0, 0.9 * s, 0)
		for i in 5:
			var p := center + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.5, 0.6), rng.randf_range(-0.8, 0.8)) * s
			var b := Basis().rotated(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.7, 0.7)).scaled(Vector3.ONE * 1.5 * s)
			leaf_items["beech"].append([Transform3D(b, p), Color(center.x, center.y, center.z, rng.randf_range(0.45, 0.75))])
	var flags := OS.get_cmdline_user_args()
	for key in trunk_items:
		if trunk_items[key].is_empty() or "--no-trunks" in flags:
			continue
		parent.add_child(_multimesh_cells(meshes[key], trunk_items[key], mats[key], near, shadow_radius + 20.0))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for k in SPECIES:
		if leaf_items[k].is_empty() or "--no-crowns" in flags:
			continue
		# the visible crowns never enter the shadow pass; the coarse proxies below cast the (soft) crown shadows
		parent.add_child(_multimesh_cells(quad, leaf_items[k], _leaf_material(k), near, 0.0))
		if not shadow_items[k].is_empty() and not "--no-crown-shadows" in flags:
			parent.add_child(_multimesh_cells(quad, shadow_items[k], _leaf_material(k), near, shadow_radius, true))
	if with_collision:
		parent.add_child(colliders)
	return { "crowns": crowns }

# understory: ferns as three crossed cards, dead branches as thin bark tubes lying on the ground
static func understory(parent: Node3D, ferns: Array, logs: Array, near: Vector2, rng: RandomNumberGenerator) -> void:
	var items: Array = []
	for f in ferns:
		if Vector2(f[0], f[1]).distance_to(SecretNight.SITE) < 21.0: continue
		var pos := Map.ground_pos(f[0], f[1])
		var s: float = f[2]
		for k in 3:
			var b := Basis().rotated(Vector3.UP, deg_to_rad(float(f[3])) + k * PI / 3.0).scaled(Vector3(1.1 * s, 0.75 * s, 1.0))
			items.append([Transform3D(b, pos + Vector3(0, 0.36 * s, 0)), Color(pos.x, pos.y - 0.5, pos.z, rng.randf_range(0.7, 1.0))])
	if not items.is_empty():
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var sh := Shader.new()
		sh.code = LEAF_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tex", load("res://assets/sprites/leaf_fern.png"))
		m.set_shader_parameter("wind", 0.4)
		m.set_shader_parameter("tint", Vector3(0.7, 0.8, 0.5))
		parent.add_child(_multimesh_cells(quad, items, m, near, 90.0))
	var log_items: Array = []
	for l in logs:
		if Vector2(l[0], l[1]).distance_to(SecretNight.SITE) < 21.0: continue
		var pos := Map.ground_pos(l[0], l[1])
		var len: float = l[2]
		var b := Basis().rotated(Vector3.UP, deg_to_rad(float(l[3]))).rotated(Vector3.RIGHT, rng.randf_range(-0.06, 0.06)).scaled(Vector3(len, 1.0, 1.0))
		log_items.append([Transform3D(b, pos + Vector3(0, 0.1, 0)), Color.WHITE])
	if not log_items.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tube(st, [Vector3(-0.5, 0, 0), Vector3(0, 0.02, 0), Vector3(0.5, 0, 0)], [0.09, 0.12, 0.07], 7, 1.2, 0.0)
		st.generate_tangents()
		parent.add_child(_multimesh_cells(st.commit(), log_items, _bark_material("ph_bark_oak", Color(0.45, 0.4, 0.35)), near, 80.0))

# a single hero tree with its own collider (the landmark oak)
static func hero(parent: Node3D, kind: String, x: float, z: float, scale: float, yaw: float, rng: RandomNumberGenerator) -> void:
	var pos := Map.ground_pos(x, z)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 991
	var mi := MeshInstance3D.new()
	mi.mesh = _trunk_mesh(kind, r2)
	mi.material_override = _bark_material(SPECIES[kind]["bark"][0], SPECIES[kind]["tint"], 0.7)
	mi.position = pos
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * scale
	parent.add_child(mi)
	var items: Array = []
	_crown_cards(kind, scale, yaw, pos, rng, items)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	parent.add_child(_multimesh_cells(quad, items, _leaf_material(kind), Vector2(x, z), 1000.0))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = SPECIES[kind]["radius"] * scale * 1.2
	cyl.height = 8.0
	cs.shape = cyl
	cs.position = pos + Vector3(0, 3.5, 0)
	body.add_child(cs)
	body.add_to_group("navsource")
	parent.add_child(body)
