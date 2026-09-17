# Builds the Waldhütte Remetschwil level from Map (assets/map, generated from geodata) and wires
# player / weapons / zombies / waves / HUD.
extends Node3D

var player: Player
var hud: Hud
var weapons: Weapons
var waves: Waves
var skills: Skills
var ambience: Ambience
var music: Music
var zombies_root: Node3D
var barricades: Array = []
var loots: Array = []
var nav_region: NavigationRegion3D
var fire_light: OmniLight3D
var started := false
var over := false
var near_bar = null
var rng := RandomNumberGenerator.new()
var _autotest := false
var _shot_t := 0.0
var _shot_i := 0
var _spawned_test := false
var _shooting := false
var _flags: PackedStringArray = []
var _fps_frames := 0
var _fps_time := 0.0
var _fps_done := false
var settings: GameSettings
var navigation_ready := false
var _alive_count := 0
var render_stats := {}

func _ready() -> void:
	rng.seed = 4242
	_autotest = "--autotest" in OS.get_cmdline_user_args()
	_flags = OS.get_cmdline_user_args()
	settings = GameSettings.new()
	add_child(settings)
	Map._ensure()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = "navsource"
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.5
	nm.cell_height = 0.2
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, nm.cell_height)
	var walkable := Map.BOUNDS.grow(4.0)
	nm.filter_baking_aabb = AABB(Vector3(walkable.position.x, -100, walkable.position.y), Vector3(walkable.size.x, 220, walkable.size.y))
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	_build_terrain()
	_build_roads()
	_build_forests()
	_build_buildings()
	_build_campsite()
	_build_fence()
	_build_clutter()
	_build_foliage()
	render_stats = RenderOptimizer.optimize(self)
	print("RENDER_OPTIMIZER ", render_stats)

	hud = Hud.new()
	add_child(hud)
	hud.start_pressed.connect(_on_start)
	player = Player.new()
	player.hud = hud
	add_child(player)
	player.global_position = Map.ground_pos(Map.PLAYER_START.x, Map.PLAYER_START.y) + Vector3(0, 0.3, 0)
	player.flashlight.visible = false
	player.died.connect(_game_over)
	zombies_root = Node3D.new()
	add_child(zombies_root)
	hud.minimap.setup(player, self)
	weapons = Weapons.new()
	add_child(weapons)
	weapons.setup(player, hud, zombies_root)
	for s in Map.BARRICADES:
		var b := Barricade.new()
		b.setup(s, hud)
		add_child(b)
		barricades.append(b)
	waves = Waves.new()
	add_child(waves)
	waves.setup(self, hud, player, weapons)
	skills = Skills.new()
	add_child(skills)
	skills.setup(player, weapons, hud, self)
	ambience = Ambience.new()
	add_child(ambience)
	ambience.setup(player, Map.ground_pos(Map.FIRE.x, Map.FIRE.y), Map.ground_pos(-40.0, -60.0))
	music = Music.new()
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	if not "--no-music" in _flags:
		music.play("title")
	_spawn_deer()
	settings.add_controls(hud.overlay_content)
	settings.apply()
	for sound in ["pistol", "revolver", "smg", "ak47", "shotgun", "reload", "empty", "hit", "hurt", "growl", "build", "wave", "wood", "boom", "pickup"]:
		Sfx.get_stream(sound)
	Zombie.preload_models()
	hud.show_overlay("WALDHÜTTE REMETSCHWIL", "Die Waldhütte am Heitersberg ist der letzte sichere Ort. Die Zombies kommen von der Sennhofstrasse über den Weg zur Hütte, von der Wiese, über den Weg Richtung Dorf und den Waldweg aus dem Norden. Halte die Barrikaden, überlebe die Wellen.", "Spiel starten", "Wegnetz wird berechnet ...")
	hud.overlay_button.disabled = true
	nav_region.bake_finished.connect(_navigation_baked)
	nav_region.bake_navigation_mesh(true)
	get_tree().paused = true

func _navigation_baked() -> void:
	navigation_ready = true
	hud.overlay_button.disabled = false
	hud.overlay_status.text = "Bereit."
	if _autotest or "--benchmark" in _flags:
		_on_start()

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.55, 0.65, 0.8)
	sm.sky_horizon_color = Color(0.95, 0.88, 0.75)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.3, 0.28, 0.22)
	sm.ground_horizon_color = Color(0.8, 0.7, 0.55)
	sm.sun_angle_max = 30.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.ssao_enabled = not "--no-ssao" in _flags
	env.ssao_intensity = 2.0
	env.ssao_radius = 1.2
	env.ssil_enabled = not "--no-ssil" in _flags
	env.ssil_intensity = 1.6
	env.ssil_radius = 6.0
	env.sdfgi_enabled = false  # leaks light through thin leaf cards and burns them white
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.75, 0.75, 0.7)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.6
	env.volumetric_fog_enabled = not "--no-vfog" in _flags
	env.volumetric_fog_density = 0.0025
	env.volumetric_fog_albedo = Color(0.7, 0.7, 0.66)
	env.volumetric_fog_emission = Color(0.8, 0.65, 0.45)
	env.volumetric_fog_emission_energy = 0.02
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_ambient_inject = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# low late-afternoon sun from the south-west (the open valley side), as in the photos
	var sun := DirectionalLight3D.new()
	settings.env = env
	settings.sun = sun
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 2.5
	sun.shadow_enabled = not "--no-shadows" in _flags
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.5
	sun.shadow_blur = 1.5
	sun.light_volumetric_fog_energy = 0.8
	add_child(sun)
	sun.look_at_from_position(Vector3(-90, 55, 110), Vector3(0, 0, 0))
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.7, 0.72, 0.78)
	fill.light_energy = 0.7
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3(60, 40, -60), Vector3(0, 0, 0))

# ---------------------------------------------------------------- terrain
func _build_terrain() -> void:
	var ext := Map.extent()
	var w := int(ext.size.x) + 1
	var d := int(ext.size.y) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize(w * d)
	for j in d:
		for i in w:
			var x := ext.position.x + i
			var z := ext.position.y + j
			var h := Map.ground_height(x, z)
			heights[j * w + i] = h
			st.set_uv(Vector2(x, z))
			st.set_color(Map.cover(x, z))
			st.set_normal(Map.ground_normal(x, z))
			st.add_vertex(Vector3(x, h, z))
	for j in d - 1:
		for i in w - 1:
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var e := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(e); st.add_index(c)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Foliage.terrain_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # otherwise it shadows the roads lying 4 cm above it
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.add_to_group("navsource")
	var cs := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = d
	shape.map_data = heights
	cs.shape = shape
	cs.position = Vector3(ext.position.x + (w - 1) / 2.0, 0, ext.position.y + (d - 1) / 2.0)
	body.add_child(cs)
	add_child(body)

# road ribbon along a polyline
func _road_mesh(pts: Array, width: float, lift: float, mat: Material, fade: bool = true) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples: Array = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		var steps := maxi(1, int(len / 1.5))
		for k in steps + (1 if i == pts.size() - 2 else 0):
			var t := float(k) / steps
			var p := a.lerp(b, t)
			var dir := (b - a).normalized()
			samples.append([p, Vector2(-dir.y, dir.x)])
	var vi := 0
	var dist := 0.0
	var total := 0.0
	for i in samples.size() - 1:
		total += (samples[i][0] as Vector2).distance_to(samples[i + 1][0])
	var prev: Vector2 = samples[0][0]
	for s in samples:
		var p: Vector2 = s[0]
		var nrm: Vector2 = s[1]
		dist += p.distance_to(prev)
		prev = p
		# fade the ribbon in and out over 6 m so it merges with the gravel of the clearing / the forest floor
		var opacity := 1.0 if not fade else clampf(minf(dist, total - dist) / 6.0, 0.0, 1.0)
		for side: float in [-1.0, 1.0]:
			var q: Vector2 = p + nrm * side * width / 2.0
			st.set_uv(Vector2((0.5 + side * 0.5) * width / 5.0, dist / 5.0))
			st.set_color(Color(1, 1, 1, opacity))
			st.set_normal(Map.ground_normal(q.x, q.y))
			st.add_vertex(Vector3(q.x, Map.ground_height(q.x, q.y) + lift, q.y))
		if vi > 0:
			var a := (vi - 1) * 2
			st.add_index(a); st.add_index(a + 2); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(a + 2); st.add_index(a + 3)
		vi += 1
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a flat ribbon on the ground only shadows itself
	add_child(mi)

func _build_roads() -> void:
	var asphalt := Foliage.pbr("ph_asphalt", 1.0, Color(0.9, 0.9, 0.9))
	var gravel := Foliage.pbr("ph_gravel", 1.0, Color(0.6, 0.57, 0.52))   # same tint as the terrain gravel
	var dirt := Foliage.pbr("ph_gravel", 1.0, Color(0.5, 0.45, 0.38))
	for m in [asphalt, gravel, dirt]:
		m.normal_scale = 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		m.uv1_scale = Vector3(1.0, 1.0, 1.0)
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = 1
	for r in Map.ROADS:
		var mat: Material = { "asphalt": asphalt, "gravel": gravel, "dirt": dirt }[r["surface"]]
		_road_mesh(r["pts"], r["width"], 0.04 if r["surface"] != "dirt" else 0.03, mat, r["surface"] != "asphalt")

# ---------------------------------------------------------------- models
var _scenes := {}
var _tree_scenes := {}

func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var path := "res://assets/models/%s.glb" % name
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[name]

func _tree_scene(name: String) -> PackedScene:
	if not _tree_scenes.has(name):
		var path := "res://assets/trees/%s.glb" % name
		_tree_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	return _tree_scenes[name]

static func _prep_foliage_materials(node: Node3D) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				var bm: BaseMaterial3D = mat
				if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.albedo_texture and bm.albedo_texture.has_alpha():
					bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					bm.alpha_scissor_threshold = 0.4
					bm.cull_mode = BaseMaterial3D.CULL_DISABLED
					bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				bm.metallic = 0.0
				bm.metallic_texture = null
				bm.metallic_specular = 0.12
				bm.roughness = 1.0
				bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

func _collider(root: Node3D, radius: float, height: float = 4.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position.y = height / 2.0
	body.add_child(cs)
	root.add_child(body)
	root.add_to_group("navsource")

func _box_collider(root: Node3D, size: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = offset + Vector3(0, size.y / 2.0, 0)
	body.add_child(cs)
	root.add_child(body)
	root.add_to_group("navsource")

func _place(name: String, x: float, z: float, height: float, yaw: float = -1.0, scale := 1.0, collide := 0.0) -> Node3D:
	var scene := _scene(name)
	if not scene:
		return null
	var root := Node3D.new()
	var model: Node3D = scene.instantiate()
	root.add_child(model)
	add_child(root)
	Weapons._fit_height(model, height)
	model.position.y += height / 2.0
	root.position = Map.ground_pos(x, z) - Vector3(0, 0.05, 0)
	root.rotation.y = yaw if yaw >= 0.0 else rng.randf() * TAU
	root.scale = Vector3.ONE * scale
	if collide > 0.0:
		_collider(root, collide)
	return root

func _place_at(name: String, x: float, z: float, y_offset: float, height: float, yaw: float = -1.0) -> Node3D:
	var n := _place(name, x, z, height, yaw, 1.0, 0.0)
	if n:
		n.position.y += y_offset
	return n

func _place_real(name: String, x: float, z: float, scale: float, collide: float, yaw: float = -1.0) -> Node3D:
	var scene := _tree_scene(name)
	if not scene:
		return null
	var model: Node3D = scene.instantiate()
	_prep_foliage_materials(model)
	add_child(model)
	model.position = Map.ground_pos(x, z) - Vector3(0, 0.03, 0)
	model.rotation.y = yaw if yaw >= 0.0 else rng.randf() * TAU
	model.scale = Vector3.ONE * scale
	if collide > 0.0:
		_collider(model, collide)
	return model

# simple textured box helper (triplanar so boards / ribs stay horizontal / vertical on every face)
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, yaw: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi

func _mat(tex: String, scale: float, tint: Color = Color.WHITE, triplanar: bool = true) -> StandardMaterial3D:
	var m := Foliage.pbr(tex, scale, tint)
	m.uv1_triplanar = triplanar
	m.uv1_scale = Vector3.ONE * scale
	return m

func _plain(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

# ---------------------------------------------------------------- forests
func _build_forests() -> void:
	if "--no-trees" in _flags:
		return
	Trees.build(self, Map.TREES, Map.SHRUBS, Map.FIRE, rng)
	Trees.build(self, Map.BORDER_TREES, [], Map.FIRE, rng, false)
	# the landmark oak leaning over the Weg zur Hütte (photo 24)
	Trees.hero(self, "oak", Map.LANDMARK_OAK.x, Map.LANDMARK_OAK.y, 1.55, 0.6, rng)
	_build_forest_blocker()

# deep forest (more than ~8 m inside the tree line, away from every track) is impassable: undergrowth wall for
# physics and the navigation bake, hidden behind the shrubs along the edges
func _build_forest_blocker() -> void:
	# layer 16: blocks the zombies (physics + navigation bake), the player walks through the trees
	var body := StaticBody3D.new()
	body.collision_layer = 16
	body.add_to_group("navsource")
	var ext := Map.extent()
	var step := 5.0
	var z := ext.position.y + step / 2.0
	while z < ext.end.y:
		var x := ext.position.x + step / 2.0
		while x < ext.end.x:
			if _deep_forest(x, z):
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(step, 4.0, step)
				cs.shape = box
				cs.position = Map.ground_pos(x, z) + Vector3(0, 1.5, 0)
				body.add_child(cs)
			x += step
		z += step
	add_child(body)

func _deep_forest(x: float, z: float) -> bool:
	var r := 8.0
	for o in [Vector2(0, 0), Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, -r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, r) * 0.7]:
		if Map.leaf_weight(x + o.x, z + o.y) < 0.92:
			return false
	if Map.on_road(x, z, 6.0) or Vector2(x, z).distance_to(Map.FIRE) < 30.0:
		return false
	return true

# ---------------------------------------------------------------- buildings
# walls of a room (local x/z, floor at y0, height h) with one opening: side "w"/"e"/"n"/"s", along = offset along the
# wall, width, bottom, top. Every piece gets a collider so the room is enterable.
func _walls(root: Node3D, size: Vector2, y0: float, h: float, thick: float, mat: Material, opening: Dictionary) -> void:
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	for side in ["w", "e", "n", "s"]:
		var horizontal: bool = side == "n" or side == "s"
		var length: float = size.x if horizontal else size.y
		var pieces: Array = [[-length / 2.0, length / 2.0, y0, y0 + h]]
		if opening.get("side", "") == side:
			var a: float = opening["along"] - opening["width"] / 2.0
			var b: float = opening["along"] + opening["width"] / 2.0
			pieces = [[-length / 2.0, a, y0, y0 + h], [b, length / 2.0, y0, y0 + h],
				[a, b, y0, y0 + opening["bottom"]], [a, b, y0 + opening["top"], y0 + h]]
		for pc in pieces:
			var len: float = pc[1] - pc[0]
			var hh: float = pc[3] - pc[2]
			if len <= 0.01 or hh <= 0.01:
				continue
			var mid: float = (pc[0] + pc[1]) / 2.0
			var cy: float = (pc[2] + pc[3]) / 2.0
			var box_size: Vector3
			var pos: Vector3
			match side:
				"w": box_size = Vector3(thick, hh, len); pos = Vector3(-hx + thick / 2.0, cy, mid)
				"e": box_size = Vector3(thick, hh, len); pos = Vector3(hx - thick / 2.0, cy, mid)
				"n": box_size = Vector3(len, hh, thick); pos = Vector3(mid, cy, -hz + thick / 2.0)
				_: box_size = Vector3(len, hh, thick); pos = Vector3(mid, cy, hz - thick / 2.0)
			_box(root, box_size, pos, mat)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = box_size
			cs.shape = bs
			cs.position = pos
			body.add_child(cs)
			root.add_child(body)
	root.add_to_group("navsource")

func _slab(root: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	_box(root, size, pos, mat)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
	root.add_child(body)

func _loot(root: Node3D, kind: String, id: String, label: String, local_pos: Vector3, model: String, height: float, yaw: float = 0.0) -> void:
	var l := Loot.new()
	l.setup(kind, id, label)
	root.add_child(l)
	l.position = local_pos
	l.rotation.y = yaw
	var scene := _scene(model)
	if scene:
		var m: Node3D = scene.instantiate()
		l.add_child(m)
		Weapons._fit_height(m, height)
		m.position.y += height / 2.0
	else:
		_box(l, Vector3(0.6, 0.35, 0.4), Vector3(0, 0.18, 0), Foliage.pbr("planks", 0.8, Color(0.5, 0.42, 0.3)))
	if kind == "ammo":
		# olive ammunition crate with a lid
		_box(l, Vector3(0.62, 0.32, 0.4), Vector3(0, 0.16, 0), _plain(Color(0.28, 0.32, 0.2), 0.8))
		_box(l, Vector3(0.66, 0.05, 0.44), Vector3(0, 0.34, 0), _plain(Color(0.22, 0.26, 0.16), 0.8))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 0.6
	light.omni_range = 2.5
	light.position = Vector3(0, 0.6, 0)
	l.add_child(light)
	loots.append(l)

func _hip_roof(parent: Node3D, size: Vector2, y: float, height: float, overhang: float, mat: Material, gable: bool = false) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x / 2.0 + overhang
	var hz := size.y / 2.0 + overhang
	# ridge along the longer axis
	var along_x := size.x >= size.y
	var r := (absf(size.x - size.y) / 2.0) if not gable else (hx if along_x else hz)
	var top := y + height
	var a := Vector3(-hx, y, -hz); var b := Vector3(hx, y, -hz); var c := Vector3(hx, y, hz); var d := Vector3(-hx, y, hz)
	var r0: Vector3; var r1: Vector3
	if along_x:
		r0 = Vector3(-r, top, 0); r1 = Vector3(r, top, 0)
	else:
		r0 = Vector3(0, top, -r); r1 = Vector3(0, top, r)
	var faces: Array
	if along_x:
		faces = [[a, b, r1, r0], [c, d, r0, r1], [b, c, r1], [d, a, r0]]
	else:
		faces = [[b, c, r1, r0], [d, a, r0, r1], [a, b, r0], [c, d, r1]]
	for f in faces:
		var n: Vector3 = ((f[1] - f[0]).cross(f[2] - f[0])).normalized()
		if n.y < 0.0:
			n = -n
			f.reverse()
		var tris: Array = [[f[0], f[1], f[2]]] if f.size() == 3 else [[f[0], f[1], f[2]], [f[0], f[2], f[3]]]
		for t in tris:
			for v: Vector3 in t:
				st.set_normal(n)
				st.set_uv(Vector2(v.x + v.z, v.y) * 0.5)
				st.add_vertex(v)
	# soffit / underside
	for t in [[a, c, b], [a, d, c]]:
		for v: Vector3 in t:
			st.set_normal(Vector3.DOWN)
			st.set_uv(Vector2(v.x, v.z) * 0.5)
			st.add_vertex(v)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)

func _waldhuette() -> Node3D:
	# Photos 14, 17, 19: garage door in the west face (north end), a second small double door in the base at the
	# west end of the north face, the outside stair along the north face rising east to the upper door, the east side
	# buried in the slope. Local axes: -x west, -z north.
	var b: Dictionary = Map.BUILDINGS["waldhuette"]
	var pos: Vector2 = b["pos"]
	var size: Vector2 = b["size"]
	var base_h: float = b["base_h"]
	var wall_h: float = b["wall_h"]
	var root := Node3D.new()
	add_child(root)
	root.rotation.y = b["yaw"]
	var west := Vector2(pos.x - cos(b["yaw"]) * size.x / 2.0, pos.y + sin(b["yaw"]) * size.x / 2.0)
	var y0 := Map.ground_height(west.x, west.y) - 0.15
	root.position = Vector3(pos.x, y0, pos.y)
	var concrete := _mat("ph_concrete", 0.45, Color(0.95, 0.95, 0.92))
	var wood := _mat("ph_cladding", 0.55, Color(0.5, 0.36, 0.3))
	var dark_wood := _plain(Color(0.28, 0.14, 0.09), 0.75)
	var roof := _plain(Color(0.16, 0.16, 0.17), 0.85)
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	# garage storey: concrete walls with the door opening in the west face (north end), enterable (photo 14)
	_walls(root, Vector2(size.x, size.y), 0.0, base_h, 0.3, concrete, { "side": "w", "along": -hz + 1.9, "width": 2.6, "bottom": 0.0, "top": 2.1 })
	_slab(root, Vector3(size.x, 0.1, size.y), Vector3(0, -0.05, 0), _mat("ph_concrete", 0.6, Color(0.7, 0.7, 0.68)))
	_slab(root, Vector3(size.x, 0.25, size.y), Vector3(0, base_h + 0.125, 0), _plain(Color(0.35, 0.25, 0.15), 0.9))
	_box(root, Vector3(size.x + 0.16, wall_h, size.y + 0.16), Vector3(0, base_h + 0.25 + wall_h / 2.0 - 0.125, 0), wood)
	# inside: workbench with an ammunition crate, shotgun and MP5 on the wall
	_box(root, Vector3(2.2, 0.08, 0.7), Vector3(hx - 1.2, 0.85, hz - 0.6), Foliage.pbr("planks", 0.8, Color(0.5, 0.42, 0.3)))
	for lx in [hx - 2.1, hx - 0.3]:
		_box(root, Vector3(0.1, 0.85, 0.6), Vector3(lx, 0.42, hz - 0.6), Foliage.pbr("planks", 0.8, Color(0.4, 0.33, 0.25)))
	_loot(root, "ammo", "", "Munitionskiste", Vector3(hx - 1.2, 0.9, hz - 0.6), "", 0.3)
	_loot(root, "weapon", "shotgun", "Schrotflinte", Vector3(hx - 0.35, 1.5, 0.5), "rifle", 0.25, PI / 2.0)
	_loot(root, "weapon", "smg", "MP5", Vector3(-0.5, 1.4, -hz + 0.35), "smg", 0.22, 0.0)
	_loot(root, "ammo", "", "Munitionskiste", Vector3(-hx + 0.6, 0.0, hz - 0.5), "", 0.3)
	var inner := OmniLight3D.new()
	inner.light_color = Color(1.0, 0.8, 0.55)
	inner.light_energy = 1.2
	inner.omni_range = 6.0
	inner.position = Vector3(0, base_h - 0.3, 0)
	root.add_child(inner)
	_box(root, Vector3(size.x + 0.9, 0.14, size.y + 0.9), Vector3(0, base_h + wall_h + 0.07, 0), dark_wood)
	_hip_roof(root, size, base_h + wall_h + 0.14, b["roof_h"], 0.55, roof)
	_box(root, Vector3(0.5, 1.6, 0.5), Vector3(hx * 0.4, base_h + wall_h + 1.4, -0.6), _plain(Color(0.35, 0.33, 0.3)))
	# garage door stands open: one leaf folded against the wall outside, the other inside
	_box(root, Vector3(0.08, 2.05, 1.3), Vector3(-hx - 0.06, 1.05, -hz + 0.5), dark_wood)
	_box(root, Vector3(0.08, 2.05, 1.3), Vector3(-hx + 0.34, 1.05, -hz + 3.85), dark_wood)
	# small double door in the base: north face, west end, under the start of the stair (photo 17)
	_box(root, Vector3(1.5, 2.0, 0.08), Vector3(-hx + 1.4, 1.0, -hz - 0.02), dark_wood)
	# closed shutters: north (2), west (1), east (1)
	var shutter := _plain(Color(0.3, 0.15, 0.1), 0.7)
	for sh in [[Vector3(-0.3, base_h + 1.55, -hz - 0.11), 0.0], [Vector3(-hx + 1.0, base_h + 1.55, -hz - 0.11), 0.0],
			[Vector3(-hx - 0.11, base_h + 1.55, 1.0), PI / 2.0], [Vector3(hx + 0.11, base_h + 1.55, 1.5), PI / 2.0]]:
		_box(root, Vector3(1.1, 0.9, 0.06), sh[0], shutter, sh[1])
	# outside stair along the north face: 13 steps from the north-west corner up to the landing at the east end
	var steps := 13
	var rise := base_h / steps
	var tread := 0.33
	var stair_z := -hz - 0.55
	var x_start := -hx + 0.3
	var step_mat := _mat("ph_concrete", 0.5, Color(0.85, 0.85, 0.82))
	for i in steps:
		var x := x_start + i * tread
		_box(root, Vector3(tread, rise * (i + 1), 0.95), Vector3(x + tread / 2.0, rise * (i + 1) / 2.0, stair_z), step_mat)
	var x_top := x_start + steps * tread
	_box(root, Vector3(hx - x_top, base_h, 0.95), Vector3((x_top + hx) / 2.0, base_h / 2.0, stair_z), step_mat)
	# upper door on the north face at the east end, two small steps in front (photos 15, 17)
	_box(root, Vector3(0.9, 2.0, 0.06), Vector3(hx - 0.9, base_h + 1.0, -hz - 0.1), dark_wood)
	_box(root, Vector3(1.3, 0.16, 0.5), Vector3(hx - 0.9, base_h + 0.08, -hz - 0.35), step_mat)
	# railing
	var rail := _plain(Color(0.25, 0.25, 0.27), 0.5, 0.6)
	for i in range(0, steps + 1, 3):
		_box(root, Vector3(0.04, 1.0, 0.04), Vector3(x_start + i * tread, rise * i + 0.5, stair_z - 0.45), rail)
	var run := steps * tread
	var rl := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(sqrt(run * run + base_h * base_h), 0.04, 0.04)
	rl.mesh = rb
	rl.material_override = rail
	rl.position = Vector3(x_start + run / 2.0, base_h / 2.0 + 1.0, stair_z - 0.45)
	rl.rotation.z = atan2(base_h, run)
	root.add_child(rl)
	# collision: upper storey block (the garage below has its own walls), walkable ramp over the stair, landing
	_box_collider(root, Vector3(size.x + 0.2, wall_h + 0.3, size.y + 0.2), Vector3(0, base_h, 0))
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(sqrt(run * run + base_h * base_h) + 0.3, 0.2, 0.95)
	rcs.shape = rbox
	rcs.position = Vector3(x_start + run / 2.0, base_h / 2.0 - 0.1, stair_z)
	rcs.rotation.z = atan2(base_h, run)
	ramp.add_child(rcs)
	var lcs := CollisionShape3D.new()
	var lbox := BoxShape3D.new()
	lbox.size = Vector3(hx - x_top + 0.2, base_h, 0.95)
	lcs.shape = lbox
	lcs.position = Vector3((x_top + hx) / 2.0, base_h / 2.0, stair_z)
	ramp.add_child(lcs)
	root.add_child(ramp)
	ramp.add_to_group("navsource")
	# warm light at the upper door and over the garage
	var wl := OmniLight3D.new()
	wl.light_color = Color(1.0, 0.72, 0.42)
	wl.light_energy = 2.5
	wl.omni_range = 10.0
	wl.shadow_enabled = true
	wl.position = Vector3(hx - 0.9, base_h + 2.3, -hz - 0.8)
	root.add_child(wl)
	return root

func _holzlager() -> Node3D:
	var b: Dictionary = Map.BUILDINGS["holzlager"]
	var pos: Vector2 = b["pos"]
	var size: Vector2 = b["size"]
	var base_h: float = b["base_h"]
	var wall_h: float = b["wall_h"]
	var root := Node3D.new()
	add_child(root)
	root.rotation.y = b["yaw"]
	root.position = Map.ground_pos(pos.x, pos.y) - Vector3(0, 0.1, 0)
	var concrete := _mat("ph_concrete", 0.45, Color(0.9, 0.9, 0.88))
	var metal := _mat("ph_corrugated", 0.35, Color(1.15, 1.1, 1.05))
	metal.roughness = 0.6
	var roof := _plain(Color(0.55, 0.55, 0.56), 0.5, 0.3)
	var dark_wood := _plain(Color(0.25, 0.13, 0.08), 0.75)
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	# concrete base and sheet-metal walls as real walls; small back window in the west face (the way in)
	_walls(root, Vector2(size.x, size.y), 0.0, base_h, 0.25, concrete, { "side": "w", "along": 2.0, "width": 1.3, "bottom": 0.0, "top": 0.0 })
	_walls(root, Vector2(size.x + 0.1, size.y + 0.1), base_h, wall_h, 0.12, metal, { "side": "w", "along": 2.0, "width": 1.3, "bottom": 0.3, "top": 2.4 })
	var pane := Breakable.new()
	pane.setup(Vector2(1.2, 1.0))
	root.add_child(pane)
	pane.position = Vector3(-hx - 0.02, base_h + 0.85, 2.0)
	pane.rotation.y = PI / 2.0
	_slab(root, Vector3(size.x, 0.1, size.y), Vector3(0, -0.05, 0), _mat("ph_concrete", 0.6, Color(0.6, 0.6, 0.58)))
	_slab(root, Vector3(size.x, 0.1, size.y), Vector3(0, base_h + wall_h, 0), _plain(Color(0.2, 0.2, 0.2)))
	# crates as steps outside and inside the window
	_slab(root, Vector3(0.9, 0.55, 0.9), Vector3(-hx - 0.6, 0.275, 2.0), Foliage.pbr("planks", 0.8, Color(0.45, 0.38, 0.28)))
	_slab(root, Vector3(0.9, 0.5, 0.9), Vector3(-hx + 0.75, 0.25 + base_h, 2.0), Foliage.pbr("planks", 0.8, Color(0.45, 0.38, 0.28)))
	_hip_roof(root, size, base_h + wall_h, b["roof_h"], 0.6, roof, true)
	# inside: the good weapons on a rack, ammunition, firewood
	_box(root, Vector3(2.6, 1.6, 0.08), Vector3(0, base_h + 1.4, hz - 0.2), Foliage.pbr("planks", 0.8, Color(0.4, 0.33, 0.25)))
	_loot(root, "weapon", "ak47", "AK-47", Vector3(-0.7, base_h + 1.4, hz - 0.3), "ak47", 0.28, 0.0)
	_loot(root, "weapon", "revolver", "Revolver", Vector3(0.7, base_h + 1.4, hz - 0.3), "revolver", 0.16, 0.0)
	_loot(root, "ammo", "", "Munitionskiste", Vector3(hx - 0.9, base_h, -hz + 1.2), "", 0.3)
	_loot(root, "ammo", "", "Munitionskiste", Vector3(hx - 0.9, base_h, -hz + 2.2), "", 0.3)
	for k in 3:
		_box(root, Vector3(0.9, 1.1, 2.2), Vector3(-hx + 0.6, base_h + 0.55, -hz + 2.0 + k * 2.5), _mat("ph_bark_beech2", 0.5, Color(0.7, 0.6, 0.5), true))
	var inner := OmniLight3D.new()
	inner.light_color = Color(0.9, 0.85, 0.7)
	inner.light_energy = 1.0
	inner.omni_range = 8.0
	inner.position = Vector3(0, base_h + wall_h - 0.4, 0)
	root.add_child(inner)
	# big double door and a small door on the east side facing the gravel (photo 12)
	_box(root, Vector3(0.08, 3.0, 3.6), Vector3(size.x / 2.0 + 0.07, base_h + 1.5, 2.2), dark_wood)
	_box(root, Vector3(0.08, 2.1, 0.9), Vector3(size.x / 2.0 + 0.07, base_h + 1.05, -2.8), dark_wood)
	# notice board
	_box(root, Vector3(0.05, 0.7, 1.0), Vector3(size.x / 2.0 + 0.08, base_h + 2.1, -0.6), _plain(Color(0.6, 0.62, 0.55)))
	return root

func _build_buildings() -> void:
	_waldhuette()
	_holzlager()
	# firewood stacks at the south end of the Holzlager
	var hl: Dictionary = Map.BUILDINGS["holzlager"]
	var hp: Vector2 = hl["pos"]
	for i in 3:
		_place("woodpile", hp.x + 2.0 + i * 1.7, hp.y + 9.5, 1.2, 0.0, 1.0, 1.1)

# ---------------------------------------------------------------- campsite
func _log_bench(x: float, z: float, yaw: float, length: float = 2.6) -> void:
	var lb := _place("log_bench", x, z, 0.55, yaw + TAU, 1.0, 0.9)
	if lb:
		return
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(x, z)
	root.rotation.y = yaw
	var bark := _mat("ph_bark_beech2", 0.6, Color(0.8, 0.7, 0.6), false)
	var seat := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16; cm.bottom_radius = 0.16; cm.height = length
	seat.mesh = cm
	seat.material_override = bark
	seat.rotation.z = PI / 2.0
	seat.position.y = 0.45
	root.add_child(seat)
	for sx in [-length * 0.35, length * 0.35]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.17; lm.bottom_radius = 0.19; lm.height = 0.32
		leg.mesh = lm
		leg.material_override = bark
		leg.position = Vector3(sx, 0.16, 0)
		root.add_child(leg)
	_box_collider(root, Vector3(length, 0.6, 0.4))

func _log_table(x: float, z: float, yaw: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(x, z)
	root.rotation.y = yaw
	var bark := _mat("ph_bark_beech2", 0.6, Color(0.55, 0.45, 0.38), false)
	var plank := Foliage.pbr("planks", 0.8, Color(0.45, 0.36, 0.28))
	for k in 3:
		_box(root, Vector3(2.3, 0.09, 0.28), Vector3(0, 0.76, (k - 1) * 0.3), plank)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(2.3, 0.09, 0.32), Vector3(0, 0.46, side * 0.78), plank)
	for sx in [-0.85, 0.85]:
		for sz in [-0.35, 0.35, -0.78, 0.78]:
			var leg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			var tall := absf(sz) < 0.5
			lm.top_radius = 0.11; lm.bottom_radius = 0.12; lm.height = 0.72 if tall else 0.42
			leg.mesh = lm
			leg.material_override = bark
			leg.position = Vector3(sx, lm.height / 2.0, sz)
			root.add_child(leg)
	_box_collider(root, Vector3(2.3, 0.85, 1.9))

func _fountain(x: float, z: float, yaw: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(x, z)
	root.rotation.y = yaw
	var bark := _mat("ph_bark_oak", 0.6, Color(0.7, 0.62, 0.55), false)
	# hollowed log trough on two stumps, wooden post with a spout (photos 15, 21)
	for sx in [-0.8, 0.8]:
		var st := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.2; sm.bottom_radius = 0.22; sm.height = 0.35
		st.mesh = sm
		st.material_override = bark
		st.position = Vector3(sx, 0.17, 0)
		root.add_child(st)
	var trough := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.27; tm.bottom_radius = 0.27; tm.height = 2.4
	trough.mesh = tm
	trough.material_override = bark
	trough.rotation.z = PI / 2.0
	trough.position.y = 0.6
	root.add_child(trough)
	# water surface inside
	var water := MeshInstance3D.new()
	var wq := BoxMesh.new()
	wq.size = Vector3(2.1, 0.02, 0.36)
	water.mesh = wq
	var wm := _plain(Color(0.2, 0.28, 0.3, 0.85), 0.05, 0.4)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wm
	water.position.y = 0.8
	root.add_child(water)
	_box(root, Vector3(0.16, 1.5, 0.16), Vector3(0.6, 0.75, -0.35), bark)
	_box(root, Vector3(0.05, 0.05, 0.4), Vector3(0.6, 1.35, -0.12), _plain(Color(0.3, 0.3, 0.32), 0.4, 0.8))
	_box_collider(root, Vector3(2.5, 0.9, 0.7))

func _signpost(x: float, z: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(x, z)
	root.rotation.y = 0.3
	var post := _plain(Color(0.35, 0.3, 0.25), 0.8)
	_box(root, Vector3(0.1, 2.4, 0.1), Vector3(0, 1.2, 0), post)
	var yellow := _plain(Color(0.95, 0.8, 0.1), 0.6)
	_box(root, Vector3(0.9, 0.14, 0.03), Vector3(0.45, 2.1, 0.06), yellow, 0.0)
	_box(root, Vector3(0.9, 0.14, 0.03), Vector3(0.4, 1.9, -0.06), yellow, PI * 0.55)
	# small wooden info board next to it (photo 16)
	_box(root, Vector3(0.6, 0.5, 0.05), Vector3(1.0, 1.4, 0.3), Foliage.pbr("planks", 0.8, Color(0.6, 0.5, 0.4)))
	_box(root, Vector3(0.08, 1.2, 0.08), Vector3(1.0, 0.6, 0.3), post)
	_box_collider(root, Vector3(0.3, 2.4, 0.3))

func _build_campsite() -> void:
	# square stone fireplace with the swivel grill (photo 20)
	var fire := Foliage.campfire(Map.ground_pos(Map.FIRE.x, Map.FIRE.y))
	add_child(fire)
	for c in fire.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
			c.queue_free()
	fire_light = fire.get_node("Light")
	var stone := _mat("rock", 0.8, Color(0.62, 0.6, 0.56))
	for k in 4:
		var yaw := k * PI / 2.0
		var off := Vector3(cos(yaw), 0, sin(yaw)) * 0.85
		_box(fire, Vector3(0.32, 0.35, 1.9), off + Vector3(0, 0.12, 0), stone, -yaw)
	_box(fire, Vector3(1.6, 0.05, 1.6), Vector3(0, 0.0, 0), _plain(Color(0.12, 0.11, 0.1), 1.0))
	_collider(fire, 1.1, 0.5)
	var iron := _plain(Color(0.15, 0.15, 0.16), 0.45, 0.7)
	_box(fire, Vector3(0.07, 1.9, 0.07), Vector3(1.05, 0.95, 1.05), iron)
	_box(fire, Vector3(1.5, 0.04, 0.04), Vector3(0.35, 1.75, 0.35), iron, PI / 4.0)
	var grate := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.42; gm.bottom_radius = 0.42; gm.height = 0.03
	grate.mesh = gm
	grate.material_override = iron
	grate.position = Vector3(0, 0.72, 0)
	fire.add_child(grate)
	_box(fire, Vector3(0.02, 1.0, 0.02), Vector3(0, 1.25, 0), iron)
	# the four round-log benches (photo 20), the log picnic table (photo 18)
	var bi := 0
	for b in Map.BENCHES:
		_log_bench(b[0].x, b[0].y, b[1])
		if bi == 0:
			_place_at("mug", b[0].x + 0.8, b[0].y + 0.1, 0.5, 0.11)
		bi += 1
	_log_table(Map.TABLE.x, Map.TABLE.y, Map.TABLE.z)
	_place_at("basket", Map.TABLE.x + 0.5, Map.TABLE.y, 0.83, 0.4)
	# fountain, bin, signpost and the fallen log at the west edge (photos 15, 16, 21)
	_fountain(Map.FOUNTAIN.x, Map.FOUNTAIN.y, Map.FOUNTAIN.z)
	var bin := Node3D.new()
	add_child(bin)
	bin.position = Map.ground_pos(Map.BIN.x, Map.BIN.y)
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.26; dm.bottom_radius = 0.26; dm.height = 0.85
	drum.mesh = dm
	drum.material_override = _plain(Color(0.82, 0.82, 0.8), 0.6, 0.2)
	drum.position.y = 0.43
	bin.add_child(drum)
	_box(bin, Vector3(0.54, 0.16, 0.54), Vector3(0, 0.9, 0), _plain(Color(0.1, 0.1, 0.1), 0.6))
	_collider(bin, 0.3, 1.0)
	_signpost(Map.SIGNPOST.x, Map.SIGNPOST.y)
	var seat := Node3D.new()
	add_child(seat)
	seat.position = Map.ground_pos(Map.LOG_SEAT.x, Map.LOG_SEAT.y) + Vector3(0, 0.3, 0)
	seat.rotation.y = Map.LOG_SEAT.z
	var lg := MeshInstance3D.new()
	var lgm := CylinderMesh.new()
	lgm.top_radius = 0.28; lgm.bottom_radius = 0.32; lgm.height = 3.2
	lg.mesh = lgm
	lg.material_override = _mat("ph_bark_oak", 0.6, Color(0.75, 0.7, 0.62), false)
	lg.rotation.z = PI / 2.0
	seat.add_child(lg)
	_box_collider(seat, Vector3(3.2, 0.6, 0.6), Vector3(0, -0.3, 0))
	# pumpkin lanterns: game flavour at the stair, the table and the fountain
	var wh: Dictionary = Map.BUILDINGS["waldhuette"]
	var whp: Vector2 = wh["pos"]
	var lanterns := [[whp.x - 4.6, whp.y - 4.2, "pumpkin_lantern", 0.55], [Map.TABLE.x + 1.6, Map.TABLE.y - 0.9, "pumpkin_lantern", 0.5], [Map.FOUNTAIN.x + 1.8, Map.FOUNTAIN.y + 0.6, "pumpkin", 0.42]]
	for p in lanterns:
		_place(p[2], p[0], p[1], p[3], -1.0, 1.0, 0.0)
		if p[2] == "pumpkin_lantern":
			var pl := OmniLight3D.new()
			pl.light_color = Color(1.0, 0.55, 0.15)
			pl.light_energy = 1.2
			pl.omni_range = 4.0
			add_child(pl)
			pl.global_position = Map.ground_pos(p[0], p[1]) + Vector3(0, p[3] * 0.6, 0)
	# mushrooms in the leaf litter around the clearing
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(12.0, 30.0)
		var x := Map.FIRE.x + cos(a) * r
		var z := Map.FIRE.y + sin(a) * r
		if Map.leaf_weight(x, z) < 0.6 or Map.on_road(x, z, 1.0) or Map.in_building(x, z, 1.0) or Map.in_clearing(x, z):
			continue
		_place("mushroom_cluster" if rng.randf() < 0.65 else "mushroom_fly", x, z, 0.22 + rng.randf() * 0.18, -1.0, 1.0, 0.0)

# pasture fence between the tracks and the meadow (photos 4, 9): posts, two wires, collision
func _build_fence() -> void:
	var post_mat := _plain(Color(0.42, 0.36, 0.28), 0.9)
	var wire_mat := _plain(Color(0.6, 0.6, 0.62), 0.4, 0.8)
	var root := Node3D.new()
	add_child(root)
	root.add_to_group("navsource")
	var body := StaticBody3D.new()
	body.collision_layer = 1
	root.add_child(body)
	for line in Map.FENCE:
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var len := a.distance_to(b)
			var n := maxi(1, int(len / 3.5))
			var dir := (b - a) / n
			for k in n + (1 if i == line.size() - 2 else 0):
				var p := a + dir * k
				var pp := Map.ground_pos(p.x, p.y)
				_box(root, Vector3(0.09, 1.25, 0.09), pp + Vector3(0, 0.55, 0), post_mat)
			for k in n:
				var p0 := Map.ground_pos((a + dir * k).x, (a + dir * k).y)
				var p1 := Map.ground_pos((a + dir * (k + 1)).x, (a + dir * (k + 1)).y)
				for hgt in [0.55, 1.05]:
					var w := MeshInstance3D.new()
					var wm := BoxMesh.new()
					wm.size = Vector3(0.02, 0.02, p0.distance_to(p1))
					w.mesh = wm
					w.material_override = wire_mat
					w.position = (p0 + p1) / 2.0 + Vector3(0, hgt, 0)
					w.look_at_from_position(w.position, p1 + Vector3(0, hgt, 0))
					root.add_child(w)
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(0.1, 1.3, p0.distance_to(p1) + 0.1)
				cs.shape = bx
				cs.position = (p0 + p1) / 2.0 + Vector3(0, 0.65, 0)
				cs.look_at_from_position(cs.position, p1 + Vector3(0, 0.65, 0))
				body.add_child(cs)

# ---------------------------------------------------------------- clutter and foliage
func _build_clutter() -> void:
	# Poly Haven clutter is optional (not in the repo); everything below works without it
	var clutter := [["fern_02_a", 60, 0.9], ["fern_02_b", 40, 0.9], ["fern_02_c", 30, 0.9], ["fern_02_d", 30, 0.9],
		["grass_medium_02_a", 40, 1.0], ["grass_medium_02_b", 40, 1.0], ["grass_medium_02_c", 40, 1.0],
		["moss_01_a", 12, 1.0], ["moss_01_b", 12, 1.0], ["moss_01_c", 12, 1.0],
		["dry_branches_medium_01_a", 20, 1.0], ["dry_branches_medium_01_b", 20, 1.0], ["dry_branches_medium_01_c", 20, 1.0],
		["bark_debris_01_a", 14, 1.0], ["bark_debris_01_b", 14, 1.0], ["bark_debris_01_c", 14, 1.0]]
	for c in clutter:
		if not _tree_scene(c[0]):
			continue
		for i in int(c[1]):
			var x: float = rng.randf_range(-70.0, 60.0)
			var z: float = rng.randf_range(-70.0, 70.0)
			var is_grass: bool = c[0].begins_with("grass_medium")
			if Map.leaf_weight(x, z) < 0.5 and not is_grass:
				continue
			if is_grass and Map.meadow_weight(x, z) < 0.5:
				continue
			if Map.on_road(x, z, 0.8) or Map.in_building(x, z, 1.5) or Map.in_clearing(x, z):
				continue
			_place_real(c[0], x, z, c[2] * (0.7 + rng.randf() * 0.6), 0.0)
	for i in 10:
		var x: float = rng.randf_range(-70.0, 50.0)
		var z: float = rng.randf_range(-70.0, 60.0)
		if not Map.is_clear_zone(x, z) and Map.leaf_weight(x, z) > 0.5:
			if not _place_real(["boulder_01", "tree_stump_01", "dead_tree_trunk_02"][i % 3], x, z, 0.8 + rng.randf() * 0.5, 0.8):
				_place(["rock", "stump", "stump"][i % 3], x, z, 0.6, -1.0, 1.0, 0.6)
	# mushrooms over the forest floor near the camp
	for i in 160:
		var x: float = rng.randf_range(-80.0, 60.0)
		var z: float = rng.randf_range(-90.0, 60.0)
		if Map.leaf_weight(x, z) < 0.6 or Map.on_road(x, z, 1.0) or Map.in_building(x, z, 1.0) or Map.in_clearing(x, z):
			continue
		_place("mushroom_cluster" if rng.randf() < 0.7 else "mushroom_fly", x, z, 0.18 + rng.randf() * 0.2, -1.0, 1.0, 0.0)

func _spawn_deer() -> void:
	var groups := [[Vector2(40, 108), "stag"], [Vector2(46, 114), "deer"], [Vector2(52, 106), "deer"], [Vector2(-130, 52), "deer"], [Vector2(-136, 58), "deer"], [Vector2(-60, -120), "stag"], [Vector2(-66, -126), "deer"], [Vector2(95, 85), "deer"]]
	var i := 0
	for g in groups:
		var pos: Vector2 = g[0]
		var kind: String = g[1]
		var d := Deer.new()
		d.setup(player, kind, _scene(kind), 100 + i)
		add_child(d)
		d.global_position = Map.ground_pos(pos.x, pos.y) + Vector3(0, 0.3, 0)
		d.rotation.y = rng.randf() * TAU
		i += 1

func _build_foliage() -> void:
	if "--no-foliage" in _flags:
		return
	var leaf_sampler := func(r: RandomNumberGenerator):
		var x: float = r.randf_range(-110.0, 110.0)
		var z: float = r.randf_range(-120.0, 100.0)
		var w := Map.leaf_weight(x, z)
		if r.randf() > w * 0.9 + 0.05:
			return null
		if Map.on_road(x, z) and r.randf() > 0.25:
			return null
		if Map.in_building(x, z) or (Map.in_clearing(x, z) and r.randf() > 0.15):
			return null
		return Map.ground_pos(x, z)
	if not "--no-leaves" in _flags:
		add_child(Foliage.ground_leaves(70000, leaf_sampler, rng))
	var grass_sampler := func(r: RandomNumberGenerator):
		var x: float = r.randf_range(-150.0, 150.0)
		var z: float = r.randf_range(-60.0, 160.0)
		if Map.meadow_weight(x, z) < 0.5:
			return null
		if Map.on_road(x, z, 0.5) or Map.in_building(x, z, 0.5):
			return null
		return Map.ground_pos(x, z)
	if not "--no-grass" in _flags:
		add_child(Foliage.grass(240000, grass_sampler, rng))
	if not "--no-particles" in _flags:
		add_child(Foliage.falling_leaves(Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3(0, 9, 10), Vector3(45, 7, 40)))

# ---------------------------------------------------------------- game flow
func _on_start() -> void:
	if not navigation_ready:
		return
	if over:
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	get_tree().paused = false
	hud.hide_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.active = true
	if not started and not "--no-music" in _flags:
		music.play("night")
	started = true

func _pause() -> void:
	if not started or over:
		return
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	hud.show_overlay("PAUSE", "Verschnaufpause. Hier kannst du Grafik und Steuerung anpassen.", "Weiter")

func _game_over() -> void:
	over = true
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	music.horde = 0.0
	music.play("gameover")
	get_tree().paused = true
	hud.show_overlay("GESTORBEN", "Du hast %d Welle%s überstanden mit %d Punkten." % [waves.completed, "" if waves.completed == 1 else "n", player.score], "Nochmal")

func spawn_zombie(type: String, p: Vector2, speed_mul: float) -> void:
	var z := Zombie.new()
	z.setup(type, player, barricades, speed_mul, _zombie_killed)
	zombies_root.add_child(z)
	var spawn := Map.ground_pos(p.x, p.y)
	var nav_map := nav_region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		spawn = NavigationServer3D.map_get_closest_point(nav_map, spawn)
	z.global_position = spawn + Vector3(0, 0.2, 0)
	_alive_count += 1
	z.tree_exiting.connect(func():
		if z.alive:
			_alive_count = maxi(0, _alive_count - 1))

func _zombie_killed(_zombie: Zombie) -> void:
	_alive_count = maxi(0, _alive_count - 1)

func alive_zombies() -> int:
	return _alive_count

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if fire_light:
		fire_light.light_energy = 5.0 * (0.8 + 0.2 * sin(t * 11.0) * sin(t * 7.3) + 0.1 * sin(t * 23.0))
	if player and player.active:
		var near = null
		var nd := 3.2
		for b in barricades:
			var d: float = Vector2(b.center.x - player.global_position.x, b.center.z - player.global_position.z).length()
			if d < nd:
				nd = d
				near = b
		near_bar = near
		var loot = null
		if not near:
			var ld := 2.4
			for l in loots:
				if not is_instance_valid(l) or l.taken:
					continue
				var d: float = l.global_position.distance_to(player.global_position + Vector3(0, 0.8, 0))
				if d < ld:
					ld = d
					loot = l
		hud.set_prompt(near.prompt_text() if near else (loot.prompt_text() if loot else ""))
		if near and Input.is_action_just_pressed("interact"):
			near.interact(player)
			hud.set_prompt(near.prompt_text())
		elif loot and Input.is_action_just_pressed("interact"):
			loot.take(weapons, hud)
			hud.set_prompt("")
	if _autotest and started:
		_autotest_step(delta)

# --autotest: start automatically, look around, save screenshots, quit (used by Claude for checks)
# yaw 0 looks north (-Z), PI/2 west, -PI/2 east, PI south
func _autotest_step(delta: float) -> void:
	_shot_t += delta
	var views := [
		[Vector3(3, 0, 5), 0.0, 0.02],            # from the hut's north-west corner north over the fire (photo 20)
		[Vector3(-6, 0, -17), -2.3, 0.0],         # from the fountain south-east over the fire to the hut's north face (photo 15)
		[Vector3(7, 0, 58), 0.0, 0.03],           # from the fork north between the huts (photo 22 reversed)
		[Vector3(96, 0, 33), PI / 2.0 + 0.25, 0.02],   # on the Weg zur Hütte looking west towards the oak (photo 10)
		[Vector3(-9, 0, 4), -PI / 2.0, 0.06],     # west face of the Waldhütte with the garage door (photo 14)
		[Vector3(9, 0, -9), PI, 0.06],            # north face with the stair (photo 17)
		[Vector3(4, 0, -3), 0.35, 0.02],          # from the fire north-west to the fountain and the Waldweg entrance (photos 16, 20)
		[Vector3(2.5, 0, 1.3), -PI / 2.0, 0.0],   # into the open garage of the Waldhütte
		[Vector3(-10.5, 0, 30.5), -PI / 2.0 + 0.1, 0.02],   # back of the Holzlager with the window
	]
	if _shot_i == 0 and _shot_t > 1.5:
		_fps_frames += 1
		_fps_time += delta
		if _fps_time >= 1.5 and not _fps_done:
			_fps_done = true
			print("FPS_SAMPLE %.1f flags=%s" % [_fps_frames / _fps_time, _flags])
	if _shot_i == 0 and _shot_t > 0.5 and not _spawned_test:
		_spawned_test = true
		for i in 3:
			spawn_zombie("shambler", Vector2(30 + i * 3.0, 54 - i), 1.0)
		if "--pathtest" in _flags:
			spawn_zombie("runner", Vector2(100, 32), 1.0)
			spawn_zombie("runner", Vector2(-40, -75), 1.0)
			spawn_zombie("runner", Vector2(-70, 77), 1.0)
			spawn_zombie("runner", Vector2(30, 100), 1.0)
	if "--pathtest" in _flags:
		if _shot_t > 40.0:
			for zz in zombies_root.get_children():
				print("ZOMBIE at %s" % zz.global_position)
			print("PATHTEST_DONE player=%s" % player.global_position)
			get_tree().quit()
		return
	if _shot_t > 3.0 and _shot_i < views.size() and not _shooting:
		_shooting = true
		var idx := _shot_i
		var v: Array = views[idx]
		player.global_position = Map.ground_pos(v[0].x, v[0].z) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.rotation.y = v[1]
		player.pitch = v[2]
		player.head.rotation.x = v[2]
		for i in 8:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var dir := ProjectSettings.globalize_path("res://") + "../shots/"
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png(dir + "shot%d.png" % idx)
		_shot_i = idx + 1
		_shot_t = 2.0
		_shooting = false
		if _shot_i >= views.size():
			for zz in zombies_root.get_children():
				print("ZOMBIE at %s" % zz.global_position)
			print("AUTOTEST_DONE zombies=%d fps=%d" % [alive_zombies(), Engine.get_frames_per_second()])
			get_tree().quit()
