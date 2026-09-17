# Builds the Birkenhof world from Map, wires player / weapons / zombies / waves / HUD.
# Autumn dusk look: warm backlight through fog, leaf-covered ground, campsite with cabin in the bay.
extends Node3D

var player: Player
var hud: Hud
var weapons: Weapons
var waves: Waves
var zombies_root: Node3D
var barricades: Array = []
var nav_region: NavigationRegion3D
var torches: Array = []
var fire_light: OmniLight3D
var started := false
var over := false
var near_bar = null
var rng := RandomNumberGenerator.new()
var crowns: Array = []
var _autotest := false
var _shot_t := 0.0
var _shot_i := 0
var _spawned_test := false
var _shooting := false
var _flags: PackedStringArray = []
var _fps_frames := 0
var _fps_time := 0.0
var _fps_done := false

const CAMP := Vector3(0.0, 0.0, -48.0)   # campfire in the middle of the bay
const CABIN := Vector3(0.0, 0.0, -68.0)  # cabin at the north edge of the clearing

func _ready() -> void:
	rng.seed = 4242
	_autotest = "--autotest" in OS.get_cmdline_user_args()
	_flags = OS.get_cmdline_user_args()
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
	nm.cell_size = 0.35
	nm.cell_height = 0.25
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	_build_terrain()
	_build_roads()
	_build_props()
	_build_campsite()
	_build_foliage()
	_build_sky_extras()

	hud = Hud.new()
	add_child(hud)
	hud.start_pressed.connect(_on_start)
	player = Player.new()
	player.hud = hud
	add_child(player)
	player.global_position = Map.ground_pos(0.0, -42.0) + Vector3(0, 0.3, 0)
	player.flashlight.visible = false
	player.died.connect(_game_over)
	zombies_root = Node3D.new()
	add_child(zombies_root)
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
	hud.show_overlay("BIRKENHOF", "Die Lichtung oben am Birkenhof ist der letzte sichere Ort. Die Zombies kommen den Weg herauf und aus dem Wald. Halte die Barrikaden, überlebe die Wellen.", "Spiel starten", "Wegnetz wird berechnet ...")
	nav_region.bake_finished.connect(func(): hud.overlay_status.text = "Bereit."; if _autotest: _on_start())
	nav_region.bake_navigation_mesh(true)

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.7, 0.7, 0.74)
	sm.sky_horizon_color = Color(1.0, 0.9, 0.75)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.35, 0.22, 0.12)
	sm.ground_horizon_color = Color(0.8, 0.66, 0.5)
	sm.sun_angle_max = 22.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.ssao_enabled = not "--no-ssao" in _flags
	env.ssao_intensity = 2.0
	env.ssao_radius = 1.2
	env.ssil_enabled = true
	env.sdfgi_enabled = false  # leaks light through thin leaf cards and burns them white
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_bounce_feedback = 0.0 if "--no-feedback" in _flags else 0.3
	env.sdfgi_energy = 1.1
	env.ssil_intensity = 1.6
	env.ssil_radius = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.95, 0.88, 0.78)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.004
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.7
	env.volumetric_fog_enabled = not "--no-vfog" in _flags
	env.volumetric_fog_density = 0.009
	env.volumetric_fog_albedo = Color(0.85, 0.8, 0.72)
	env.volumetric_fog_emission = Color(0.8, 0.6, 0.4)
	env.volumetric_fog_emission_energy = 0.02
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_ambient_inject = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# low autumn sun behind the forest (north-east), shining towards the camera on the bay
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.85, 0.62)
	sun.light_energy = 2.6
	sun.shadow_enabled = not "--no-shadows" in _flags
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.5
	sun.shadow_blur = 1.5
	sun.light_volumetric_fog_energy = 0.8
	add_child(sun)
	sun.look_at_from_position(Vector3(40, 22, -140), Vector3(0, 0, -50))
	# soft fill from the sky side
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.7, 0.7, 0.75)
	fill.light_energy = 0.5
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3(-40, 40, 40), Vector3(0, 0, -40))

func _ground_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := (Map.ground_height(x + e, z) - Map.ground_height(x - e, z)) / (2.0 * e)
	var dz := (Map.ground_height(x, z + e) - Map.ground_height(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

# 1 = leaf litter (forest floor, clearing), 0 = meadow grass
func _leaf_weight(x: float, z: float) -> float:
	var rw := Map.ROAD_WIDTH / 2.0
	var dx := x - Map.road_x(z)
	var w := 0.0
	# clearing and forest around the bay
	w = maxf(w, 1.0 - smoothstep(-30.0, -22.0, z) if absf(x) < 48.0 else 0.0)
	w = maxf(w, smoothstep(30.0, 48.0, absf(x)) * (1.0 - smoothstep(-30.0, -10.0, z)))
	# east forest side of the road
	var edge := rw + 1.5 + (0.0 if z < 40.0 else (z - 40.0) * 0.5)
	w = maxf(w, smoothstep(edge, edge + 5.0, dx))
	# far west tree line and bottom tree line
	w = maxf(w, smoothstep(-85.0, -92.0, x))
	w = maxf(w, smoothstep(112.0, 120.0, z))
	# never on the road itself
	w *= smoothstep(rw - 0.4, rw + 0.6, absf(dx)) if z > Map.ROAD_START - 2.0 else 1.0
	return w

# ---------------------------------------------------------------- terrain
func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var W := 320.0
	var n := 200
	var step := W / n
	for j in n + 1:
		for i in n + 1:
			var x := -W / 2.0 + i * step
			var z := -W / 2.0 + j * step
			st.set_uv(Vector2(x, z))
			st.set_color(Color(_leaf_weight(x, z), 0, 0))
			st.set_normal(_ground_normal(x, z))
			st.add_vertex(Vector3(x, Map.ground_height(x, z), z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Foliage.terrain_material()
	mi.add_to_group("navsource")
	add_child(mi)
	mi.create_trimesh_collision()

func _ribbon(zs: Array, edges: Callable, lift: float, v_scale: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in zs.size():
		var z: float = zs[i]
		var e: Vector2 = edges.call(z)
		for x in [e.x, e.y]:
			st.set_uv(Vector2(0.0 if x == e.x else 1.0, i * v_scale))
			st.set_normal(_ground_normal(x, z))
			st.add_vertex(Vector3(x, Map.ground_height(x, z) + lift, z))
		if i > 0:
			var a := (i - 1) * 2
			st.add_index(a); st.add_index(a + 1); st.add_index(a + 2)
			st.add_index(a + 1); st.add_index(a + 3); st.add_index(a + 2)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_roads() -> void:
	var rw := Map.ROAD_WIDTH / 2.0
	var asphalt := Foliage.pbr("asphalt", 1.0, Color(0.85, 0.85, 0.85))
	asphalt.uv1_scale = Vector3(1.0, 1.0, 1.0)
	asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gravel := Foliage.pbr("gravel", 1.0, Color(0.9, 0.86, 0.8))
	gravel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var zs: Array = []
	var z := Map.ROAD_START - 1.0
	while z <= Map.ROAD_END:
		zs.append(z)
		z += 2.0
	_ribbon(zs, func(zz): return Vector2(Map.road_x(zz) - rw, Map.road_x(zz) + rw), 0.04, 0.5, asphalt)
	var sh: Array = []
	z = -38.0
	while z <= -24.0:
		sh.append(z)
		z += 2.0
	_ribbon(sh, func(zz): return Vector2(Map.road_x(zz) - rw - 3.5, Map.road_x(zz) - rw + 0.2), 0.03, 0.6, gravel)
	var tz: Array = []
	z = -50.0
	while z >= -95.0:
		tz.append(z)
		z -= 2.0
	_ribbon(tz, func(zz): return Vector2(Map.track_x(zz) - 1.5, Map.track_x(zz) + 1.5), 0.04, 0.7, gravel)
	# concrete curb around the bay (kept from the photos)
	var curb_mat := StandardMaterial3D.new()
	curb_mat.albedo_color = Color(0.55, 0.53, 0.48)
	curb_mat.roughness = 0.9
	var B := Map.BAY
	_curb(Vector3(B.end.x, 0, B.get_center().y), B.size.y, PI / 2.0, curb_mat)
	_curb(Vector3(B.position.x, 0, (B.position.y + B.end.y + 6.0) / 2.0), B.size.y - 6.0, PI / 2.0, curb_mat)

func _curb(pos: Vector3, length: float, yaw: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.14, 0.25)
	mi.mesh = box
	mi.material_override = mat
	add_child(mi)
	mi.global_position = Vector3(pos.x, Map.ground_height(pos.x, pos.z) + 0.07, pos.z)
	mi.rotation.y = yaw

# ---------------------------------------------------------------- props
var _scenes := {}

func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		var path := "res://assets/models/%s.glb" % name
		_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[name]

func _place_at(name: String, x: float, z: float, y_offset: float, height: float, yaw: float = -1.0) -> Node3D:
	var n := _place(name, x, z, height, yaw, 1.0, 0.0)
	if n:
		n.position.y += y_offset
	return n

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
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = collide
		cyl.height = 4.0
		cs.shape = cyl
		cs.position.y = 2.0
		body.add_child(cs)
		root.add_child(body)
		root.add_to_group("navsource")
	return root

const BROADLEAF := ["island_tree_01", "island_tree_02", "island_tree_03", "tree_small_02", "jacaranda_tree"]
const CONIFER := ["fir_tree_01_a", "fir_tree_01_b", "fir_tree_01_c"]
var _tree_scenes := {}

func _tree_scene(name: String) -> PackedScene:
	if not _tree_scenes.has(name):
		var path := "res://assets/trees/%s.glb" % name
		_tree_scenes[name] = load(path) if ResourceLoader.exists(path) else null
	return _tree_scenes[name]

# make leaf cards double sided with alpha scissor, receive proper shading
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
				bm.specular = 0.12
				bm.roughness = 1.0
				if "--no-normal" in OS.get_cmdline_user_args():
					bm.normal_enabled = false
				if "--no-a2c" in OS.get_cmdline_user_args():
					bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
				if "--dark-leaf" in OS.get_cmdline_user_args():
					bm.albedo_color = Color(0.3, 0.3, 0.3)
				bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

func _place_real(name: String, x: float, z: float, scale: float, collide: float, yaw: float = -1.0) -> Node3D:
	var scene := _tree_scene(name)
	if not scene:
		return null
	var model: Node3D = scene.instantiate()
	_prep_foliage_materials(model)
	if OS.has_environment("REMZ_DEBUG") and not _scenes.has(name + "_matdbg"):
		_scenes[name + "_matdbg"] = true
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var bm: BaseMaterial3D = mat
					print("MAT %s surf %d albedo_tex=%s color=%s transp=%d cull=%d emission=%s rough=%.2f metal=%.2f normal=%s" % [name, i, bm.albedo_texture.resource_path if bm.albedo_texture else "none", bm.albedo_color, bm.transparency, bm.cull_mode, bm.emission_enabled, bm.roughness, bm.metallic, bm.normal_enabled])
	add_child(model)
	model.position = Map.ground_pos(x, z) - Vector3(0, 0.03, 0)
	model.rotation.y = yaw if yaw >= 0.0 else rng.randf() * TAU
	model.scale = Vector3.ONE * scale
	if collide > 0.0:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = collide
		cyl.height = 4.0
		cs.shape = cyl
		cs.position.y = 2.0
		body.add_child(cs)
		model.add_child(body)
		model.add_to_group("navsource")
	return model

func _tree(x: float, z: float, big: bool = false) -> void:
	if "--no-trees" in _flags:
		return
	if Map.is_clear_zone(x, z):
		return
	if Vector2(x - CABIN.x, z - CABIN.z).length() < 9.0:
		return
	var r := rng.randf()
	var conifer := r > 0.78
	# photogrammetry trees (Poly Haven, autumn recoloured) when the reduced GLBs exist
	var pool: Array = CONIFER if conifer else BROADLEAF
	var name: String = pool[rng.randi() % pool.size()]
	var near_camp := Vector2(x - CAMP.x, z - CAMP.z).length() < 75.0
	if _tree_scene(name) and near_camp and (conifer or rng.randf() < 0.8):
		var s := (0.9 if big else 0.7) + rng.randf() * 0.5
		_place_real(name, x, z, s, 0.45 / s)
		return
	var kind := "tree_pine" if conifer else ("tree_leaf" if rng.randf() < 0.85 else "tree_dead")
	if not conifer and _scene("tree_autumn_a"):
		kind = "tree_autumn_a" if rng.randf() < 0.6 else "tree_autumn_b"
	if conifer and _scene("spruce_detailed"):
		kind = "spruce_detailed"
	var h: float = { "tree_leaf": 11.0, "tree_pine": 12.0, "tree_dead": 8.0, "tree_autumn_a": 12.0, "tree_autumn_b": 13.0, "spruce_detailed": 15.0 }[kind]
	var s := (1.0 if big else 0.75) + rng.randf() * 0.6
	var node := _place(kind, x, z, h, -1.0, s, 0.5)
	if node and kind == "tree_leaf":
		crowns.append([node.position + Vector3(0, h * s * 0.68, 0), h * s * 0.3])

func _bush(x: float, z: float, s: float) -> void:
	var shrub: String = ["island_tree_02", "tree_small_02", "jacaranda_tree"][rng.randi() % 3]
	if _tree_scene(shrub) and Vector2(x - CAMP.x, z - CAMP.z).length() < 90.0:
		_place_real(shrub, x, z, 0.16 + 0.1 * s, 0.9, -1.0)
		return
	_place("bush", x, z, 2.2, -1.0, s, 0.9)

func _build_props() -> void:
	var rw := Map.ROAD_WIDTH / 2.0
	var forest_edge := func(z: float) -> float: return Map.road_x(z) + rw + (3.5 if z < 40.0 else 3.5 + (z - 40.0) * 0.5)
	for i in 300:
		var z := -60.0 + rng.randf() * 175.0
		var x: float = forest_edge.call(z) + rng.randf() * rng.randf() * 50.0
		_tree(x, z, z < -30.0)
	for i in 170:
		_tree(-34.0 + rng.randf() * 84.0, -62.0 - rng.randf() * 35.0, true)
	for i in 60:
		_tree(Map.STRIP.end.x + 1.5 + rng.randf() * 25.0, -62.0 + rng.randf() * 26.0, true)
	for i in 80:
		var z := -60.0 - rng.randf() * 35.0
		_tree(Map.track_x(z) + 4.0 + rng.randf() * 30.0, z, true)
	# west side of the clearing gets trees too so the camp is enclosed like the reference
	for i in 70:
		_tree(-14.0 - rng.randf() * 30.0, -66.0 + rng.randf() * 34.0, true)
	var z := -37.0
	while z < 42.0:
		var x := Map.road_x(z) + rw + 1.9 + rng.randf() * 0.6
		if not Map.is_clear_zone(x, z) or z > -34.0:
			_bush(x, z, 0.7 + rng.randf() * 0.5)
		z += 1.8 + rng.randf()
	for i in 26:
		var x := Map.STRIP.end.x + 0.5 + rng.randf() * 3.0
		var zz := -62.0 + rng.randf() * 26.0
		if not Map.is_clear_zone(x, zz):
			_bush(x, zz, 0.8 + rng.randf() * 0.8)
	for i in 45:
		var zz := 55.0 + rng.randf() * 65.0
		_bush(Map.road_x(zz) - rw - 1.5 - rng.randf() * 7.0, zz, 0.6 + rng.randf() * 0.9)
	for i in 14:
		var zz := 60.0 + rng.randf() * 60.0
		_tree(Map.road_x(zz) - rw - 4.0 - rng.randf() * 8.0, zz)
	for i in 90:
		_tree(-100.0 + rng.randf() * 25.0, -80.0 + rng.randf() * 200.0, true)
	for i in 40:
		_tree(-30.0 + rng.randf() * 60.0, 118.0 + rng.randf() * 20.0, true)
	# the three green benches on the strip (photos)
	for bz in [-57.0, -50.0, -43.0]:
		_place("bench", 10.5, bz, 0.9, -PI / 2.0 + TAU, 1.0, 0.8)
	_place("woodpile", -8.0, -60.0, 1.2, 0.2, 1.0, 1.2)
	_place("stump", 15.5, -46.0, 0.6, -1.0, 1.0, 0.5)
	_place("stump", -14.0, -70.0, 0.6, -1.0, 1.0, 0.5)
	for i in 8:
		var x := -25.0 + rng.randf() * 50.0
		var zz := -78.0 + rng.randf() * 14.0
		if not Map.is_clear_zone(x, zz) and Vector2(x - CABIN.x, zz - CABIN.z).length() > 8.0:
			_place("rock", x, zz, 1.1, -1.0, 0.5 + rng.randf(), 0.6)
	# farmhouse at the bottom
	var hx := Map.road_x(116.0) - 10.0
	var house := Node3D.new()
	add_child(house)
	house.global_position = Map.ground_pos(hx, 116.0)
	house.rotation.y = 0.2
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(11, 5, 8)
	wall.mesh = wb
	wall.material_override = Foliage.pbr("planks", 0.5)
	wall.position.y = 2.5
	house.add_child(wall)
	var roof := MeshInstance3D.new()
	var rp := PrismMesh.new()
	rp.size = Vector3(12.5, 3.4, 9.5)
	roof.mesh = rp
	roof.material_override = Foliage.pbr("roof", 0.8)
	roof.position.y = 6.7
	house.add_child(roof)
	var hb := StaticBody3D.new()
	var hs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(11, 5, 8)
	hs.shape = hbox
	hs.position.y = 2.5
	hb.add_child(hs)
	house.add_child(hb)
	house.add_to_group("navsource")
	_post(Map.road_x(-18.0) - rw - 1.6, -18.0, Color(0.11, 0.31, 0.66))
	_post(Map.road_x(100.0) - rw - 0.6, 100.0, Color(0.93, 0.93, 0.93), 0.12, 1.1)

func _post(x: float, z: float, color: Color, w := 0.03, h := 1.6) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = w
	c.bottom_radius = w
	c.height = h
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = color if w > 0.05 else Color(0.6, 0.6, 0.6)
	mi.material_override = m
	add_child(mi)
	mi.global_position = Map.ground_pos(x, z) + Vector3(0, h / 2.0, 0)
	if w <= 0.05:
		var sign := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.22, 0.28, 0.02)
		sign.mesh = b
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		sign.material_override = sm
		sign.position.y = 0.7
		mi.add_child(sign)

# ---------------------------------------------------------------- campsite (reference image)
func _build_campsite() -> void:
	# cabin: Meshy model when generated, otherwise a plank/tile placeholder of the same footprint
	var cabin := _place("cabin", CABIN.x, CABIN.z, 5.2, PI, 1.0, 0.0)
	if cabin:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8.0, 5.0, 6.5)
		cs.shape = box
		cs.position.y = 2.5
		body.add_child(cs)
		cabin.add_child(body)
		cabin.add_to_group("navsource")
	else:
		var hut := Node3D.new()
		add_child(hut)
		hut.global_position = Map.ground_pos(CABIN.x, CABIN.z)
		var base := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(8.0, 1.0, 6.5)
		base.mesh = bb
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.6, 0.6, 0.58)
		base.material_override = cm
		base.position.y = 0.5
		hut.add_child(base)
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(8.0, 2.8, 6.5)
		wall.mesh = wb
		wall.material_override = Foliage.pbr("planks", 0.6)
		wall.position.y = 2.4
		hut.add_child(wall)
		var roof := MeshInstance3D.new()
		var rp := PrismMesh.new()
		rp.size = Vector3(9.6, 2.2, 8.0)
		roof.mesh = rp
		roof.material_override = Foliage.pbr("roof", 1.0)
		roof.position.y = 4.9
		hut.add_child(roof)
		var door := MeshInstance3D.new()
		var dq := BoxMesh.new()
		dq.size = Vector3(1.0, 2.1, 0.08)
		door.mesh = dq
		door.material_override = Foliage.pbr("planks", 1.0, Color(0.5, 0.35, 0.22))
		door.position = Vector3(-1.5, 2.05, 3.29)
		hut.add_child(door)
		for wx in [1.3, 2.6]:
			var win := MeshInstance3D.new()
			var wq := BoxMesh.new()
			wq.size = Vector3(0.9, 0.9, 0.06)
			win.mesh = wq
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(1.0, 0.8, 0.5)
			wm.emission_enabled = true
			wm.emission = Color(1.0, 0.7, 0.35)
			wm.emission_energy_multiplier = 4.0
			win.material_override = wm
			win.position = Vector3(wx, 2.6, 3.29)
			hut.add_child(win)
		var wl := OmniLight3D.new()
		wl.light_color = Color(1.0, 0.7, 0.4)
		wl.light_energy = 2.0
		wl.omni_range = 8.0
		wl.position = Vector3(1.9, 2.6, 4.2)
		hut.add_child(wl)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8.0, 5.0, 6.5)
		cs.shape = box
		cs.position.y = 2.5
		body.add_child(cs)
		hut.add_child(body)
		hut.add_to_group("navsource")
	# campfire with cauldron tripod
	var fire := Foliage.campfire(Map.ground_pos(CAMP.x, CAMP.z))
	add_child(fire)
	fire_light = fire.get_node("Light")
	var tripod := _place("tripod_cauldron", CAMP.x, CAMP.z, 1.9, 0.6, 1.0, 0.0)
	if not tripod:
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.25, 0.18, 0.12)
		for i in 3:
			var leg := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.03
			cy.bottom_radius = 0.04
			cy.height = 2.1
			leg.mesh = cy
			leg.material_override = tm
			var a := i * TAU / 3.0
			add_child(leg)
			leg.global_position = Map.ground_pos(CAMP.x + cos(a) * 0.45, CAMP.z + sin(a) * 0.45) + Vector3(0, 1.0, 0)
			leg.look_at(leg.global_position + Vector3(-cos(a), 2.3, -sin(a)))
			leg.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		var pot := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.28
		pm.bottom_radius = 0.22
		pm.height = 0.3
		pot.mesh = pm
		var potm := StandardMaterial3D.new()
		potm.albedo_color = Color(0.08, 0.08, 0.08)
		potm.metallic = 0.6
		potm.roughness = 0.5
		pot.material_override = potm
		add_child(pot)
		pot.global_position = Map.ground_pos(CAMP.x, CAMP.z) + Vector3(0, 0.95, 0)
	var fb := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fcy := CylinderShape3D.new()
	fcy.radius = 0.9
	fcy.height = 2.0
	fcs.shape = fcy
	fcs.position.y = 1.0
	fb.add_child(fcs)
	fire.add_child(fb)
	fire.add_to_group("navsource")
	# log benches around the fire
	for a: float in [0.35, 2.45, 4.1]:
		var bx: float = CAMP.x + cos(a) * 3.4
		var bz: float = CAMP.z + sin(a) * 3.4
		var yaw: float = -a + PI / 2.0 + TAU
		var lb := _place("log_bench", bx, bz, 0.55, yaw, 1.0, 0.9)
		if not lb:
			var seat := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(2.6, 0.18, 0.45)
			seat.mesh = sm
			seat.material_override = Foliage.pbr("planks", 0.7, Color(0.55, 0.45, 0.35))
			add_child(seat)
			seat.global_position = Map.ground_pos(bx, bz) + Vector3(0, 0.42, 0)
			seat.rotation.y = yaw
			for s in [-1.0, 1.0]:
				var lg := MeshInstance3D.new()
				var lc := CylinderMesh.new()
				lc.top_radius = 0.17
				lc.bottom_radius = 0.17
				lc.height = 0.5
				lg.mesh = lc
				lg.material_override = Foliage.pbr("bark", 1.0)
				add_child(lg)
				lg.global_position = Map.ground_pos(bx + cos(yaw) * s * 0.95, bz - sin(yaw) * s * 0.95) + Vector3(0, 0.17, 0)
				lg.rotation = Vector3(PI / 2.0, yaw, 0)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2.6, 1.0, 0.5)
			cs.shape = box
			cs.position.y = 0.5
			body.add_child(cs)
			body.position = Map.ground_pos(bx, bz)
			body.rotation.y = yaw
			add_child(body)
			body.add_to_group("navsource")
	# blanket, mug and candle on the benches (reference image)
	var b0x: float = CAMP.x + cos(0.35) * 3.4
	var b0z: float = CAMP.z + sin(0.35) * 3.4
	_place_at("blanket", b0x + 0.6, b0z, 0.5, 0.45, -0.35 + PI / 2.0 + TAU)
	_place_at("mug", b0x - 0.8, b0z, 0.5, 0.11)
	_place_at("candle", CAMP.x + cos(2.45) * 3.4 + 0.5, CAMP.z + sin(2.45) * 3.4, 0.5, 0.12)
	# pumpkins on the ground beside the cabin steps and on the bench strip
	var pumpkins := [[4.6, -64.5, "pumpkin_lantern", 0.55], [5.4, -63.6, "pumpkin", 0.42], [6.2, -64.4, "pumpkin_lantern", 0.6], [-4.8, -64.0, "pumpkin", 0.5], [9.2, -47.0, "pumpkin_lantern", 0.5], [-3.2, -44.4, "pumpkin", 0.4]]
	for p in pumpkins:
		if not _place(p[2], p[0], p[1], p[3], -1.0, 1.0, 0.0):
			var pk := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = p[3] * 0.55
			sm.height = p[3]
			pk.mesh = sm
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.95, 0.45, 0.08)
			pmat.roughness = 0.6
			if p[2] == "pumpkin_lantern":
				pmat.emission_enabled = true
				pmat.emission = Color(1.0, 0.5, 0.1)
				pmat.emission_energy_multiplier = 1.5
			pk.material_override = pmat
			add_child(pk)
			pk.global_position = Map.ground_pos(p[0], p[1]) + Vector3(0, p[3] / 2.0, 0)
		if p[2] == "pumpkin_lantern":
			var pl := OmniLight3D.new()
			pl.light_color = Color(1.0, 0.55, 0.15)
			pl.light_energy = 1.2
			pl.omni_range = 4.0
			add_child(pl)
			pl.global_position = Map.ground_pos(p[0], p[1]) + Vector3(0, p[3] * 0.6, 0)
	_place("basket", 8.0, -58.5, 0.5, -1.0, 1.0, 0.0)
	# photogrammetry ground clutter: ferns, moss, branches, bark, boulders, stumps, dead trunks
	var clutter := [["fern_02_a", 60, 0.9], ["fern_02_b", 40, 0.9], ["fern_02_c", 30, 0.9], ["fern_02_d", 30, 0.9],
		["grass_medium_02_a", 40, 1.0], ["grass_medium_02_b", 40, 1.0], ["grass_medium_02_c", 40, 1.0], ["grass_medium_02_d", 40, 1.0], ["grass_medium_02_e", 40, 1.0],
		["moss_01_a", 12, 1.0], ["moss_01_b", 12, 1.0], ["moss_01_c", 12, 1.0], ["moss_01_d", 12, 1.0], ["moss_01_g", 12, 1.0], ["moss_01_k", 12, 1.0],
		["dry_branches_medium_01_a", 16, 1.0], ["dry_branches_medium_01_b", 16, 1.0], ["dry_branches_medium_01_c", 16, 1.0],
		["bark_debris_01_a", 12, 1.0], ["bark_debris_01_b", 12, 1.0], ["bark_debris_01_c", 12, 1.0], ["bark_debris_01_d", 12, 1.0]]
	for c in clutter:
		if not _tree_scene(c[0]):
			continue
		for i in int(c[1]):
			var a := rng.randf() * TAU
			var rr := 6.0 + rng.randf() * 55.0
			var cx: float = CAMP.x + cos(a) * rr
			var cz: float = CAMP.z + sin(a) * rr * 1.3
			if _leaf_weight(cx, cz) < 0.5 and not c[0].begins_with("grass_medium"):
				continue
			if Map.is_clear_zone(cx, cz) and not c[0].begins_with("moss") and not c[0].begins_with("grass_medium"):
				continue
			if Vector2(cx - CABIN.x, cz - CABIN.z).length() < 6.0:
				continue
			_place_real(c[0], cx, cz, c[2] * (0.7 + rng.randf() * 0.6), 0.0)
	for i in 6:
		var a := rng.randf() * TAU
		var rr := 14.0 + rng.randf() * 40.0
		var bx: float = CAMP.x + cos(a) * rr
		var bz: float = CAMP.z + sin(a) * rr
		if not Map.is_clear_zone(bx, bz) and Vector2(bx - CABIN.x, bz - CABIN.z).length() > 8.0:
			_place_real(["boulder_01", "tree_stump_01", "dead_tree_trunk_02"][i % 3], bx, bz, 0.8 + rng.randf() * 0.5, 0.8)
	# mushrooms along the edges of the clearing
	for i in 22:
		var a := rng.randf() * TAU
		var r := 9.0 + rng.randf() * 7.0
		var mx := CAMP.x + cos(a) * r
		var mz := CAMP.z + sin(a) * r
		if Map.is_clear_zone(mx, mz) and mz > -58.0 and absf(mx) < 8.0:
			continue
		var kind := "mushroom_cluster" if rng.randf() < 0.65 else "mushroom_fly"
		_place(kind, mx, mz, 0.22 + rng.randf() * 0.18, -1.0, 1.0, 0.0)

# ---------------------------------------------------------------- foliage
func _build_foliage() -> void:
	if "--no-foliage" in _flags:
		return
	var leaf_sampler := func(r: RandomNumberGenerator):
		var x: float = CAMP.x + r.randf_range(-70.0, 70.0)
		var z: float = CAMP.z + r.randf_range(-50.0, 100.0)
		var w := _leaf_weight(x, z)
		if r.randf() > w * 0.9 + 0.05:
			return null
		var rw := Map.ROAD_WIDTH / 2.0
		if z > Map.ROAD_START and absf(x - Map.road_x(z)) < rw and r.randf() > 0.25:
			return null
		return Map.ground_pos(x, z)
	if not "--no-leaves" in _flags:
		add_child(Foliage.ground_leaves(60000, leaf_sampler, rng))
	var grass_sampler := func(r: RandomNumberGenerator):
		var x: float = CAMP.x + r.randf_range(-90.0, 45.0)
		var z: float = CAMP.z + r.randf_range(-20.0, 150.0)
		if _leaf_weight(x, z) > 0.4:
			return null
		var rw := Map.ROAD_WIDTH / 2.0
		if z > Map.ROAD_START - 2.0 and absf(x - Map.road_x(z)) < rw + 0.6:
			return null
		return Map.ground_pos(x, z)
	if not "--no-grass" in _flags:
		add_child(Foliage.grass(50000, grass_sampler, rng))
	if not "--no-canopy" in _flags:
		add_child(Foliage.canopy(crowns, rng))
	if not "--no-particles" in _flags:
		add_child(Foliage.falling_leaves(Map.ground_pos(CAMP.x, CAMP.z) + Vector3(0, 9, -6), Vector3(26, 7, 22)))

func _build_sky_extras() -> void:
	# a few village lights in the valley to the west, visible through the dusk haze
	for i in 30:
		var l := MeshInstance3D.new()
		var ls := SphereMesh.new()
		ls.radius = 0.4
		ls.height = 0.8
		l.mesh = ls
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.85, 0.6)
		lm.emission_enabled = true
		lm.emission = lm.albedo_color
		lm.emission_energy_multiplier = 2.0
		l.material_override = lm
		add_child(l)
		l.global_position = Vector3(-150.0 - rng.randf() * 60.0, -18.0 + rng.randf() * 3.0, -80.0 + rng.randf() * 200.0)

# ---------------------------------------------------------------- game flow
func _on_start() -> void:
	if over:
		get_tree().reload_current_scene()
		return
	hud.hide_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.active = true
	started = true

func _pause() -> void:
	if not started or over:
		return
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_overlay("PAUSE", "Die Zombies warten nicht lange.", "Weiter")

func _game_over() -> void:
	over = true
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_overlay("GESTORBEN", "Du hast %d Welle%s überstanden mit %d Punkten." % [waves.wave, "" if waves.wave == 1 else "n", player.score], "Nochmal")

func spawn_zombie(type: String, p: Vector2, speed_mul: float) -> void:
	var z := Zombie.new()
	z.setup(type, player, barricades, speed_mul, Callable())
	zombies_root.add_child(z)
	z.global_position = Map.ground_pos(p.x, p.y) + Vector3(0, 0.2, 0)

func alive_zombies() -> int:
	var n := 0
	for z in zombies_root.get_children():
		if z is Zombie and z.alive:
			n += 1
	return n

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if fire_light:
		fire_light.light_energy = 5.0 * (0.8 + 0.2 * sin(t * 11.0) * sin(t * 7.3) + 0.1 * sin(t * 23.0))
	if Input.is_action_just_pressed("pause"):
		_pause()
	if player and player.active:
		var near = null
		var nd := 3.2
		for b in barricades:
			var d: float = Vector2(b.center.x - player.global_position.x, b.center.z - player.global_position.z).length()
			if d < nd:
				nd = d
				near = b
		near_bar = near
		hud.set_prompt(near.prompt_text() if near else "")
		if near and Input.is_action_just_pressed("interact"):
			near.interact(player)
			hud.set_prompt(near.prompt_text())
	if _autotest and started:
		_autotest_step(delta)

# --autotest: start automatically, look around, save screenshots, quit (used by Claude for checks)
func _autotest_step(delta: float) -> void:
	_shot_t += delta
	var views := [
		[Vector3(0, 0, -36), 0.0, 0.03],          # from the bay entrance towards fire and cabin
		[Vector3(-5, 0, -52), -1.2, -0.05],       # fire and benches from the west
		[Vector3(9, 0, -44), 0.9, -0.02],         # towards the cabin past the pumpkins
		[Vector3(0, 0, 10), 0.0, 0.05],           # uphill from the road with the hedge
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
			spawn_zombie("shambler", Vector2(-3 + i * 2.0, -20 - i * 4), 1.0)
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
			print("AUTOTEST_DONE zombies=%d fps=%d" % [alive_zombies(), Engine.get_frames_per_second()])
			get_tree().quit()
