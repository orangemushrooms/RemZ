# Builds the level from Map (the hand-drawn plan) and wires player / weapons / zombies / waves / HUD.
extends Node3D

var player: Player
var hud: Hud
var weapons: Weapons
var waves: Waves
var skills: Skills
var ambience: Ambience
var zombies_root: Node3D
var barricades: Array = []
var nav_region: NavigationRegion3D
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
	_build_stream()
	_build_forests()
	_build_buildings()
	_build_campsite()
	_build_clutter()
	_build_foliage()
	_build_sky_extras()

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
	ambience.setup(player, Map.ground_pos(Map.FIRE.x, Map.FIRE.y), Map.ground_pos(-40.0, 36.0))
	_spawn_deer()
	hud.show_overlay("BIRKENHOF", "Die Lichtung mit der Waldhütte ist der letzte sichere Ort. Die Zombies kommen von der Nordstrasse über den Weg zur Hütte, über den Waldweg und aus der Wiese. Halte die Barrikaden, überlebe die Wellen.", "Spiel starten", "Wegnetz wird berechnet ...")
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
	env.ambient_light_energy = 1.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.ssao_enabled = not "--no-ssao" in _flags
	env.ssao_intensity = 2.0
	env.ssao_radius = 1.2
	env.ssil_enabled = true
	env.ssil_intensity = 1.6
	env.ssil_radius = 6.0
	env.sdfgi_enabled = false  # leaks light through thin leaf cards and burns them white
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
	# low autumn sun in the north-east, shining across the clearing towards the camp
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
	sun.look_at_from_position(Vector3(80, 24, -130), Vector3(-20, 0, 0))
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.7, 0.7, 0.75)
	fill.light_energy = 0.5
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3(-40, 40, 60), Vector3(0, 0, 0))

func _ground_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := (Map.ground_height(x + e, z) - Map.ground_height(x - e, z)) / (2.0 * e)
	var dz := (Map.ground_height(x, z + e) - Map.ground_height(x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()

# ---------------------------------------------------------------- terrain
func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var W := 360.0
	var n := 240
	var step := W / n
	for j in n + 1:
		for i in n + 1:
			var x := -W / 2.0 + i * step
			var z := -W / 2.0 + j * step
			st.set_uv(Vector2(x, z))
			st.set_color(Color(Map.leaf_weight(x, z), 0, 0))
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

# road ribbon along a polyline
func _road_mesh(pts: Array, width: float, lift: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples: Array = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		var steps := maxi(1, int(len / 2.0))
		for k in steps + (1 if i == pts.size() - 2 else 0):
			var t := float(k) / steps
			var p := a.lerp(b, t)
			var dir := (b - a).normalized()
			samples.append([p, Vector2(-dir.y, dir.x)])
	var vi := 0
	var dist := 0.0
	var prev: Vector2 = samples[0][0]
	for s in samples:
		var p: Vector2 = s[0]
		var nrm: Vector2 = s[1]
		dist += p.distance_to(prev)
		prev = p
		for side: float in [-1.0, 1.0]:
			var q: Vector2 = p + nrm * side * width / 2.0
			st.set_uv(Vector2(0.0 if side < 0 else 1.0, dist / width))
			st.set_normal(_ground_normal(q.x, q.y))
			st.add_vertex(Vector3(q.x, Map.ground_height(q.x, q.y) + lift, q.y))
		if vi > 0:
			var a := (vi - 1) * 2
			st.add_index(a); st.add_index(a + 1); st.add_index(a + 2)
			st.add_index(a + 1); st.add_index(a + 3); st.add_index(a + 2)
		vi += 1
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

func _build_roads() -> void:
	var asphalt := Foliage.pbr("asphalt", 1.0, Color(0.85, 0.85, 0.85))
	asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gravel := Foliage.pbr("gravel", 1.0, Color(1.0, 0.96, 0.9))
	gravel.cull_mode = BaseMaterial3D.CULL_DISABLED
	if "--road-plain" in _flags:
		for m in [asphalt, gravel]:
			m.normal_enabled = false
			m.ao_enabled = false
			m.roughness_texture = null
	for r in Map.ROADS:
		_road_mesh(r["pts"], r["width"], 0.04, asphalt if r["surface"] == "asphalt" else gravel)

func _build_stream() -> void:
	# water surface in the stream bed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = Map.STREAM
	var vi := 0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var nxt: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var prv: Vector2 = pts[maxi(i - 1, 0)]
		var dir := (nxt - prv).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			var q: Vector2 = p + nrm * side * 1.4
			st.set_uv(Vector2(0.0 if side < 0 else 1.0, i * 2.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q.x, Map.ground_height(p.x, p.y) + 0.35, q.y))
		if vi > 0:
			var a := (vi - 1) * 2
			st.add_index(a); st.add_index(a + 1); st.add_index(a + 2)
			st.add_index(a + 1); st.add_index(a + 3); st.add_index(a + 2)
		vi += 1
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.25, 0.35, 0.38, 0.75)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.metallic = 0.6
	wm.roughness = 0.08
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = wm
	add_child(mi)
	# pebbles along the banks
	var stone := Foliage.pbr("rock", 1.0, Color(0.7, 0.68, 0.62))
	for i in 60:
		var t := rng.randf()
		var seg := int(t * (pts.size() - 1))
		var p: Vector2 = pts[seg].lerp(pts[mini(seg + 1, pts.size() - 1)], fmod(t * (pts.size() - 1), 1.0))
		var q := p + Vector2(rng.randf_range(-2.6, 2.6), rng.randf_range(-1.0, 1.0))
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.08, 0.25)
		sm.height = sm.radius * 1.4
		s.mesh = sm
		s.material_override = stone
		add_child(s)
		s.global_position = Map.ground_pos(q.x, q.y) + Vector3(0, sm.radius * 0.3, 0)

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
				bm.specular = 0.12
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

# ---------------------------------------------------------------- forests
const BROADLEAF := ["island_tree_01", "island_tree_02", "island_tree_03", "tree_small_02", "jacaranda_tree"]
const CONIFER := ["fir_tree_01_a", "fir_tree_01_b", "fir_tree_01_c"]

func _tree(x: float, z: float, big: bool = false) -> void:
	if "--no-trees" in _flags:
		return
	if Map.is_clear_zone(x, z):
		return
	var conifer := rng.randf() > 0.7
	var near_camp := Vector2(x, z).distance_to(Map.FIRE) < 95.0
	var pool: Array = CONIFER if conifer else BROADLEAF
	var name: String = pool[rng.randi() % pool.size()]
	if _tree_scene(name) and near_camp and (conifer or rng.randf() < 0.92):
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
	_place(kind, x, z, h, -1.0, s, 0.5)

func _bush(x: float, z: float, s: float) -> void:
	var shrub: String = ["island_tree_02", "tree_small_02", "jacaranda_tree"][rng.randi() % 3]
	if _tree_scene(shrub) and Vector2(x, z).distance_to(Map.FIRE) < 100.0:
		_place_real(shrub, x, z, 0.16 + 0.1 * s, 0.9, -1.0)
		return
	_place("bush", x, z, 2.2, -1.0, s, 0.9)

func _build_forests() -> void:
	# fill each forest block with trees on a jittered grid, denser near the clearing
	for key: String in Map.FORESTS:
		var r: Rect2 = Map.FORESTS[key]
		var far: bool = key.ends_with("hinten") or key.ends_with("ganz") or key == "Wald West"
		var spacing := 7.5 if far else 5.5
		var z := r.position.y + spacing * 0.5
		while z < r.end.y:
			var x := r.position.x + spacing * 0.5
			while x < r.end.x:
				var px := x + rng.randf_range(-spacing * 0.4, spacing * 0.4)
				var pz := z + rng.randf_range(-spacing * 0.4, spacing * 0.4)
				if rng.randf() < 0.85:
					_tree(px, pz, not far)
				x += spacing
			z += spacing
	# undergrowth along the forest edges facing the clearing and paths
	for key: String in Map.FORESTS:
		var r: Rect2 = Map.FORESTS[key]
		if key.ends_with("hinten") or key.ends_with("ganz") or key == "Wald West":
			continue
		var n := int((r.size.x + r.size.y) / 3.0)
		for i in n:
			var side := rng.randi() % 4
			var x: float
			var z: float
			match side:
				0: x = r.position.x + rng.randf() * r.size.x; z = r.position.y + rng.randf_range(0.5, 2.5)
				1: x = r.position.x + rng.randf() * r.size.x; z = r.end.y - rng.randf_range(0.5, 2.5)
				2: x = r.position.x + rng.randf_range(0.5, 2.5); z = r.position.y + rng.randf() * r.size.y
				_: x = r.end.x - rng.randf_range(0.5, 2.5); z = r.position.y + rng.randf() * r.size.y
			if not Map.is_clear_zone(x, z):
				_bush(x, z, 0.6 + rng.randf() * 0.7)

# ---------------------------------------------------------------- buildings
func _building_collider(root: Node3D, size: Vector2, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, height, size.y)
	cs.shape = box
	cs.position.y = height / 2.0
	body.add_child(cs)
	root.add_child(body)
	root.add_to_group("navsource")

func _hut(spec: Dictionary, model_name: String, height: float, fallback_roof: bool) -> Node3D:
	var pos: Vector2 = spec["pos"]
	var size: Vector2 = spec["size"]
	var yaw: float = spec["yaw"]
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(pos.x, pos.y)
	root.rotation.y = yaw
	var scene := _scene(model_name)
	if scene:
		var model: Node3D = scene.instantiate()
		root.add_child(model)
		Weapons._fit_height(model, height)
		model.position.y += height / 2.0
		# stretch the model footprint to the plan's size
		var aabb := AABB()
		var first := true
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = root.global_transform.affine_inverse() * (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
		if aabb.size.x > 0.1 and aabb.size.z > 0.1:
			model.scale = Vector3(model.scale.x * size.x / aabb.size.x, model.scale.y, model.scale.z * size.y / aabb.size.z)
	else:
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(size.x, height * 0.6, size.y)
		wall.mesh = wb
		wall.material_override = Foliage.pbr("planks", 0.5)
		wall.position.y = height * 0.3
		root.add_child(wall)
		if fallback_roof:
			var roof := MeshInstance3D.new()
			var rp := PrismMesh.new()
			rp.size = Vector3(size.x * 1.15, height * 0.4, size.y * 1.15)
			roof.mesh = rp
			roof.material_override = Foliage.pbr("roof", 0.8)
			roof.position.y = height * 0.8
			root.add_child(roof)
	_building_collider(root, size, height)
	return root

func _build_buildings() -> void:
	var wh := _hut(Map.WALDHUETTE, "cabin", 6.5, true)
	# warm window light and a lamp by the door of the Waldhütte
	var wl := OmniLight3D.new()
	wl.light_color = Color(1.0, 0.72, 0.42)
	wl.light_energy = 3.0
	wl.omni_range = 12.0
	wl.shadow_enabled = true
	wl.position = Vector3(0, 2.6, Map.WALDHUETTE["size"].y / 2.0 + 1.5)
	wh.add_child(wl)
	_hut(Map.HOLZAGER, "storage_hut", 6.0, true)
	# firewood stacks beside the Holzager-Hütte
	var hp: Vector2 = Map.HOLZAGER["pos"]
	for i in 4:
		_place("woodpile", hp.x - 10.0 + i * 1.6, hp.y + 6.5, 1.2, 0.0, 1.0, 1.1)

# ---------------------------------------------------------------- campsite
func _build_campsite() -> void:
	var fire := Foliage.campfire(Map.ground_pos(Map.FIRE.x, Map.FIRE.y))
	add_child(fire)
	fire_light = fire.get_node("Light")
	var tripod := _place("tripod_cauldron", Map.FIRE.x, Map.FIRE.y, 1.9, 0.6, 1.0, 0.0)
	_collider(fire, 0.9, 2.0)
	# the four benches around the fire (Bank 1-4 on the plan)
	var bi := 0
	for b in Map.BENCHES:
		var p: Vector2 = b[0]
		var yaw: float = b[1]
		var lb := _place("log_bench", p.x, p.y, 0.55, yaw + TAU, 1.0, 0.9)
		if not lb:
			var seat := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(2.6, 0.18, 0.45)
			seat.mesh = sm
			seat.material_override = Foliage.pbr("planks", 0.7, Color(0.55, 0.45, 0.35))
			add_child(seat)
			seat.global_position = Map.ground_pos(p.x, p.y) + Vector3(0, 0.42, 0)
			seat.rotation.y = yaw
		# blanket, mug, candle on the benches
		if bi == 1:
			_place_at("blanket", p.x, p.y + 0.6, 0.5, 0.45, yaw + TAU)
			_place_at("mug", p.x, p.y - 0.8, 0.5, 0.11)
		if bi == 2:
			_place_at("candle", p.x + 0.7, p.y, 0.5, 0.12)
			_place_at("mug", p.x - 0.6, p.y, 0.5, 0.11)
		bi += 1
	# table and well
	var t := _place("table", Map.TABLE.x, Map.TABLE.y, 0.8, 0.0, 1.0, 1.0)
	if not t:
		var tm := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(1.8, 0.1, 0.9)
		tm.mesh = tb
		tm.material_override = Foliage.pbr("planks", 0.8)
		add_child(tm)
		tm.global_position = Map.ground_pos(Map.TABLE.x, Map.TABLE.y) + Vector3(0, 0.78, 0)
		for lx in [-0.7, 0.7]:
			var leg := MeshInstance3D.new()
			var lb2 := BoxMesh.new()
			lb2.size = Vector3(0.12, 0.75, 0.7)
			leg.mesh = lb2
			leg.material_override = Foliage.pbr("planks", 0.8)
			add_child(leg)
			leg.global_position = Map.ground_pos(Map.TABLE.x + lx, Map.TABLE.y) + Vector3(0, 0.37, 0)
		_place_at("basket", Map.TABLE.x + 0.4, Map.TABLE.y, 0.83, 0.4)
	var w := _place("well", Map.WELL.x, Map.WELL.y, 2.4, 0.0, 1.0, 1.1)
	if not w:
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.05
		cm.height = 1.0
		ring.mesh = cm
		ring.material_override = Foliage.pbr("rock", 1.5, Color(0.75, 0.75, 0.7))
		add_child(ring)
		ring.global_position = Map.ground_pos(Map.WELL.x, Map.WELL.y) + Vector3(0, 0.5, 0)
		_collider(ring, 1.1, 1.0)
	# pumpkins and lanterns around the camp and the hut door
	var wh: Vector2 = Map.WALDHUETTE["pos"]
	var door := Vector2(wh.x - Map.WALDHUETTE["size"].x / 2.0 - 1.2, wh.y)
	var pumpkins := [[door.x, door.y + 1.6, "pumpkin_lantern", 0.55], [door.x - 0.8, door.y + 2.2, "pumpkin", 0.42], [door.x, door.y - 1.6, "pumpkin_lantern", 0.6],
		[Map.FIRE.x - 6.0, Map.FIRE.y + 4.0, "pumpkin", 0.5], [Map.TABLE.x + 1.8, Map.TABLE.y + 0.4, "pumpkin_lantern", 0.5], [Map.WELL.x + 1.6, Map.WELL.y - 0.5, "pumpkin", 0.4]]
	for p in pumpkins:
		_place(p[2], p[0], p[1], p[3], -1.0, 1.0, 0.0)
		if p[2] == "pumpkin_lantern":
			var pl := OmniLight3D.new()
			pl.light_color = Color(1.0, 0.55, 0.15)
			pl.light_energy = 1.2
			pl.omni_range = 4.0
			add_child(pl)
			pl.global_position = Map.ground_pos(p[0], p[1]) + Vector3(0, p[3] * 0.6, 0)
	# mushrooms along the clearing edge
	for i in 30:
		var x := Map.CLEARING.position.x + rng.randf() * Map.CLEARING.size.x
		var z := Map.CLEARING.position.y + rng.randf() * Map.CLEARING.size.y
		var edge := minf(minf(x - Map.CLEARING.position.x, Map.CLEARING.end.x - x), minf(z - Map.CLEARING.position.y, Map.CLEARING.end.y - z))
		if edge > 6.0 or Map.is_clear_zone(x, z) and Vector2(x, z).distance_to(Map.FIRE) < 14.0:
			continue
		var kind := "mushroom_cluster" if rng.randf() < 0.65 else "mushroom_fly"
		_place(kind, x, z, 0.22 + rng.randf() * 0.18, -1.0, 1.0, 0.0)

# ---------------------------------------------------------------- clutter and foliage
func _build_clutter() -> void:
	var clutter := [["fern_02_a", 90, 0.9], ["fern_02_b", 60, 0.9], ["fern_02_c", 40, 0.9], ["fern_02_d", 40, 0.9],
		["grass_medium_02_a", 60, 1.0], ["grass_medium_02_b", 60, 1.0], ["grass_medium_02_c", 60, 1.0], ["grass_medium_02_d", 60, 1.0], ["grass_medium_02_e", 60, 1.0],
		["moss_01_a", 16, 1.0], ["moss_01_b", 16, 1.0], ["moss_01_c", 16, 1.0], ["moss_01_d", 16, 1.0], ["moss_01_g", 16, 1.0], ["moss_01_k", 16, 1.0],
		["dry_branches_medium_01_a", 24, 1.0], ["dry_branches_medium_01_b", 24, 1.0], ["dry_branches_medium_01_c", 24, 1.0],
		["bark_debris_01_a", 16, 1.0], ["bark_debris_01_b", 16, 1.0], ["bark_debris_01_c", 16, 1.0], ["bark_debris_01_d", 16, 1.0]]
	for c in clutter:
		if not _tree_scene(c[0]):
			continue
		for i in int(c[1]):
			var x: float = rng.randf_range(-100.0, 60.0)
			var z: float = rng.randf_range(-40.0, 62.0)
			var is_grass: bool = c[0].begins_with("grass_medium")
			if Map.leaf_weight(x, z) < 0.5 and not is_grass:
				continue
			if is_grass and Map.leaf_weight(x, z) > 0.5 and rng.randf() < 0.7:
				continue
			if Map.on_road(x, z, 0.8) or Map.in_building(x, z, 1.5):
				continue
			if Vector2(x, z).distance_to(Map.FIRE) < 5.0:
				continue
			_place_real(c[0], x, z, c[2] * (0.7 + rng.randf() * 0.6), 0.0)
	for i in 12:
		var x: float = rng.randf_range(-100.0, 40.0)
		var z: float = rng.randf_range(-36.0, 62.0)
		if not Map.is_clear_zone(x, z) and Map.leaf_weight(x, z) > 0.5:
			_place_real(["boulder_01", "tree_stump_01", "dead_tree_trunk_02"][i % 3], x, z, 0.8 + rng.randf() * 0.5, 0.8)
	# mushrooms all over the forest floor
	for i in 260:
		var x: float = rng.randf_range(-105.0, 50.0)
		var z: float = rng.randf_range(-40.0, 64.0)
		if Map.leaf_weight(x, z) < 0.6 or Map.on_road(x, z, 1.0) or Map.in_building(x, z, 1.0):
			continue
		var kind := "mushroom_cluster" if rng.randf() < 0.7 else "mushroom_fly"
		_place(kind, x, z, 0.18 + rng.randf() * 0.2, -1.0, 1.0, 0.0)

func _spawn_deer() -> void:
	var groups := [[Vector2(-70, -18), "stag"], [Vector2(-66, -14), "deer"], [Vector2(-64, -20), "deer"], [Vector2(25, 34), "deer"], [Vector2(28, 38), "deer"], [Vector2(70, 30), "stag"], [Vector2(74, 34), "deer"], [Vector2(-60, 30), "deer"]]
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
		var x: float = r.randf_range(-105.0, 60.0)
		var z: float = r.randf_range(-45.0, 65.0)
		var w := Map.leaf_weight(x, z)
		if r.randf() > w * 0.9 + 0.05:
			return null
		if Map.on_road(x, z) and r.randf() > 0.25:
			return null
		if Map.in_building(x, z):
			return null
		return Map.ground_pos(x, z)
	if not "--no-leaves" in _flags:
		add_child(Foliage.ground_leaves(70000, leaf_sampler, rng))
	var grass_sampler := func(r: RandomNumberGenerator):
		var x: float = r.randf_range(-105.0, 110.0)
		var z: float = r.randf_range(-45.0, 65.0)
		if Map.leaf_weight(x, z) > 0.4:
			return null
		if Map.on_road(x, z, 0.5) or Map.in_building(x, z, 0.5):
			return null
		return Map.ground_pos(x, z)
	if not "--no-grass" in _flags:
		add_child(Foliage.grass(60000, grass_sampler, rng))
	if not "--no-particles" in _flags:
		add_child(Foliage.falling_leaves(Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3(10, 9, 0), Vector3(45, 7, 24)))

func _build_sky_extras() -> void:
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
		l.global_position = Vector3(150.0 + rng.randf() * 60.0, -6.0 + rng.randf() * 3.0, -80.0 + rng.randf() * 200.0)

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
		if skills and skills.is_open:
			skills.close()
		else:
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
		[Vector3(-28, 0, 8), 0.0, 0.03],          # from the Waldweg edge north over the fire to the forest
		[Vector3(-34, 0, -9), -PI / 2.0, -0.02],  # from bench 1 east over the fire towards the Waldhütte
		[Vector3(-20, 0, 20), 2.6, 0.0],          # from the Waldweg south-west to the Holzager hut and stream
		[Vector3(41, 0, -30), 0.0, 0.02],         # down the Weg zur Hütte towards the clearing
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
			spawn_zombie("shambler", Vector2(38 + i * 2.0, -30 - i * 4), 1.0)
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
