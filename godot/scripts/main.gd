# Builds the Birkenhof world from Map, wires player / weapons / zombies / waves / HUD.
extends Node3D

var player: Player
var hud: Hud
var weapons: Weapons
var waves: Waves
var zombies_root: Node3D
var barricades: Array = []
var nav_region: NavigationRegion3D
var torches: Array = []
var stars: MeshInstance3D
var started := false
var over := false
var near_bar = null
var rng := RandomNumberGenerator.new()
var _autotest := false
var _shot_t := 0.0
var _shot_i := 0
var _spawned_test := false
var _shooting := false

func _ready() -> void:
	rng.seed = 4242
	_autotest = "--autotest" in OS.get_cmdline_user_args()
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
	_build_torches()
	_build_sky_extras()

	hud = Hud.new()
	add_child(hud)
	hud.start_pressed.connect(_on_start)
	player = Player.new()
	player.hud = hud
	add_child(player)
	player.global_position = Map.ground_pos(0.0, -48.0) + Vector3(0, 0.3, 0)
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
	hud.show_overlay("BIRKENHOF", "Der Wendeplatz oben am Birkenhof ist der letzte sichere Ort. Die Zombies kommen den Weg herauf und aus dem Wald. Halte die Barrikaden, überlebe die Wellen.", "Spiel starten", "Wegnetz wird berechnet ...")
	nav_region.bake_finished.connect(func(): hud.overlay_status.text = "Bereit."; if _autotest: _on_start())
	nav_region.bake_navigation_mesh(true)

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.012, 0.016, 0.035)
	sm.sky_horizon_color = Color(0.05, 0.07, 0.1)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.012)
	sm.ground_horizon_color = Color(0.04, 0.05, 0.07)
	sm.sun_angle_max = 3.0
	sm.sun_curve = 0.15
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.2, 0.3)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.ssao_radius = 1.5
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.04, 0.06)
	env.fog_density = 0.01
	env.fog_sky_affect = 0.5
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.5, 0.56, 0.7)
	env.volumetric_fog_emission = Color(0.02, 0.026, 0.04)
	env.volumetric_fog_emission_energy = 0.25
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_anisotropy = 0.55
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.56, 0.64, 0.82)
	moon.light_energy = 0.7
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 140.0
	moon.directional_shadow_split_1 = 0.08
	moon.directional_shadow_split_2 = 0.25
	moon.directional_shadow_split_3 = 0.5
	moon.light_volumetric_fog_energy = 0.6
	add_child(moon)
	moon.look_at_from_position(Vector3(-60, 80, -30), Vector3(0, 0, -40))

func _noise_tex(seed_v: int, freq: float, c0: Color, c1: Color, size: int = 512) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = freq
	nz.fractal_octaves = 5
	t.noise = nz
	t.seamless = true
	t.width = size
	t.height = size
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	t.color_ramp = g
	return t

func _ground_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := (Map.ground_height(x + e, z) - Map.ground_height(x - e, z)) / (2.0 * e)
	var dz := (Map.ground_height(x, z + e) - Map.ground_height(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

# ---------------------------------------------------------------- terrain
func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var W := 320.0
	var n := 160
	var step := W / n
	for j in n + 1:
		for i in n + 1:
			var x := -W / 2.0 + i * step
			var z := -W / 2.0 + j * step
			st.set_uv(Vector2(x, z) / 3.0)
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
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_tex(7, 0.02, Color(0.16, 0.26, 0.09), Color(0.32, 0.42, 0.18))
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
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
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	return mi

func _build_roads() -> void:
	var rw := Map.ROAD_WIDTH / 2.0
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = _noise_tex(11, 0.05, Color(0.18, 0.18, 0.19), Color(0.3, 0.3, 0.31), 256)
	asphalt.roughness = 0.95
	asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gravel := StandardMaterial3D.new()
	gravel.albedo_texture = _noise_tex(13, 0.12, Color(0.38, 0.36, 0.32), Color(0.62, 0.6, 0.55), 256)
	gravel.roughness = 1.0
	gravel.cull_mode = BaseMaterial3D.CULL_DISABLED
	# road
	var zs: Array = []
	var z := Map.ROAD_START - 1.0
	while z <= Map.ROAD_END:
		zs.append(z)
		z += 2.0
	_ribbon(zs, func(zz): return Vector2(Map.road_x(zz) - rw, Map.road_x(zz) + rw), 0.04, 0.45, asphalt)
	# gravel shoulder on the west side below the bay
	var sh: Array = []
	z = -38.0
	while z <= -24.0:
		sh.append(z)
		z += 2.0
	_ribbon(sh, func(zz): return Vector2(Map.road_x(zz) - rw - 3.5, Map.road_x(zz) - rw + 0.2), 0.03, 0.3, gravel)
	# parking bay (built as a ribbon of rows)
	var bz: Array = []
	z = Map.BAY.position.y
	while z <= Map.BAY.end.y:
		bz.append(z)
		z += 2.0
	_ribbon(bz, func(_zz): return Vector2(Map.BAY.position.x, Map.BAY.end.x), 0.05, 0.5, asphalt)
	# gravel track NW
	var tz: Array = []
	z = -50.0
	while z >= -95.0:
		tz.append(z)
		z -= 2.0
	_ribbon(tz, func(zz): return Vector2(Map.track_x(zz) - 1.5, Map.track_x(zz) + 1.5), 0.04, 0.4, gravel)
	# concrete curb around the bay
	var curb_mat := StandardMaterial3D.new()
	curb_mat.albedo_color = Color(0.6, 0.6, 0.57)
	var B := Map.BAY
	_curb(Vector3(B.end.x, 0, B.get_center().y), B.size.y, PI / 2.0, curb_mat)
	_curb(Vector3(B.get_center().x, 0, B.position.y), B.size.x, 0.0, curb_mat)
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
		_scenes[name] = load("res://assets/models/%s.glb" % name)
	return _scenes[name]

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
	if OS.has_environment("REMZ_DEBUG") and not _scenes.has(name + "_dbg"):
		_scenes[name + "_dbg"] = true
		print("FIT %s scale=%s pos=%s" % [name, model.scale, model.position])
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

func _tree(x: float, z: float, big: bool = false) -> void:
	if Map.is_clear_zone(x, z):
		return
	var r := rng.randf()
	var kind := "tree_leaf" if r < 0.6 else ("tree_pine" if r < 0.9 else "tree_dead")
	var h: float = { "tree_leaf": 11.0, "tree_pine": 12.0, "tree_dead": 8.0 }[kind]
	var s := (1.0 if big else 0.75) + rng.randf() * 0.6
	_place(kind, x, z, h, -1.0, s, 0.5)

func _bush(x: float, z: float, s: float) -> void:
	_place("bush", x, z, 2.2, -1.0, s, 0.9)

func _build_props() -> void:
	var rw := Map.ROAD_WIDTH / 2.0
	var forest_edge := func(z: float) -> float: return Map.road_x(z) + rw + (3.5 if z < 40.0 else 3.5 + (z - 40.0) * 0.5)
	for i in 300:
		var z := -60.0 + rng.randf() * 175.0
		var x: float = forest_edge.call(z) + rng.randf() * rng.randf() * 50.0
		_tree(x, z, z < -30.0)
	for i in 160:
		_tree(-30.0 + rng.randf() * 80.0, -62.0 - rng.randf() * 35.0, true)
	for i in 60:
		_tree(Map.STRIP.end.x + 1.5 + rng.randf() * 25.0, -62.0 + rng.randf() * 26.0, true)
	for i in 80:
		var z := -60.0 - rng.randf() * 35.0
		_tree(Map.track_x(z) + 4.0 + rng.randf() * 30.0, z, true)
	# hazel hedge along the east road edge
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
	for i in 22:
		var x := -12.0 + rng.randf() * 28.0
		var zz := -61.0 - rng.randf() * 3.0
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
	# benches, bin, woodpile, stumps, rocks
	for bz in [-57.0, -50.0, -43.0]:
		_place("bench", 10.5, bz, 0.9, -PI / 2.0 + TAU, 1.0, 0.8)
	var bin := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.2
	cyl.height = 0.75
	bin.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.18, 0.42, 0.21)
	bin.material_override = bm
	add_child(bin)
	bin.global_position = Map.ground_pos(10.5, -41.0) + Vector3(0, 0.38, 0)
	_place("woodpile", -5.0, -61.0, 1.2, 0.2, 1.0, 1.2)
	_place("stump", 15.5, -46.0, 0.6, -1.0, 1.0, 0.5)
	_place("stump", -14.0, -70.0, 0.6, -1.0, 1.0, 0.5)
	for i in 10:
		var x := -25.0 + rng.randf() * 50.0
		var zz := -75.0 + rng.randf() * 20.0
		if not Map.is_clear_zone(x, zz):
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
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.78, 0.75, 0.68)
	wall.material_override = wm
	wall.position.y = 2.5
	house.add_child(wall)
	var roof := MeshInstance3D.new()
	var rp := PrismMesh.new()
	rp.size = Vector3(12.5, 3.4, 9.5)
	roof.mesh = rp
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.32, 0.18, 0.14)
	roof.material_override = rm
	roof.position.y = 6.7
	house.add_child(roof)
	var win := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(1.0, 1.2)
	win.mesh = wq
	var winm := StandardMaterial3D.new()
	winm.albedo_color = Color(1.0, 0.8, 0.5)
	winm.emission_enabled = true
	winm.emission = Color(1.0, 0.75, 0.4)
	winm.emission_energy_multiplier = 3.0
	win.material_override = winm
	win.position = Vector3(0, 2.6, 4.02)
	house.add_child(win)
	var hb := StaticBody3D.new()
	var hs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(11, 5, 8)
	hs.shape = hbox
	hs.position.y = 2.5
	hb.add_child(hs)
	house.add_child(hb)
	house.add_to_group("navsource")
	# signpost and road marker
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

func _build_torches() -> void:
	for p in [Vector2(-6, -36), Vector2(6, -36), Vector2(-6, -56)]:
		var base := Map.ground_pos(p.x, p.y)
		var pole := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.04
		c.bottom_radius = 0.05
		c.height = 1.6
		pole.mesh = c
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.23, 0.16, 0.1)
		pole.material_override = pm
		add_child(pole)
		pole.global_position = base + Vector3(0, 0.8, 0)
		var flame := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.12
		s.height = 0.24
		flame.mesh = s
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.6, 0.25)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.55, 0.2)
		fm.emission_energy_multiplier = 6.0
		flame.material_override = fm
		add_child(flame)
		flame.global_position = base + Vector3(0, 1.7, 0)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.23)
		light.light_energy = 3.0
		light.omni_range = 18.0
		light.shadow_enabled = true
		light.light_volumetric_fog_energy = 0.5
		add_child(light)
		light.global_position = base + Vector3(0, 1.7, 0)
		torches.append({ "light": light, "flame": flame, "seed": rng.randf() * 10.0 })

func _build_sky_extras() -> void:
	# stars as a point cloud that follows the player
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_POINTS)
	for i in 900:
		var a := rng.randf() * TAU
		var e := asin(rng.randf() * 0.95 + 0.05)
		st.add_vertex(Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)) * 230.0)
	stars = MeshInstance3D.new()
	stars.mesh = st.commit()
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.8, 0.85, 1.0, 0.8)
	sm.use_point_size = true
	sm.point_size = 2.5
	sm.disable_fog = true
	stars.material_override = sm
	add_child(stars)
	var moon := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 6.0
	s.height = 12.0
	moon.mesh = s
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.9, 0.92, 1.0)
	mm.emission_enabled = true
	mm.emission = Color(0.9, 0.92, 1.0)
	mm.emission_energy_multiplier = 2.0
	mm.disable_fog = true
	moon.material_override = mm
	add_child(moon)
	moon.global_position = Vector3(-60, 80, -30).normalized() * 225.0
	# village lights in the valley to the west
	for i in 40:
		var l := MeshInstance3D.new()
		var ls := SphereMesh.new()
		ls.radius = 0.35
		ls.height = 0.7
		l.mesh = ls
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.82, 0.54) if rng.randf() < 0.7 else Color(1.0, 0.96, 0.86)
		lm.emission_enabled = true
		lm.emission = lm.albedo_color
		lm.emission_energy_multiplier = 3.0
		lm.disable_fog = true
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
	for tc in torches:
		var f: float = 0.75 + 0.25 * sin(t * 11.0 + tc["seed"]) * sin(t * 7.3 + tc["seed"] * 2.0) + 0.1 * sin(t * 23.0 + tc["seed"])
		tc["light"].light_energy = 3.0 * f
		tc["flame"].scale = Vector3.ONE * (0.8 + f * 0.3)
	if player:
		stars.global_position = Vector3(player.global_position.x, 0, player.global_position.z)
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
		[Vector3(0, 0, -48), PI, 0.0],            # bay, looking south down the road
		[Vector3(4, 0, -50), -PI / 2.0, -0.15],   # benches
		[Vector3(-4, 0, -50), 0.35, 0.0],         # gravel track
		[Vector3(0, 0, 10), 0.0, 0.05],           # uphill from the road with the hedge
	]
	if _shot_i == 0 and _shot_t > 0.5 and not _spawned_test:
		_spawned_test = true
		for i in 4:
			spawn_zombie("shambler", Vector2(-2 + i * 1.5, -30 - i * 4), 1.0)
		spawn_zombie("runner", Vector2(3, -36), 1.0)
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
