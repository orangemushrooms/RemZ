# Builds the Waldhütte Remetschwil level from Map (assets/map, generated from geodata) and wires
# player / weapons / zombies / waves / HUD.
extends Node3D

var player: Player
var hud: Hud
var weapons: Weapons
var waves: Waves
var day_night: DayNightCycle
var cornfield: Node3D
var fill_light: DirectionalLight3D
var skills: Skills
var fireworks: Fireworks
var quickbar: CanvasLayer
var inventory: Inventory
var cheat_menu: CanvasLayer
var forest_keys: ForestKeys
var achievements: Achievements
var barricade_menu: BarricadeMenu
var defences: DefenceSystem
var progression: Progression
var ambience: Ambience
var music: Music
var intro: Intro
var zombies_root: Node3D
var barricades: Array = []
var perimeter: Perimeter                  # palisade ring, its gates are the barricade slots
var hut: HutHealth                        # Waldhütte health: attacked by zombies, repaired with E, lost at zero
var loots: Array = []
var nav_region: NavigationRegion3D
var fire_light: OmniLight3D
var started := false
var over := false
var near_bar = null
var _tower_hint_remaining := 12.0
var notice_board: Node3D
var _notice_open := false
const SECRET_SHOP_NOTICE := "Zwischen den Zeilen steht, von Hand ergänzt:\n\nMan sagt, es gebe einen Laden, der keinen Namen trägt.\nSeine Waren stehen auf keiner Liste. Sein Händler stellt keine Fragen.\nWer ihn findet, versteht, warum niemand von ihm spricht."
var rng := RandomNumberGenerator.new()
var _autotest := false
var _restarted := false      # scene rebuilt by "Nochmal": skip the start menu and the intro
var _shot_t := 0.0
var _shot_i := 0
var _spawned_test := false
var _shooting := false
var _flags: PackedStringArray = []
var _fps_frames := 0
var _fps_time := 0.0
var _fps_done := false
var settings: GameSettings
var stats: RunStats
var leaderboard: CanvasLayer
var difficulty: Dictionary = GameSettings.DIFFICULTIES[1]
var navigation_ready := false
var _perimeter_navigation_dirty := false
var _alive_count := 0
var render_stats := {}

func _ready() -> void:
	rng.seed = 4242
	_autotest = "--autotest" in OS.get_cmdline_user_args()
	_flags = OS.get_cmdline_user_args()
	settings = GameSettings.new()
	add_child(settings)
	difficulty = GameSettings.DIFFICULTIES[settings.difficulty]
	stats = RunStats.new()
	add_child(stats)
	Map._ensure()
	Progression.clear_space()
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
	_build_small_campsite()
	_build_pond()
	_build_fence()
	_build_clutter()
	cornfield = preload("res://scripts/cornfield.gd").new()
	add_child(cornfield)
	cornfield.build(self)
	_build_foliage()
	render_stats = RenderOptimizer.optimize(self)
	print("RENDER_OPTIMIZER ", render_stats)

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.start_pressed.connect(_on_start)
	hud.main_menu_pressed.connect(_to_main_menu)
	hud.set_difficulties(GameSettings.DIFFICULTIES, settings.difficulty, func(i: int):
		settings.difficulty = i
		settings._changed()
		difficulty = GameSettings.DIFFICULTIES[i]
		player.regen_mul = float(difficulty["regen"]))
	player = Player.new()
	player.hud = hud
	add_child(player)
	player.global_position = Map.ground_pos(Map.PLAYER_START.x, Map.PLAYER_START.y) + Vector3(0, 0.3, 0)
	player.flashlight.visible = false
	player.died.connect(_game_over)
	stats.register_player(1, NetSession.player_name)
	leaderboard = preload("res://scripts/leaderboard.gd").new()
	add_child(leaderboard)
	leaderboard.setup(self)
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
	# Palisade sections follow gate construction; navigation is refreshed when their state changes.
	if not "--no-perimeter" in _flags:
		perimeter = Perimeter.new()
		add_child(perimeter)
		perimeter.setup(barricades)
		perimeter.layout_changed.connect(_perimeter_changed)
	waves = Waves.new()
	add_child(waves)
	waves.setup(self, hud, player, weapons)
	waves.wave_started.connect(_restock_huts)
	day_night = DayNightCycle.new()
	add_child(day_night)
	day_night.setup(self, fill_light)
	skills = Skills.new()
	add_child(skills)
	skills.setup(player, weapons, hud, self)
	inventory = Inventory.new()
	add_child(inventory)
	inventory.setup(player, weapons, hud, self)
	fireworks = Fireworks.new()
	add_child(fireworks)
	fireworks.setup(self)
	forest_keys = ForestKeys.new()
	add_child(forest_keys)
	forest_keys.setup(self)
	achievements = Achievements.new()
	add_child(achievements)
	achievements.setup(player, weapons, hud, self)
	barricade_menu = BarricadeMenu.new()
	add_child(barricade_menu)
	barricade_menu.setup(self)
	defences = DefenceSystem.new()
	add_child(defences)
	defences.setup(self)
	progression = Progression.new()
	add_child(progression)
	progression.setup(self)
	quickbar = preload("res://scripts/quickbar.gd").new()
	add_child(quickbar)
	quickbar.setup(self)
	ambience = Ambience.new()
	add_child(ambience)
	ambience.setup(player, Map.ground_pos(Map.FIRE.x, Map.FIRE.y), Map.ground_pos(-40.0, -60.0))
	ambience.day_night = day_night
	intro = Intro.new()
	add_child(intro)
	intro.setup(self, player, settings.env)
	intro.road_reached.connect(func():
		if not NetSession.enabled and waves.wave == 0: waves.start(1))
	cheat_menu = preload("res://scripts/cheat_menu.gd").new()
	cheat_menu.main = self
	add_child(cheat_menu)
	music = Music.new()
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	if not "--no-music" in _flags:
		music.play("title")
	_spawn_deer()
	settings.add_controls(hud.settings_box, false)
	player.regen_mul = float(difficulty["regen"])
	settings.apply()
	for sound in ["pistol", "revolver", "smg", "ak47", "shotgun", "reload", "empty", "hit", "hurt", "growl", "build", "wave", "wood", "wood_hit", "boom", "pickup",
			"zombie_death", "melee", "melee_stab", "grenade_throw", "grenade_bounce", "heartbeat", "land", "weapon_switch", "door_close", "crash"]:
		Sfx.get_stream(sound)
	Zombie.preload_models()
	hud.show_overlay("WALDHÜTTE REMETSCHWIL", "Die Waldhütte am Heitersberg ist der letzte sichere Ort. Du wachst unten an der Sennhofstrasse auf und musst zuerst zur Hütte hinauf. Baue an den vier Zugängen Barrikaden, um nach und nach den Palisadenring zu errichten. Dann kommen sie: von der Sennhofstrasse über den Weg zur Hütte, von der Wiese, über den Weg Richtung Dorf und den Waldweg aus dem Norden. Baue die Sperren in den Toren aus (E), halte sie, überlebe die Wellen, und trag dich in die Bestenliste ein. Die Zombies gehen auch auf die Waldhütte selbst los: fällt sie, ist die Runde verloren. Repariere sie mit E an ihrer Wand.", "Spiel starten", "Wegnetz wird berechnet ...", "start")
	hud.overlay_button.disabled = true
	hud.set_loading(true)
	nav_region.bake_finished.connect(_navigation_baked)
	nav_region.bake_navigation_mesh(true)
	if "--shot-menu" in _flags:
		_shot_menu()
	get_tree().paused = true

# --shot-menu: screenshot the start overlay (logo, loading bar) while the navmesh bakes, then quit
func _shot_menu() -> void:
	for i in 30:
		await get_tree().process_frame
	var dir := ProjectSettings.globalize_path("res://") + "../shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir + "menu.png")
	print("SHOT_MENU_DONE")
	get_tree().quit()

func _perimeter_changed() -> void:
	_perimeter_navigation_dirty = true
	call_deferred("_refresh_perimeter_navigation")

func _refresh_perimeter_navigation() -> void:
	if not navigation_ready or nav_region.is_baking() or not _perimeter_navigation_dirty: return
	_perimeter_navigation_dirty = false
	nav_region.bake_navigation_mesh(true)

func _navigation_baked() -> void:
	if navigation_ready:
		_refresh_perimeter_navigation()
		return
	# The baked region must reach the navigation server before validating key paths.
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	var nav_map := nav_region.get_navigation_map()
	var start := Map.ground_pos(Map.PLAYER_START.x, Map.PLAYER_START.y)
	# Baking and publishing the asynchronous map iteration are separate steps.
	var deadline := Time.get_ticks_msec() + 15000
	while not NavigationServer3D.map_get_closest_point_owner(nav_map, start).is_valid() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	if not forest_keys.populate():
		get_tree().paused = true
		hud.overlay_status.text = "Schlüsselplätze konnten nicht vorbereitet werden. Bitte neu starten."
		return
	get_tree().paused = true
	navigation_ready = true
	hud.overlay_button.disabled = false
	hud.overlay_status.text = "Bereit."
	hud.set_loading(false)
	NetSession.attach(self)
	if NetSession.restart_pending and not NetSession.enabled:
		# "Nochmal" after a death: straight into the next round, no start menu and no intro
		NetSession.restart_pending = false
		_restarted = true
		_on_start()
	if _autotest or "--benchmark" in _flags or "--intro-test" in _flags:
		_on_start()
	for f in _flags:
		if f.begins_with("--view="):
			_shot_view(f.substr(7))
		elif f.begins_with("--views="):
			_shot_views(f.substr(8))
		elif f == "--shot-ui":
			_shot_ui()

# --views=x,z,yaw[,pitch[,hour]];...: like --view but several spots in one run, saved as shots/view_N.png
func _shot_views(spec: String) -> void:
	_on_start()
	for i in 20:
		await get_tree().process_frame
	if "--spawn-drops" in _flags:
		# the three supply drops side by side on the plaza for visual checks
		var k := 0
		for kind in ["ammo", "grenade", "medkit"]:
			var drop := Pickup.new()
			drop.setup(kind)
			add_child(drop)
			drop.global_position = Map.ground_pos(4.0 + k * 0.8, -2.0) + Vector3(0, 0.05, 0)
			k += 1
	var dir := ProjectSettings.globalize_path("res://") + "../shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	for part in spec.split(";"):
		var a := part.split(",")
		if a.size() < 3:
			continue
		if a.size() > 4 and day_night:
			day_night.set_time_hours(float(a[4]))
		player.global_position = Map.ground_pos(float(a[0]), float(a[1])) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.rotation.y = float(a[2])
		var pitch := float(a[3]) if a.size() > 3 else 0.0
		player.pitch = pitch
		player.head.rotation.x = pitch
		for i in 14:
			await get_tree().process_frame
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 1500000:
			await get_tree().process_frame
			frames += 1
		print("VIEW_FPS %d %.1f at %s" % [n, frames / ((Time.get_ticks_usec() - t0) / 1000000.0), player.global_position])
		get_viewport().get_texture().get_image().save_png(dir + "view_%d.png" % n)
		n += 1
	print("SHOT_VIEWS_DONE %d" % n)
	get_tree().quit()

# --shot-ui: screenshots of inventory, skills, pause menu tabs and the game-over screen into shots/ui_*.png
func _shot_ui() -> void:
	_on_start()
	for i in 20:
		await get_tree().process_frame
	var dir := ProjectSettings.globalize_path("res://") + "../shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := func(name: String) -> void:
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(dir + "ui_%s.png" % name)
	for id in ["revolver", "smg", "shotgun"]:
		weapons.unlock(id)
	inventory.add_mushroom("steinpilz")
	inventory.add_mushroom("fliegenpilz")
	player.add_score(640)
	stats.kills = 17; stats.headshots = 6; stats.shots = 90; stats.hits = 52; stats.best_streak = 5; stats.seconds = 412.0
	inventory.open()
	await shot.call("inventory")
	inventory.close()
	skills.open()
	await shot.call("skills")
	skills.close()
	player.hp = 22.0
	hud.set_health(player.hp)
	hud.damage_flash(0.8)
	hud.streak(4, 20)
	spawn_zombie("shambler", Vector2(player.global_position.x + 6.0, player.global_position.z), 1.0)
	await shot.call("hud_lowhp")
	_pause()
	await shot.call("pause")
	hud.show_tab("difficulty")
	await shot.call("pause_difficulty")
	hud.show_tab("settings")
	await shot.call("pause_settings")
	hud.show_tab("achievements")
	await shot.call("pause_achievements")
	_on_start()
	for i in 4:
		await get_tree().process_frame
	waves.completed = 4
	player.damage(10000.0)
	await shot.call("gameover")
	hud.show_tab("records")
	await shot.call("gameover_records")
	print("SHOT_UI_DONE")
	get_tree().quit()

# --view=x,z,yaw[,pitch]: start, teleport, screenshot to shots/view.png, quit (for checking single spots)
func _shot_view(spec: String) -> void:
	var a := spec.split(",")
	_on_start()
	for i in 20:
		await get_tree().process_frame
	player.global_position = Map.ground_pos(float(a[0]), float(a[1])) + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.rotation.y = float(a[2])
	var pitch := float(a[3]) if a.size() > 3 else 0.0
	player.pitch = pitch
	player.head.rotation.x = pitch
	for i in 12:
		await get_tree().process_frame
	var dir := ProjectSettings.globalize_path("res://") + "../shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir + "view.png")
	print("SHOT_VIEW_DONE")
	get_tree().quit()

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.1
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
	env.volumetric_fog_enabled = not "--no-vfog" in _flags
	env.volumetric_fog_density = 0.0025
	env.volumetric_fog_albedo = Color(0.55, 0.56, 0.52)
	env.volumetric_fog_emission = Color(0.8, 0.65, 0.45)
	env.volumetric_fog_emission_energy = 0.02
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_ambient_inject = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.08
	AlpineAtmosphere.apply(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# The day/night controller positions and colours these existing lights.
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
	fill_light = fill
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
	_build_skirt(ext)

# coarse ground beyond the playable extent (heights clamped to the edge) so the horizon is never empty,
# plus the villages of Sennhof / Remetschwil from OSM footprints as a backdrop in the east and south-east
func _build_skirt(ext: Rect2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 10.0
	var x0 := ext.position.x - 500.0
	var z0 := ext.position.y - 500.0
	var nx := int((ext.size.x + 1000.0) / step) + 1
	var nz := int((ext.size.y + 1000.0) / step) + 1
	for j in nz:
		for i in nx:
			var x := x0 + i * step
			var z := z0 + j * step
			var inside := ext.grow(-step).has_point(Vector2(x, z))
			var h := Map.ground_height(x, z) - (0.0 if not inside else 30.0)   # sink the part under the real terrain
			st.set_uv(Vector2(x, z))
			st.set_color(Color(0.0, 1.0, 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x, h - 0.15, z))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + nx)
			st.add_index(a + 1); st.add_index(a + nx + 1); st.add_index(a + nx)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Foliage.terrain_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	add_child(preload("res://scripts/village_buildings.gd").new().build())
	_village_props()

# Farm yard details that the aerial shows around Sennhof (all outside the playable bounds, decoration only):
# a row of wrapped silage bales east of the big barn, a tractor in the yard between the barns, a car on the
# Parkplatz Sennhof beside the big hall and one parked along the village street.
func _village_props() -> void:
	var root := Node3D.new()
	root.name = "VillageProps"
	add_child(root)
	for spec in [["silage_bales", 4.8, Vector2(247.0, 280.0), PI / 2.0], ["tractor", 3.7, Vector2(223.0, 296.0), 0.3],
			["car_estate", 4.4, Vector2(149.0, 250.5), 0.15], ["car_estate", 4.4, Vector2(186.0, 291.0), PI / 2.0 + 0.05]]:
		var holder := Node3D.new()
		root.add_child(holder)
		holder.position = Map.ground_pos(spec[2].x, spec[2].y) - Vector3(0, 0.25, 0)
		var n := _prop(holder, spec[0], spec[1], "x", Vector3.ZERO, spec[3])
		if n:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).add_to_group("render_backdrop")

# road ribbon along a polyline
func _road_mesh(pts: Array, width: float, lift: float, mat: Material, fade: bool = true) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples: Array = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		var steps := maxi(1, ceili(len / 0.25))
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
	# Subdivide across the width too: a single quad bridges the roadbed and can
	# disappear below the terrain, especially where gravel tracks join the road.
	var across := maxi(1, ceili(width / 0.25))
	var stride := across + 1
	for s in samples:
		var p: Vector2 = s[0]
		var nrm: Vector2 = s[1]
		dist += p.distance_to(prev)
		prev = p
		# fade the ribbon in and out over 6 m so it merges with the gravel of the clearing / the forest floor
		var opacity := 1.0 if not fade else clampf(minf(dist, total - dist) / 6.0, 0.0, 1.0)
		for column in stride:
			var side := float(column) / across * 2.0 - 1.0
			var q: Vector2 = p + nrm * side * width / 2.0
			st.set_uv(Vector2((0.5 + side * 0.5) * width / 5.0, dist / 5.0))
			st.set_color(Color(1, 1, 1, opacity))
			st.set_normal(Map.ground_normal(q.x, q.y))
			st.add_vertex(Vector3(q.x, Map.surface_height(q.x, q.y) + lift, q.y))
		if vi > 0:
			for column in across:
				var a := (vi - 1) * stride + column
				st.add_index(a); st.add_index(a + stride); st.add_index(a + 1)
				st.add_index(a + 1); st.add_index(a + stride); st.add_index(a + stride + 1)
		vi += 1
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a flat ribbon on the ground only shadows itself
	add_child(mi)

func _build_roads() -> void:
	var asphalt := Foliage.pbr("ph_asphalt", 1.0, Color(0.58, 0.58, 0.56))
	asphalt.roughness_texture = null
	asphalt.roughness = 0.97
	asphalt.metallic_specular = 0.2
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
		# Dirt tracks cross steeper cell creases and need a little more clearance.
		_road_mesh(r["pts"], r["width"], 0.04 if r["surface"] != "dirt" else 0.05, mat, r["surface"] != "asphalt")

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

# Meshy prop fitted by one dimension: axis "x" / "z" = length along that local axis, "y" = height. The model's
# longest horizontal extent is turned onto local +x first, so every prop's length runs along x regardless of how
# Meshy oriented it; PROP_YAW adds a per-model correction (flip / quarter turn) found with tests/prop_info.gd.
# Returns null when the GLB is missing so the caller can keep its primitive version.
const PROP_YAW := {
	"log_fountain": 0.0, "log_bench_beam": 0.0, "log_picnic_table": 0.0, "fire_pit": 0.0, "fallen_log": 0.0,
	"workbench": 0.0, "guidepost": 0.0, "info_board": 0.0, "waste_bin": 0.0, "ammo_crate": 0.0, "ammo_pack": 0.0, "medkit": 0.0,
}

# albedo tint per model: Meshy renders weathered wood almost white, the site photos show grey-brown
const PROP_TINT := { "log_fountain": Color(0.95, 0.93, 0.9), "fallen_log": Color(0.82, 0.8, 0.74), "log_bench_beam": Color(0.92, 0.9, 0.87), "fence_post_wire": Color(0.62, 0.58, 0.5), "deer_feeder": Color(0.8, 0.76, 0.68) }

func _prop(parent: Node3D, name: String, size: float, axis: String, local_pos: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> Node3D:
	var scene := _scene(name)
	if not scene:
		return null
	var holder := Node3D.new()
	var model: Node3D = scene.instantiate()
	holder.add_child(model)
	parent.add_child(holder)
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (model.global_transform.affine_inverse() * (mi as Node3D).global_transform) * (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if aabb.size.length() <= 0.0:
		return holder
	# longest horizontal extent onto +x
	var turn := 0.0
	if aabb.size.z > aabb.size.x * 1.15:
		turn = PI / 2.0
	var ext := aabb.size
	if turn != 0.0:
		ext = Vector3(aabb.size.z, aabb.size.y, aabb.size.x)
	var ref := ext.y if axis == "y" else (ext.z if axis == "z" else ext.x)
	var s := size / maxf(ref, 0.001)
	model.scale = Vector3.ONE * s
	model.rotation.y = turn + float(PROP_YAW.get(name, 0.0))
	# centre horizontally, bottom on the ground
	var c := aabb.get_center()
	var offset := Vector3(-c.x, -aabb.position.y, -c.z) * s
	model.position = offset.rotated(Vector3.UP, model.rotation.y)
	holder.position = local_pos
	holder.rotation.y = yaw
	var tint: Color = PROP_TINT.get(name, Color.WHITE)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if tint != Color.WHITE:
			for i in inst.mesh.get_surface_count():
				var mat := inst.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var dup: BaseMaterial3D = mat.duplicate()
					dup.albedo_color = dup.albedo_color * tint
					# weathered wood is matte: no sky reflection that turns the grey logs pale blue
					dup.roughness = 1.0
					dup.metallic_specular = 0.15
					inst.set_surface_override_material(i, dup)
	return holder

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

func _tex_or_null(short: String) -> Texture2D:
	return Foliage._tex(Foliage.TEX + short + ".jpg")

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
	Trees.shadow_cells.clear()
	Trees.build(self, Map.TREES, Map.SHRUBS, Map.FIRE, rng, true, 1.0, 65.0)
	# border forest outside the playable area: a third of the cards, no shadows (it is never closer than ~60 m)
	if not "--no-border" in _flags:
		Trees.build(self, Map.BORDER_TREES, [], Map.FIRE, rng, false, 0.35, 0.0)
	Trees.understory(self, Map.FERNS, Map.LOGS, Map.FIRE, rng)
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
func _walls(root: Node3D, size: Vector2, y0: float, h: float, thick: float, mat: Material, opening: Variant) -> void:
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	var openings: Array = opening if opening is Array else [opening]
	for side in ["w", "e", "n", "s"]:
		var horizontal: bool = side == "n" or side == "s"
		var length: float = size.x if horizontal else size.y
		var pieces: Array = [[-length / 2.0, length / 2.0, y0, y0 + h]]
		for hole: Dictionary in openings:
			if hole.get("side", "") != side:
				continue
			var remaining: Array = []
			for pc in pieces:
				var a := maxf(pc[0], hole.along - hole.width / 2.0)
				var b := minf(pc[1], hole.along + hole.width / 2.0)
				var bottom := maxf(pc[2], y0 + hole.bottom)
				var top := minf(pc[3], y0 + hole.top)
				if b <= a or top <= bottom:
					remaining.append(pc)
				else:
					remaining.append_array([[pc[0], a, pc[2], pc[3]], [b, pc[1], pc[2], pc[3]], [a, b, pc[2], bottom], [a, b, top, pc[3]]])
			pieces = remaining
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

func _restock_huts(number: int) -> void:
	for item in loots:
		if is_instance_valid(item) and item is Loot and item.renewable:
			item.restock(number)

func _loot(root: Node3D, kind: String, id: String, label: String, local_pos: Vector3, model: String, height: float, yaw: float = 0.0, first_wave := 0) -> void:
	var l := Loot.new()
	l.setup(kind, id, label)
	l.renewable = true
	l.first_wave = first_wave
	l.restock(0)
	root.add_child(l)
	l.position = local_pos
	l.rotation.y = yaw
	var scene := _scene(model)
	if scene:
		var m: Node3D = scene.instantiate()
		l.add_child(m)
		Weapons._fit_height(m, height)
		m.position.y += height / 2.0
	elif kind != "ammo":
		_box(l, Vector3(0.6, 0.35, 0.4), Vector3(0, 0.18, 0), Foliage.pbr("planks", 0.8, Color(0.5, 0.42, 0.3)))
	if kind == "ammo":
		# olive ammunition crate with a lid
		if not _prop(l, "ammo_crate", 0.66, "x"):
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

# ridge cap, rafter ends under the eaves, gutters: the cheap details that make a roof read as real
func _roof_details(parent: Node3D, size: Vector2, y: float, height: float, overhang: float, gable: bool) -> void:
	var wood := _plain(Color(0.28, 0.18, 0.12), 0.85)
	var zinc := _plain(Color(0.55, 0.56, 0.58), 0.4, 0.6)
	var along_x := size.x >= size.y
	var hx := size.x / 2.0 + overhang
	var hz := size.y / 2.0 + overhang
	var r := (absf(size.x - size.y) / 2.0) if not gable else (hx if along_x else hz)
	# ridge cap
	if along_x:
		_box(parent, Vector3(r * 2.0 + 0.2, 0.09, 0.32), Vector3(0, y + height + 0.03, 0), zinc)
	else:
		_box(parent, Vector3(0.32, 0.09, r * 2.0 + 0.2), Vector3(0, y + height + 0.03, 0), zinc)
	# rafter ends along the long eaves and gutters
	var pitch := atan2(height, (hz if along_x else hx))
	var n := int((size.x if along_x else size.y) / 0.7)
	for k in n + 1:
		var t := -0.5 + float(k) / n
		for side in [-1.0, 1.0]:
			var rafter := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(0.08, 0.14, overhang + 0.6) if along_x else Vector3(overhang + 0.6, 0.14, 0.08)
			rafter.mesh = rb
			rafter.material_override = wood
			if along_x:
				rafter.position = Vector3(t * size.x, y - 0.1 + tan(pitch) * (overhang + 0.3) * 0.5, side * (hz - (overhang + 0.3) / 2.0))
				rafter.rotation.x = -side * pitch
			else:
				rafter.position = Vector3(side * (hx - (overhang + 0.3) / 2.0), y - 0.1 + tan(pitch) * (overhang + 0.3) * 0.5, t * size.y)
				rafter.rotation.z = side * pitch
			parent.add_child(rafter)
	for side in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = 0.06
		gm.bottom_radius = 0.06
		gm.height = (size.x if along_x else size.y) + overhang * 2.0
		g.mesh = gm
		g.material_override = zinc
		if along_x:
			g.position = Vector3(0, y - 0.05, side * (hz + 0.02))
			g.rotation.z = PI / 2.0
		else:
			g.position = Vector3(side * (hx + 0.02), y - 0.05, 0)
			g.rotation.x = PI / 2.0
		parent.add_child(g)

# Gable roof ("Satteldach") with the ridge along z (along_x = false) or x, separate overhangs for the gable ends and
# the two eave sides (over_eave.x = negative axis side, .y = positive side), a thin slab with fascia boards and a
# closed underside so the wide gable overhangs read as real roof structure (Waldhütte photos 14, 17, 19).
func _gable_roof(parent: Node3D, size: Vector2, y: float, height: float, over_gable: Vector2, over_eave: Vector2, mat: Material, along_x: bool, under_mat: Material = null) -> void:
	# work in a frame where the ridge runs along "v" and the slopes fall along "u"; over_gable.x / .y = overhang at the
	# negative / positive end of the ridge, over_eave.x / .y = overhang on the negative / positive slope side
	var half_u := (size.x if not along_x else size.y) / 2.0
	var wall_v := (size.y if not along_x else size.x) / 2.0
	var v_neg := -(wall_v + over_gable.x)
	var v_pos := wall_v + over_gable.y
	var slope := height / half_u
	var u_neg := -(half_u + over_eave.x)
	var u_pos := half_u + over_eave.y
	var thick := 0.14
	var st_top := SurfaceTool.new()
	st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
	# soffit and fascias in dark boards, a separate surface so the tile texture never shows from below
	var st_under := SurfaceTool.new()
	st_under.begin(Mesh.PRIMITIVE_TRIANGLES)
	var to_local := func(u: float, yy: float, v: float) -> Vector3:
		return Vector3(v, yy, u) if along_x else Vector3(u, yy, v)
	# lambdas capture by value, so the target tool is passed explicitly
	var quad := func(tool: SurfaceTool, pts: Array, n: Vector3) -> void:
		for t in [[pts[0], pts[1], pts[2]], [pts[0], pts[2], pts[3]]]:
			for p: Vector3 in t:
				tool.set_normal(n)
				tool.set_uv(Vector2(p.x + p.z, p.y) * 0.5)
				tool.add_vertex(p)
	var top := y + height
	for side: float in [-1.0, 1.0]:
		var u_edge := u_pos if side > 0.0 else u_neg
		var y_edge := top - slope * absf(u_edge)
		var n_top := Vector3(side, 1.0 / slope, 0.0).normalized() if slope > 0.0 else Vector3.UP
		var n3: Vector3 = Vector3(0.0, n_top.y, n_top.x) if along_x else n_top
		# top surface
		var a: Vector3 = to_local.call(0.0, top, v_neg)
		var b: Vector3 = to_local.call(u_edge, y_edge, v_neg)
		var c: Vector3 = to_local.call(u_edge, y_edge, v_pos)
		var d: Vector3 = to_local.call(0.0, top, v_pos)
		if side > 0.0:
			quad.call(st_top, [a, d, c, b], n3)
		else:
			quad.call(st_top, [a, b, c, d], n3)
		# underside (soffit), same plane lowered by the slab thickness
		var a2: Vector3 = to_local.call(0.0, top - thick, v_neg)
		var b2: Vector3 = to_local.call(u_edge, y_edge - thick, v_neg)
		var c2: Vector3 = to_local.call(u_edge, y_edge - thick, v_pos)
		var d2: Vector3 = to_local.call(0.0, top - thick, v_pos)
		if side > 0.0:
			quad.call(st_under, [a2, b2, c2, d2], -n3)
		else:
			quad.call(st_under, [a2, d2, c2, b2], -n3)
		# eave fascia
		var fn: Vector3 = to_local.call(side, 0.0, 0.0)
		if side > 0.0:
			quad.call(st_under, [b, c, c2, b2], fn)
		else:
			quad.call(st_under, [c, b, b2, c2], fn)
		# gable fascias (both ends) for this slope
		for gs: float in [-1.0, 1.0]:
			var gv := v_pos if gs > 0.0 else v_neg
			var p0: Vector3 = to_local.call(0.0, top, gv)
			var p1: Vector3 = to_local.call(u_edge, y_edge, gv)
			var p2: Vector3 = to_local.call(u_edge, y_edge - thick, gv)
			var p3: Vector3 = to_local.call(0.0, top - thick, gv)
			var gn: Vector3 = to_local.call(0.0, 0.0, gs)
			if (gs > 0.0) == (side > 0.0):
				quad.call(st_under, [p0, p1, p2, p3], gn)
			else:
				quad.call(st_under, [p0, p3, p2, p1], gn)
	st_top.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st_top.commit()
	mi.material_override = mat
	parent.add_child(mi)
	st_under.generate_tangents()
	var under := MeshInstance3D.new()
	under.mesh = st_under.commit()
	under.material_override = under_mat if under_mat else _plain(Color(0.22, 0.14, 0.09), 0.9)
	parent.add_child(under)

# ridge cap, purlins protruding under the gable overhangs with knee braces, rafter ends and gutters along the eaves
func _gable_roof_details(parent: Node3D, size: Vector2, y: float, height: float, over_gable: Vector2, over_eave: Vector2, along_x: bool, wall_mat: Material) -> void:
	var wood := _plain(Color(0.28, 0.18, 0.12), 0.85)
	var zinc := _plain(Color(0.24, 0.25, 0.27), 0.5, 0.5)   # weathered dark sheet metal (photos 14, 19)
	var half_u := (size.x if not along_x else size.y) / 2.0
	var wall_v := (size.y if not along_x else size.x) / 2.0
	var v_neg := -(wall_v + over_gable.x)
	var v_pos := wall_v + over_gable.y
	var v_mid := (v_neg + v_pos) / 2.0
	var v_len := v_pos - v_neg
	var slope := height / half_u
	var top := y + height
	var place := func(node: Node3D, u: float, yy: float, v: float) -> void:
		node.position = Vector3(v, yy, u) if along_x else Vector3(u, yy, v)
	# ridge cap: a low angled cap sitting on the ridge (two thin boards), not a light slab
	for cs: float in [-1.0, 1.0]:
		var board := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(0.24, 0.03, v_len + 0.06) if not along_x else Vector3(v_len + 0.06, 0.03, 0.24)
		board.mesh = bmesh
		board.material_override = zinc
		var tilt := atan(slope)
		if along_x:
			board.position = Vector3(v_mid, top + 0.035 - sin(tilt) * 0.11, cs * cos(tilt) * 0.11)
			board.rotation.x = cs * tilt
		else:
			board.position = Vector3(cs * cos(tilt) * 0.11, top + 0.035 - sin(tilt) * 0.11, v_mid)
			board.rotation.z = -cs * tilt
		parent.add_child(board)
	# closed gable triangles between the wall top and the roof, in the wall material
	for gs: float in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var v := gs * (wall_v + 0.04)
		var pts := [Vector3(-half_u, y - 0.14, v), Vector3(half_u, y - 0.14, v), Vector3(0, top - 0.14, v)]
		if along_x:
			pts = [Vector3(v, y - 0.14, -half_u), Vector3(v, y - 0.14, half_u), Vector3(v, top - 0.14, 0)]
		var n := Vector3(0, 0, gs) if not along_x else Vector3(gs, 0, 0)
		# Godot front faces are clockwise; exchanging the ridge axes reverses winding.
		var order := [0, 2, 1] if (gs > 0.0) != along_x else [0, 1, 2]
		for i in order:
			st.set_normal(n)
			st.set_uv(Vector2(pts[i].x + pts[i].z, pts[i].y) * 0.5)
			st.add_vertex(pts[i])
		st.generate_tangents()
		var tri := MeshInstance3D.new()
		tri.mesh = st.commit()
		tri.material_override = wall_mat
		parent.add_child(tri)
	# purlins under the gable overhangs: ridge purlin plus one per slope, with knee braces at the wall
	for gs: float in [-1.0, 1.0]:
		var og := over_gable.y if gs > 0.0 else over_gable.x
		if og > 0.4:
			for pu: float in [0.0, -0.58, 0.58]:
				var u := pu * half_u
				var py := top - slope * absf(u) - 0.14 - 0.09 - slope * 0.07
				var beam := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.14, 0.18, og + 0.9) if not along_x else Vector3(og + 0.9, 0.18, 0.14)
				beam.mesh = bm
				beam.material_override = wood
				place.call(beam, u, py, gs * (wall_v + og / 2.0 - 0.45))
				parent.add_child(beam)
				if pu != 0.0:
					# diagonal brace from the wall down-inward to the purlin's outer end
					var brace := MeshInstance3D.new()
					var bb := BoxMesh.new()
					var run := og * 0.85
					var drop := og * 0.85
					bb.size = Vector3(0.1, 0.1, sqrt(run * run + drop * drop)) if not along_x else Vector3(sqrt(run * run + drop * drop), 0.1, 0.1)
					brace.mesh = bb
					brace.material_override = wood
					place.call(brace, u, py - 0.1 - drop / 2.0, gs * (wall_v + run / 2.0))
					if along_x:
						brace.rotation.z = gs * atan2(drop, run)
					else:
						brace.rotation.x = -gs * atan2(drop, run)
					parent.add_child(brace)
	# rafter ends and gutters along both eaves
	var n_rafters := int(v_len / 0.7)
	for side: float in [-1.0, 1.0]:
		var over := over_eave.y if side > 0.0 else over_eave.x
		var u_edge := side * (half_u + over)
		var y_edge := top - slope * absf(u_edge)
		for k in n_rafters + 1:
			var v := v_neg + 0.1 + (v_len - 0.2) * float(k) / n_rafters
			var rafter := MeshInstance3D.new()
			var rb := BoxMesh.new()
			# Length follows the slope; keep the timber ends inside the roof edge.
			var run := over + 0.5 - 0.08
			var len := run * sqrt(1.0 + slope * slope)
			rb.size = Vector3(len, 0.13, 0.08) if not along_x else Vector3(0.08, 0.13, len)
			rafter.mesh = rb
			rafter.material_override = wood
			var u_mid := side * (half_u + over - 0.08 - run / 2.0)
			place.call(rafter, u_mid, top - slope * absf(u_mid) - 0.14 - 0.065 * sqrt(1.0 + slope * slope), v)
			if along_x:
				rafter.rotation.x = side * atan(slope)
			else:
				rafter.rotation.z = -side * atan(slope)
			parent.add_child(rafter)
		var g := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = 0.06
		gm.bottom_radius = 0.06
		gm.height = v_len
		g.mesh = gm
		g.material_override = zinc
		place.call(g, u_edge + side * 0.03, y_edge - 0.16, v_mid)
		if along_x:
			g.rotation.z = PI / 2.0
		else:
			g.rotation.x = PI / 2.0
		parent.add_child(g)

func _hut_door(root: Node3D, at: Vector3, yaw: float, w: float, h: float, text: String, key: String, mat: Material) -> Door:
	var door := Door.new()
	door.main = self
	door.key_id = key
	door.setup(w, h, text, mat)
	# Dynamic colliders must not become permanent holes in the baked navigation mesh.
	add_child(door)
	door.global_transform = root.global_transform * Transform3D(Basis(Vector3.UP, yaw), at)
	loots.append(door)
	return door

func _waldhuette() -> Node3D:
	# Photos 13, 14, 15, 17, 19, 22: concrete garage storey with the garage door in the west face (north end), red
	# board upper storey, gable roof with the ridge east-west (west gable towards the track, wide overhang on knee
	# braces), the outside stair along the north face rising east to the upper door, the east side buried in the
	# slope. Local axes: -x west, -z north.
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
	# horizontal tongue-and-groove boards, red-brown paint (tools/gen_hut_textures.py), 1 m tile = 9 boards
	var wood := _mat("ph_boards", 1.0, Color(1.0, 1.0, 1.0))
	wood.roughness_texture = _tex_or_null("ph_boards_rough")
	var dark_wood := _plain(Color(0.28, 0.14, 0.09), 0.75)
	# dark grey corrugated fibre-cement sheets with a slight sheen (photos 14, 17)
	var roof := _mat("ph_corrugated", 0.6, Color(0.5, 0.51, 0.53))
	roof.roughness_texture = null
	roof.roughness = 0.88
	roof.metallic = 0.04
	roof.metallic_specular = 0.25
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	# garage storey: concrete walls with the garage door in the west face (north end), enterable (photos 14, 17)
	_walls(root, Vector2(size.x, size.y), 0.0, base_h, 0.3, concrete, { "side": "w", "along": -hz + 1.9, "width": 2.6, "bottom": 0.0, "top": 2.1 })
	_slab(root, Vector3(size.x, 0.1, size.y), Vector3(0, -0.05, 0), _mat("ph_concrete", 0.6, Color(0.7, 0.7, 0.68)))
	var floor_wood := _mat("planks", 0.8, Color(0.52, 0.42, 0.31))
	_slab(root, Vector3(size.x, 0.25, size.y), Vector3(0, base_h + 0.125, 0), floor_wood)
	_walls(root, Vector2(size.x + 0.16, size.y + 0.16), base_h + 0.25, wall_h - 0.25, 0.18, wood,
		{ "side": "n", "along": hx - 0.9, "width": 1.2, "bottom": 0.0, "top": 2.0 })
	# The now-enterable upper room has a small supply table and bench.
	var upper_floor := base_h + 0.25
	_slab(root, Vector3(2.0, 0.10, 0.75), Vector3(hx - 1.4, upper_floor + 0.78, hz - 1.0), floor_wood)
	for x: float in [hx - 2.25, hx - 0.55]:
		_box(root, Vector3(0.12, 0.75, 0.65), Vector3(x, upper_floor + 0.375, hz - 1.0), dark_wood)
	_slab(root, Vector3(0.55, 0.45, 2.2), Vector3(-hx + 0.7, upper_floor + 0.225, hz - 1.8), floor_wood)
	_loot(root, "ammo", "", "Hüttenvorrat", Vector3(hx - 1.4, upper_floor + 0.84, hz - 1.0), "", 0.3)
	_loot(root, "weapon", "smg", "MP5", Vector3(hx - 2.2, upper_floor + 0.84, hz - 1.0), "smg", 0.3, 0.0, 3)
	# inside: workbench with an ammunition crate, shotgun and MP5 on the wall
	if not _prop(root, "workbench", 2.2, "x", Vector3(hx - 1.2, 0.0, hz - 0.6)):
		_box(root, Vector3(2.2, 0.08, 0.7), Vector3(hx - 1.2, 0.85, hz - 0.6), Foliage.pbr("planks", 0.8, Color(0.5, 0.42, 0.3)))
		for lx in [hx - 2.1, hx - 0.3]:
			_box(root, Vector3(0.1, 0.85, 0.6), Vector3(lx, 0.42, hz - 0.6), Foliage.pbr("planks", 0.8, Color(0.4, 0.33, 0.25)))
	_loot(root, "ammo", "", "Munitionskiste", Vector3(hx - 1.2, 0.9, hz - 0.6), "", 0.3)
	_loot(root, "ammo", "", "Geborgene Vorräte", Vector3(hx - 0.35, 1.5, 0.5), "", 0.3)
	_loot(root, "ammo", "", "Geborgene Vorräte", Vector3(-0.5, 1.4, -hz + 0.35), "", 0.3)
	_loot(root, "ammo", "", "Munitionskiste", Vector3(-hx + 0.6, 0.0, hz - 0.5), "", 0.3)
	var inner := OmniLight3D.new()
	inner.light_color = Color(1.0, 0.8, 0.55)
	inner.light_energy = 1.2
	inner.add_to_group("day_night_lamps")
	inner.omni_range = 6.0
	inner.position = Vector3(0, base_h - 0.3, 0)
	root.add_child(inner)
	_box(root, Vector3(size.x + 0.4, 0.14, size.y + 0.8), Vector3(0, base_h + wall_h + 0.07, 0), dark_wood)
	# Satteldach with the ridge east-west: the gable end faces the track in the west with a wide overhang on purlins
	# and knee braces, the eaves run along the north (stair) and south faces (photos 14, 17, 19, 22)
	var roof_y := base_h + wall_h + 0.14
	_gable_roof(root, size, roof_y, b["roof_h"], Vector2(1.4, 0.7), Vector2(0.5, 0.5), roof, true)
	_gable_roof_details(root, size, roof_y, b["roof_h"], Vector2(1.4, 0.7), Vector2(0.5, 0.5), true, wood)
	# small metal vent on the ridge near the west gable (photos 13, 14)
	_box(root, Vector3(0.36, 0.7, 0.36), Vector3(-1.6, roof_y + b["roof_h"] + 0.2, 0.0), _plain(Color(0.5, 0.5, 0.52), 0.45, 0.6))
	# Garage door: closed; E opens the leaves away from the interacting player.
	_hut_door(root, Vector3(-hx + 0.1, 0.0, -hz + 1.9), 0.0, 2.6, 2.1, "Garagentor", "waldhuette", wood)
	# two small cellar windows in the base near the south end of the west face (photo 14)
	var glass := _plain(Color(0.08, 0.1, 0.11), 0.3, 0.2)
	for wz: float in [1.85, 2.55]:
		_box(root, Vector3(0.05, 0.4, 0.55), Vector3(-hx - 0.02, 1.65, wz), glass)
		_box(root, Vector3(0.05, 0.05, 0.62), Vector3(-hx - 0.03, 1.88, wz), _plain(Color(0.6, 0.6, 0.58), 0.8))
	# closed shutters: north (2 in the west half, photo 17), west (1, north half, photo 14), south (1, photo 22)
	var shutter := _plain(Color(0.3, 0.15, 0.1), 0.7)
	for sh in [[Vector3(-hx + 0.9, base_h + 1.55, -hz - 0.11), 0.0], [Vector3(-hx + 2.9, base_h + 1.55, -hz - 0.11), 0.0],
			[Vector3(-hx - 0.11, base_h + 1.55, -1.3), PI / 2.0], [Vector3(0.6, base_h + 1.55, hz + 0.11), 0.0]]:
		_box(root, Vector3(1.1, 0.9, 0.06), sh[0], shutter, sh[1])
	# outside stair along the north face: 12 concrete block steps without a railing, starting 2.5 m from the
	# north-west corner and rising east to the landing with the upper door (photos 15, 17)
	var steps := 12
	var stair_h := base_h + 0.25
	var rise := stair_h / steps
	var tread := 0.29
	var stair_z := -hz - 0.55
	var x_start := -hx + 2.5
	var step_mat := _mat("ph_concrete", 0.5, Color(0.85, 0.85, 0.82))
	for i in steps:
		var x := x_start + i * tread
		_box(root, Vector3(tread, rise * (i + 1), 0.95), Vector3(x + tread / 2.0, rise * (i + 1) / 2.0, stair_z), step_mat)
	var x_top := x_start + steps * tread
	_box(root, Vector3(hx - x_top, stair_h, 0.95), Vector3((x_top + hx) / 2.0, stair_h / 2.0, stair_z), step_mat)
	# upper door on the north face at the east end, two small steps in front (photos 15, 17)
	_hut_door(root, Vector3(hx - 0.9, base_h + 0.25, -hz - 0.02), PI / 2.0, 1.2, 2.0, "Hüttentür", "waldhuette", wood)
	_slab(root, Vector3(1.3, 0.25, 0.6), Vector3(hx - 0.9, base_h + 0.125, -hz - 0.25), step_mat)
	var run := steps * tread
	# Walkable ramp and landing meet the upper floor without a blocking doorstep.
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(sqrt(run * run + stair_h * stair_h) + 0.3, 0.2, 0.95)
	rcs.shape = rbox
	rcs.position = Vector3(x_start + run / 2.0, stair_h / 2.0 - 0.1, stair_z)
	rcs.rotation.z = atan2(stair_h, run)
	ramp.add_child(rcs)
	var lcs := CollisionShape3D.new()
	var lbox := BoxShape3D.new()
	lbox.size = Vector3(hx - x_top + 0.2, stair_h, 0.95)
	lcs.shape = lbox
	lcs.position = Vector3((x_top + hx) / 2.0, stair_h / 2.0, stair_z)
	ramp.add_child(lcs)
	root.add_child(ramp)
	ramp.add_to_group("navsource")
	# warm light at the upper door and over the garage
	var wl := OmniLight3D.new()
	wl.light_color = Color(1.0, 0.72, 0.42)
	wl.light_energy = 2.5
	wl.add_to_group("day_night_lamps")
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
	# light fibre-cement sheets: white in the aerial, mid grey seen from the track below (photos 12, 22)
	var roof := _mat("ph_corrugated", 0.7, Color(0.95, 0.96, 0.98))
	roof.roughness = 0.78
	roof.metallic = 0.05
	var dark_wood := _plain(Color(0.25, 0.13, 0.08), 0.75)
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	# concrete base and sheet-metal walls as real walls; small back window in the west face (the way in)
	# the big double door sits in the southern part of the east face, one metre from the south-east corner (photos 12, 22)
	var door_z := hz - 2.3
	_walls(root, Vector2(size.x, size.y), 0.0, base_h, 0.25, concrete, { "side": "e", "along": door_z, "width": 2.4, "bottom": 0.0, "top": base_h })
	var boards := _mat("ph_cladding", 0.45, Color(0.55, 0.4, 0.3))
	boards.uv1_triplanar = true
	_walls(root, Vector2(size.x + 0.1, size.y + 0.1), base_h, wall_h, 0.12, boards, [
		{ "side": "w", "along": 2.0, "width": 1.3, "bottom": 0.3, "top": 2.4 },
		{ "side": "e", "along": door_z, "width": 2.4, "bottom": 0.0, "top": 2.6 - base_h }])
	# gable ends in dark corrugated sheet metal (photo 12), vertical board lines on the long sides
	for gz in [-hz - 0.07, hz + 0.07]:
		_box(root, Vector3(size.x + 0.2, wall_h, 0.04), Vector3(0, base_h + wall_h / 2.0, gz), metal)
	for k in int(size.y / 0.25):
		var zz := -hz + 0.125 + k * 0.25
		if absf(zz - door_z) < 1.25:
			continue
		_box(root, Vector3(0.03, wall_h - 0.1, 0.05), Vector3(hx + 0.08, base_h + wall_h / 2.0, zz), _plain(Color(0.2, 0.13, 0.09), 0.85))
	# notice signs on the road side
	_box(root, Vector3(0.04, 0.6, 0.9), Vector3(hx + 0.12, base_h + 2.3, 1.5), _plain(Color(0.85, 0.88, 0.8), 0.7))
	var pane := Breakable.new()
	pane.setup(Vector2(1.2, 1.0))
	root.add_child(pane)
	pane.position = Vector3(-hx - 0.02, base_h + 0.85, 2.0)
	pane.rotation.y = PI / 2.0
	# The glass remains breakable, but the locked building cannot be bypassed through it.
	var grille := _plain(Color(0.13, 0.15, 0.14), 0.5, 0.7)
	for offset: float in [-0.43, 0.0, 0.43]:
		_slab(root, Vector3(0.10, 2.1, 0.045), Vector3(-hx + 0.04, base_h + 1.35, 2.0 + offset), grille)
	_slab(root, Vector3(size.x, 0.1, size.y), Vector3(0, -0.05, 0), _mat("ph_concrete", 0.6, Color(0.6, 0.6, 0.58)))
	_slab(root, Vector3(size.x, 0.1, size.y), Vector3(0, base_h + wall_h, 0), _plain(Color(0.2, 0.2, 0.2)))
	# crates as steps outside and inside the window
	_slab(root, Vector3(0.9, 0.55, 0.9), Vector3(-hx - 0.6, 0.275, 2.0), Foliage.pbr("planks", 0.8, Color(0.45, 0.38, 0.28)))
	_slab(root, Vector3(0.9, 0.5, 0.9), Vector3(-hx + 0.75, 0.25 + base_h, 2.0), Foliage.pbr("planks", 0.8, Color(0.45, 0.38, 0.28)))
	# gable roof along the long axis; the overhang is wide on the road side (east, ~1.4 m on struts) and short on the
	# forest side (photos 12, 22)
	var roof_y := base_h + wall_h
	var roof_height: float = b["roof_h"]
	var over_eave := Vector2(0.45, 1.4)
	_gable_roof(root, size, roof_y, roof_height, Vector2(0.6, 0.6), over_eave, roof, false)
	_gable_roof_details(root, size, roof_y, roof_height, Vector2(0.6, 0.6), over_eave, false, metal)
	# The wide east overhang rests on a continuous purlin beneath the rafters.
	# Derive the braces from their actual joints so they cannot pierce the roof.
	var timber := _plain(Color(0.28, 0.18, 0.12), 0.85)
	var slope := roof_height / hx
	var support_x := hx + over_eave.y - 0.28
	var support_y := roof_y + roof_height - slope * support_x - 0.14 - 0.13 * sqrt(1.0 + slope * slope) - 0.08 - slope * 0.07
	_box(root, Vector3(0.14, 0.16, size.y + 0.9), Vector3(support_x, support_y, 0), timber)
	for k in 6:
		var zz := -hz + 1.0 + k * (size.y - 2.0) / 5.0
		var wall_joint := Vector3(hx + 0.06, support_y - 0.78, zz)
		var outer_joint := Vector3(support_x, support_y - 0.08, zz)
		var direction := outer_joint - wall_joint
		var strut := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(direction.length(), 0.1, 0.1)
		strut.mesh = sb
		strut.material_override = timber
		strut.position = (wall_joint + outer_joint) / 2.0
		strut.rotation.z = atan2(direction.y, direction.x)
		root.add_child(strut)
	# inside: the good weapons on a rack, ammunition, firewood
	_box(root, Vector3(2.6, 1.6, 0.08), Vector3(0, base_h + 1.4, hz - 0.2), Foliage.pbr("planks", 0.8, Color(0.4, 0.33, 0.25)))
	_loot(root, "ammo", "", "Geborgene Vorräte", Vector3(-0.7, base_h + 1.4, hz - 0.3), "", 0.3)
	_loot(root, "ammo", "", "Geborgene Vorräte", Vector3(0.7, base_h + 1.4, hz - 0.3), "", 0.3)
	_loot(root, "ammo", "", "Munitionskiste", Vector3(hx - 0.9, base_h, -hz + 1.2), "", 0.3)
	_loot(root, "ammo", "", "Munitionskiste", Vector3(hx - 0.9, base_h, -hz + 2.2), "", 0.3)
	_loot(root, "weapon", "shotgun", "Schrotflinte", Vector3(-1.0, base_h + 0.55, hz - 0.5), "rifle", 0.3, 0.0, 3)
	_loot(root, "weapon", "marksman", "Waldläufer .308", Vector3(1.0, base_h + 0.55, hz - 0.5), "marksman", 0.3, 0.0, 8)
	for k in 3:
		var pile := _prop(root, "woodpile", 2.2, "x", Vector3(-hx + 0.6, base_h, -hz + 2.0 + k * 2.5), PI / 2.0)
		if pile:
			var extent := Barricade._bounds(pile).size
			pile.scale = Vector3(2.2 / extent.z, 1.1 / extent.y, 0.9 / extent.x)
	var inner := OmniLight3D.new()
	inner.light_color = Color(0.9, 0.85, 0.7)
	inner.light_energy = 1.0
	inner.add_to_group("day_night_lamps")
	inner.omni_range = 8.0
	inner.position = Vector3(0, base_h + wall_h - 0.4, 0)
	root.add_child(inner)
	_hut_door(root, Vector3(hx + 0.02, 0, door_z), PI, 2.4, 2.6, "Holzlagertor", "holzlager", boards)
	return root

func _build_buildings() -> void:
	var hut_root := _waldhuette()
	hut = HutHealth.new()
	add_child(hut)
	hut.setup(self, hut_root, Map.BUILDINGS["waldhuette"]["size"])
	_holzlager()
	# firewood stacks at the south end of the Holzlager
	var hl: Dictionary = Map.BUILDINGS["holzlager"]
	var hp: Vector2 = hl["pos"]
	for i in 3:
		_place("woodpile", hp.x + 2.0 + i * 1.7, hp.y + 9.5, 1.2, 0.0, 1.0, 1.1)

# ---------------------------------------------------------------- campsite
func _log_bench(x: float, z: float, yaw: float, length: float = 2.6) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(x, z)
	root.rotation.y = yaw
	if _prop(root, "log_bench_beam", length, "x"):
		_box_collider(root, Vector3(length, 0.55, 0.4))
		return root
	var bark := _mat("ph_bark_beech2", 0.6, Color(0.6, 0.55, 0.5), false)
	var beam := Foliage.pbr("planks", 0.7, Color(0.32, 0.27, 0.22))
	_box(root, Vector3(length, 0.13, 0.24), Vector3(0, 0.47, 0), beam)
	for sx in [-length * 0.33, length * 0.33]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.17; lm.bottom_radius = 0.18; lm.height = 0.4
		leg.mesh = lm
		leg.material_override = bark
		leg.position = Vector3(sx, 0.2, 0)
		root.add_child(leg)
	_box_collider(root, Vector3(length, 0.55, 0.35))
	return root

func _build_small_campsite() -> void:
	if Map.SMALL_CAMPSITE.is_empty():
		return
	var center: Vector2 = Map.SMALL_CAMPSITE.pos
	var site := Node3D.new()
	site.name = "SmallCampsite"
	add_child(site)
	site.position = Map.ground_pos(center.x, center.y)
	# A low, simple stone ring with a small fire; no grill frame or picnic table.
	var fire := Foliage.campfire(Vector3.ZERO)
	fire.name = "Fire"
	fire.scale = Vector3.ONE * 0.7
	site.add_child(fire)
	var ash := MeshInstance3D.new()
	var bed := CylinderMesh.new()
	bed.top_radius = 0.65
	bed.bottom_radius = 0.65
	bed.height = 0.025
	bed.radial_segments = 24
	ash.mesh = bed
	ash.material_override = _plain(Color(0.11, 0.10, 0.09), 1.0)
	ash.position.y = 0.012
	fire.add_child(ash)
	for child in fire.get_children():
		if child is GPUParticles3D:
			child.local_coords = true
			child.amount = 36 if child.name == "Smoke" else 45
			if child.name != "Smoke":
				child.lifetime = 0.7
				var flame: ParticleProcessMaterial = child.process_material
				flame.initial_velocity_min = 0.35
				flame.initial_velocity_max = 0.65
				flame.gravity = Vector3(0, 0.5, 0)
				flame.scale_min = 0.35
				flame.scale_max = 0.65
				flame.turbulence_noise_strength = 0.16
		elif child is MeshInstance3D and child.mesh is CylinderMesh and child != ash:
			child.material_override = _mat("ph_bark_beech2", 0.8, Color(0.22, 0.18, 0.14))
	var light: OmniLight3D = fire.get_node("Light")
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.light_volumetric_fog_energy = 0.4
	light.shadow_enabled = false
	light.add_to_group("day_night_lamps")
	_collider(fire, 0.83, 0.28)
	var seat_index := 0
	for b in Map.SMALL_CAMPSITE.benches:
		var bench := _log_bench(b[0].x, b[0].y, b[1], 2.2)
		bench.name = "Bench%d" % (seat_index + 1)
		bench.reparent(site)
		seat_index += 1

func _log_table(x: float, z: float, yaw: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(x, z)
	root.rotation.y = yaw
	if _prop(root, "log_picnic_table", 2.3, "x"):
		_box_collider(root, Vector3(2.3, 0.85, 1.9))
		return
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
	root.name = "CabinFountain"
	add_child(root)
	root.position = Map.ground_pos(x, z)
	root.rotation.y = yaw
	if _prop(root, "log_fountain", 2.7, "x"):
		# water surface in the trough and a thin jet, the model itself is dry
		var wsurf := MeshInstance3D.new()
		var wbox := BoxMesh.new()
		wbox.size = Vector3(1.9, 0.02, 0.3)
		wsurf.mesh = wbox
		var wmat2 := _plain(Color(0.16, 0.22, 0.24, 0.9), 0.04, 0.3)
		wmat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wsurf.material_override = wmat2
		wsurf.position = Vector3(-0.35, 0.62, 0.0)
		root.add_child(wsurf)
		_box_collider(root, Vector3(2.4, 1.0, 0.8), Vector3(-0.35, 0.0, 0.0))
		_box_collider(root, Vector3(0.6, 1.9, 0.6), Vector3(1.25, 0.0, 0.0))
		return
	var bark := _mat("ph_bark_oak", 0.6, Color(0.62, 0.56, 0.5), false)
	bark.roughness_texture = null
	bark.roughness = 1.0
	# weathered grey trough: the smooth beech bark photo, darkened and fully matte
	var grey_wood := _mat("ph_bark_beech2", 0.5, Color(0.58, 0.56, 0.52), false)
	grey_wood.roughness_texture = null
	grey_wood.roughness = 1.0
	grey_wood.metallic_specular = 0.1
	# Photo 15: a hollowed, weathered grey log trough (~2.4 m) on two short log blocks, a thick trunk post
	# (~1.9 m) at the +x end with an iron pipe spout, a ring of stones on the ground at the other end.
	for sx in [-0.85, 0.75]:
		var st := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.2; sm.bottom_radius = 0.23; sm.height = 0.36
		st.mesh = sm
		st.material_override = bark
		st.position = Vector3(sx, 0.18, 0)
		root.add_child(st)
	var trough := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.3; tm.bottom_radius = 0.3; tm.height = 2.4
	tm.radial_segments = 14
	trough.mesh = tm
	trough.material_override = grey_wood
	trough.rotation.z = PI / 2.0
	trough.position.y = 0.66
	root.add_child(trough)
	# flattened top with the water surface inside
	_box(root, Vector3(2.3, 0.06, 0.5), Vector3(0, 0.93, 0), grey_wood)
	var water := MeshInstance3D.new()
	var wq := BoxMesh.new()
	wq.size = Vector3(2.05, 0.02, 0.34)
	water.mesh = wq
	var wm := _plain(Color(0.16, 0.22, 0.24, 0.9), 0.04, 0.3)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wm
	water.position.y = 0.95
	root.add_child(water)
	# thick trunk section as the post (photos 15, 21: ~0.5 m across, 1.9 m tall) with the spout pipe
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.24; pm.bottom_radius = 0.28; pm.height = 1.9
	pm.radial_segments = 12
	post.mesh = pm
	post.material_override = grey_wood
	post.position = Vector3(1.5, 0.95, 0.0)
	root.add_child(post)
	var iron := _plain(Color(0.28, 0.28, 0.3), 0.4, 0.8)
	_box(root, Vector3(0.55, 0.04, 0.04), Vector3(1.05, 1.25, 0.0), iron)
	_box(root, Vector3(0.04, 0.16, 0.04), Vector3(0.83, 1.18, 0.0), iron)
	# thin falling water jet from the spout
	var jet := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(0.025, 0.2, 0.025)
	jet.mesh = jm
	var jmat := _plain(Color(0.7, 0.8, 0.85, 0.45), 0.1, 0.0)
	jmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jet.material_override = jmat
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jet.position = Vector3(0.83, 1.03, 0.0)
	root.add_child(jet)
	# stone ring (soak-away) beside the far end
	var stone := _mat("rock", 0.8, Color(0.6, 0.58, 0.54))
	for i in 8:
		var a := TAU * i / 8.0
		var sm2 := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.11 + 0.04 * (i % 3); sph.height = sph.radius * 1.3
		sm2.mesh = sph
		sm2.material_override = stone
		sm2.position = Vector3(-1.55 + cos(a) * 0.38, 0.05, 0.45 + sin(a) * 0.38)
		sm2.rotation = Vector3(0.4 * i, 0.7 * i, 0.0)
		root.add_child(sm2)
	_box_collider(root, Vector3(2.5, 1.0, 0.7))
	_box_collider(root, Vector3(0.6, 1.9, 0.6), Vector3(1.5, 0.0, 0.0))

func _signpost(x: float, z: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(x, z)
	var post := _plain(Color(0.35, 0.3, 0.25), 0.8)
	# Swiss hiking guidepost: round wooden post with two yellow arrow plates. "Oberrohrdorf" on top points north
	# along the Waldweg, "Remetschwil" below points south down the track between the huts.
	var pm := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.06; pc.bottom_radius = 0.07; pc.height = 2.5; pc.radial_segments = 10
	pm.mesh = pc
	pm.material_override = post
	pm.position.y = 1.25
	root.add_child(pm)
	_sign_arrow(root, "Oberrohrdorf", 2.15, 0.0)
	_sign_arrow(root, "Remetschwil", 1.9, PI)
	_box_collider(root, Vector3(0.3, 2.5, 0.3))
	# small wooden info board next to it (photo 16)
	notice_board = Node3D.new()
	notice_board.name = "ReadableNoticeBoard"
	root.add_child(notice_board)
	notice_board.position = Vector3(1.0, 0.0, 0.3)
	if not _prop(notice_board, "info_board", 1.9, "y", Vector3.ZERO, -0.2):
		_box(notice_board, Vector3(0.6, 0.5, 0.05), Vector3(0, 1.4, 0), Foliage.pbr("planks", 0.8, Color(0.6, 0.5, 0.4)))
		_box(notice_board, Vector3(0.08, 1.2, 0.08), Vector3(0, 0.6, 0), post)
	_box_collider(notice_board, Vector3(0.7, 1.9, 0.3))

func _looking_at_notice() -> bool:
	if not is_instance_valid(notice_board): return false
	var eye := player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(eye, eye - player.camera.global_basis.z * Door.INTERACT_REACH, 1 | 8, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider.get_parent() == notice_board

func _read_notice() -> void:
	# Local flavour only: reading never discovers the trader or reveals a map marker.
	_notice_open = true
	hud.message(SECRET_SHOP_NOTICE, 0.0)

func _close_notice() -> void:
	_notice_open = false
	# Do not erase a newer wave, quest or combat message.
	if hud.msg_label.text == SECRET_SHOP_NOTICE:
		hud.message("", 0.0)

func _update_notice() -> void:
	if not _notice_open: return
	if hud.msg_label.text != SECRET_SHOP_NOTICE:
		_notice_open = false
		return
	if not is_instance_valid(notice_board) or not player.active or not player.alive:
		_close_notice()
	elif player.camera.global_position.distance_to(notice_board.to_global(Vector3(0, 1.2, 0))) > Door.INTERACT_REACH + 0.4:
		_close_notice()

# guidepost at the junction Sennhofstrasse / Weg zur Hütte (photo 8), on the verge north of the track
func _junction_guidepost() -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Map.ground_pos(121.5, 18.5)
	var pm := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.06; pc.bottom_radius = 0.07; pc.height = 2.5; pc.radial_segments = 10
	pm.mesh = pc
	pm.material_override = _plain(Color(0.35, 0.3, 0.25), 0.8)
	pm.position.y = 1.25
	root.add_child(pm)
	# arrows: yaw 0 = -z = north
	_sign_arrow(root, "Waldhütte", 2.15, PI / 2.0 + 0.35)   # west-south-west along the Weg zur Hütte
	_sign_arrow(root, "Oberrohrdorf", 1.9, -0.2)                        # north along the Sennhofstrasse
	_sign_arrow(root, "Remetschwil", 1.65, PI - 0.15)                    # south along the Sennhofstrasse
	_box_collider(root, Vector3(0.3, 2.5, 0.3))

# yellow arrow plate on the post at height y, pointing along -z rotated by yaw, black text on both faces
func _sign_arrow(root: Node3D, text: String, y: float, yaw: float) -> void:
	var arm := Node3D.new()
	arm.rotation.y = yaw
	arm.position.y = y
	root.add_child(arm)
	var yellow := _plain(Color(1.0, 0.82, 0.05), 0.55)
	var plate_len := 0.78
	# plate body: starts at the post, runs forward (-z)
	_box(arm, Vector3(0.03, 0.15, plate_len), Vector3(0.09, 0.0, -plate_len * 0.5 - 0.02), yellow)
	# arrow tip: a flat prism from two triangles
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := -plate_len - 0.02
	var tip := Vector3(0.09, 0.0, z0 - 0.14)
	for sx: float in [-1.0, 1.0]:
		var xo := 0.09 + sx * 0.015
		var p0 := Vector3(xo, 0.075, z0)
		var p1 := Vector3(xo, -0.075, z0)
		var t := Vector3(xo, 0.0, z0 - 0.14)
		var order := [p0, t, p1] if sx > 0.0 else [p0, p1, t]
		for p: Vector3 in order:
			st.set_normal(Vector3(sx, 0, 0))
			st.set_uv(Vector2(p.z, p.y))
			st.add_vertex(p)
	st.generate_normals()
	var tm := MeshInstance3D.new()
	tm.mesh = st.commit()
	tm.material_override = yellow
	arm.add_child(tm)
	for side: float in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = text
		label.font_size = 56
		label.pixel_size = 0.0017
		label.modulate = Color(0.05, 0.05, 0.05)
		label.outline_size = 0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.no_depth_test = false
		label.double_sided = false
		label.position = Vector3(0.09 + side * 0.018, 0.0, -plate_len * 0.5 - 0.02)
		# Label3D faces +Z; turn that normal outwards (+X on the right face, -X on the left face)
		label.rotation.y = PI / 2.0 if side > 0.0 else -PI / 2.0
		arm.add_child(label)

# ---------------------------------------------------------------- pond
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;
uniform vec3 deep : source_color = vec3(0.03, 0.06, 0.05);
uniform vec3 shallow : source_color = vec3(0.1, 0.14, 0.11);
uniform float radius = 7.0;
varying vec2 lp;
void vertex() {
	lp = VERTEX.xz;
}
void fragment() {
	float t = TIME;
	// two crossing ripple trains plus a slow drift, as normal perturbation
	float a = sin(lp.x * 3.1 + t * 1.1) * 0.5 + sin((lp.x + lp.y) * 2.3 - t * 0.8) * 0.5;
	float b = sin(lp.y * 2.7 - t * 0.9) * 0.5 + sin((lp.y - lp.x) * 1.9 + t * 0.7) * 0.5;
	vec3 n = normalize(vec3(a * 0.06, 1.0, b * 0.06));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float edge = clamp(length(lp) / radius, 0.0, 1.0);
	ALBEDO = mix(deep, shallow, edge * edge);
	ALPHA = mix(0.9, 0.7, edge * edge);
	ROUGHNESS = 0.12;
	SPECULAR = 0.3;
	METALLIC = 0.0;
}
"""

func _build_pond() -> void:
	if Map.POND.is_empty():
		return
	var pd: Dictionary = Map.POND
	var c: Vector2 = pd["pos"]
	var r: float = pd["r"]
	var water_y: float = pd["water_y"]
	# water surface: a subdivided disc with the ripple shader
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	var segs := 36
	var idx := 0
	st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3.ZERO)
	for ri in range(1, rings + 1):
		var rr := r * ri / rings
		for k in segs:
			var a := TAU * k / segs
			st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5 + cos(a) * rr / (2.0 * r), 0.5 + sin(a) * rr / (2.0 * r)))
			st.add_vertex(Vector3(cos(a) * rr, 0, sin(a) * rr))
	for k in segs:
		st.add_index(0); st.add_index(1 + (k + 1) % segs); st.add_index(1 + k)
	for ri in range(1, rings):
		var i0 := 1 + (ri - 1) * segs
		var i1 := 1 + ri * segs
		for k in segs:
			var k1 := (k + 1) % segs
			st.add_index(i0 + k); st.add_index(i1 + k1); st.add_index(i1 + k)
			st.add_index(i0 + k); st.add_index(i0 + k1); st.add_index(i1 + k1)
	var water := MeshInstance3D.new()
	water.name = "ForestPondWater"
	water.mesh = st.commit()
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var wm := ShaderMaterial.new()
	wm.shader = sh
	wm.set_shader_parameter("radius", r)
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(c.x, water_y, c.y)
	add_child(water)
	# a few stones and reeds on the bank
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var rr := r + rng.randf_range(0.2, 1.4)
		var p := Map.ground_pos(c.x + cos(a) * rr, c.y + sin(a) * rr)
		var rock := WorldModels.attach(self, "rock", p, rng.randf_range(0.25, 0.58), 1, false)
		if rock: rock.rotation.y = rng.randf_range(0, TAU)
	# long hollowed-log trough on stumps, sloping down towards the pond, mouth over the water (feeds the pond)
	var tp: Vector2 = pd["trough"]
	var to_pond := (c - tp).normalized()
	var root := Node3D.new()
	root.name = "ForestPondTrough"
	add_child(root)
	root.position = Map.ground_pos(tp.x, tp.y)
	root.rotation.y = atan2(-to_pond.y, to_pond.x)   # local +x points at the pond
	var bark := _mat("ph_bark_oak", 0.6, Color(0.7, 0.62, 0.55), false)
	var len := 4.6
	for sx in [-1.6, 0.4]:
		WorldModels.attach(root, "stump", Vector3(sx, 0, 0), 0.57 if sx < 0 else 0.46, 1, false)
	var trough := WorldModels.attach(root, "pond_trough", Vector3(0.3, 0.46, 0), 4.6, 0, false)
	if trough: trough.rotation.z = -0.06
	var wsurf := MeshInstance3D.new()
	var wq := PlaneMesh.new()
	wq.size = Vector2(len - 0.7, 0.24)
	wsurf.mesh = wq
	var wmat := ShaderMaterial.new()
	wmat.shader = sh
	wmat.set_shader_parameter("radius", 5.0)
	wsurf.material_override = wmat
	wsurf.position = Vector3(0.3, 0.80, 0)
	wsurf.rotation = Vector3(0, 0, -0.06)
	root.add_child(wsurf)
	# feed post with iron spout at the high end
	_box(root, Vector3(0.16, 1.7, 0.16), Vector3(-1.9, 0.85, -0.38), bark)
	_box(root, Vector3(0.05, 0.05, 0.45), Vector3(-1.9, 1.5, -0.14), _plain(Color(0.3, 0.3, 0.32), 0.4, 0.8))
	# water falling from the mouth into the pond
	var mouth := root.to_global(Vector3(0.3 + len * 0.5, 0.8, 0))
	var fall_h := maxf(0.2, mouth.y - water_y)
	var jet := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(0.07, fall_h, 0.14)
	jet.mesh = jm
	var jmat := _plain(Color(0.6, 0.7, 0.75, 0.35), 0.1, 0.0)
	jmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jet.material_override = jmat
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jet.position = mouth - Vector3(0, fall_h * 0.5, 0) + Vector3(to_pond.x, 0, to_pond.y) * 0.15
	add_child(jet)
	_box_collider(root, Vector3(len - 0.6, 0.9, 0.7), Vector3(0.0, 0.45, 0.0))

func _build_campsite() -> void:
	# square stone fireplace with the swivel grill (photo 20)
	var fire := Foliage.campfire(Map.ground_pos(Map.FIRE.x, Map.FIRE.y))
	add_child(fire)
	for c in fire.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
			c.queue_free()
	fire_light = fire.get_node("Light")
	if _prop(fire, "fire_pit", 2.0, "x", Vector3(0, -0.05, 0), 0.0):
		_collider(fire, 1.1, 0.5)
		# the Meshy pit has the swivel arm in it; keep only the flames, embers, smoke and light of the campfire
		for c in fire.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
				c.queue_free()
		_campsite_seating()
		return
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
	_campsite_seating()

func _campsite_seating() -> void:
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
	# white steel drum with a black lid on a short post (photo 15)
	var bin := Node3D.new()
	add_child(bin)
	bin.position = Map.ground_pos(Map.BIN.x, Map.BIN.y)
	if _prop(bin, "waste_bin", 1.25, "y"):
		_collider(bin, 0.3, 1.3)
	else:
		_bin_boxes(bin)
	_signpost(Map.SIGNPOST.x, Map.SIGNPOST.y)
	_junction_guidepost()
	var seat := Node3D.new()
	add_child(seat)
	seat.position = Map.ground_pos(Map.LOG_SEAT.x, Map.LOG_SEAT.y) + Vector3(0, 0.3, 0)
	seat.rotation.y = Map.LOG_SEAT.z
	if _prop(seat, "fallen_log", 3.2, "x", Vector3(0, -0.3, 0)):
		_box_collider(seat, Vector3(3.2, 0.6, 0.6), Vector3(0, -0.3, 0))
	else:
		_seat_log(seat)
	_campsite_lanterns()

func _bin_boxes(bin: Node3D) -> void:
	var post_m := MeshInstance3D.new()
	var postm := CylinderMesh.new()
	postm.top_radius = 0.04; postm.bottom_radius = 0.04; postm.height = 0.6
	post_m.mesh = postm
	post_m.material_override = _plain(Color(0.15, 0.15, 0.16), 0.5, 0.6)
	post_m.position.y = 0.3
	bin.add_child(post_m)
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.23; dm.bottom_radius = 0.23; dm.height = 0.62
	drum.mesh = dm
	drum.material_override = _plain(Color(0.86, 0.86, 0.84), 0.55, 0.25)
	drum.position.y = 0.6 + 0.31
	bin.add_child(drum)
	var lid := MeshInstance3D.new()
	var lm2 := CylinderMesh.new()
	lm2.top_radius = 0.2; lm2.bottom_radius = 0.26; lm2.height = 0.09
	lid.mesh = lm2
	lid.material_override = _plain(Color(0.08, 0.08, 0.08), 0.5)
	lid.position.y = 0.6 + 0.62 + 0.045
	bin.add_child(lid)
	_box(bin, Vector3(0.14, 0.12, 0.47), Vector3(0.0, 0.85, 0.0), _plain(Color(0.12, 0.12, 0.12), 0.6))
	_collider(bin, 0.28, 1.3)

func _seat_log(seat: Node3D) -> void:
	var lg := MeshInstance3D.new()
	var lgm := CylinderMesh.new()
	lgm.top_radius = 0.28; lgm.bottom_radius = 0.32; lgm.height = 3.2
	lg.mesh = lgm
	lg.material_override = _mat("ph_bark_oak", 0.6, Color(0.75, 0.7, 0.62), false)
	lg.rotation.z = PI / 2.0
	seat.add_child(lg)
	_box_collider(seat, Vector3(3.2, 0.6, 0.6), Vector3(0, -0.3, 0))

var pumpkins: Array = []
const ShootablePumpkin = preload("res://scripts/shootable_pumpkin.gd")

func _campsite_lanterns() -> void:
	# pumpkin lanterns: game flavour at the stair, the table and the fountain
	var wh: Dictionary = Map.BUILDINGS["waldhuette"]
	var whp: Vector2 = wh["pos"]
	var lanterns := [[whp.x - 4.6, whp.y - 4.2, "pumpkin_lantern", 0.55], [Map.TABLE.x + 1.6, Map.TABLE.y - 0.9, "pumpkin_lantern", 0.5], [Map.FOUNTAIN.x + 1.8, Map.FOUNTAIN.y + 0.6, "pumpkin", 0.42]]
	for p in lanterns:
		var prop := _place(p[2], p[0], p[1], p[3], -1.0, 1.0, 0.0)
		if not prop: continue
		var pumpkin := ShootablePumpkin.new()
		prop.add_child(pumpkin)
		pumpkin.setup(prop)
		pumpkins.append(pumpkin)
		if p[2] == "pumpkin_lantern":
			var pl := OmniLight3D.new()
			pl.light_color = Color(1.0, 0.55, 0.15)
			pl.light_energy = 1.2
			pumpkin.lamp = pl
			pl.add_to_group("day_night_lamps")
			pl.omni_range = 4.0
			add_child(pl)
			pl.global_position = Map.ground_pos(p[0], p[1]) + Vector3(0, p[3] * 0.6, 0)

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
			var yaw := atan2(-dir.y, dir.x)
			for k in n + (1 if i == line.size() - 2 else 0):
				var p := a + dir * k
				var pp := Map.ground_pos(p.x, p.y)
				# Meshy post (weathered square post with insulators) with the box as fallback
				var holder := Node3D.new()
				root.add_child(holder)
				holder.position = pp - Vector3(0, 0.05, 0)
				if not _prop(holder, "fence_post_wire", 1.3, "y", Vector3.ZERO, yaw + rng.randf_range(-0.15, 0.15)):
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
	# hunting feeder beside the Waldweg nach Hütte (east verge, in the beech stand)
	var feeder := Node3D.new()
	add_child(feeder)
	feeder.position = Map.ground_pos(-26.0, -63.0)
	if _prop(feeder, "deer_feeder", 2.3, "y", Vector3.ZERO, 0.9):
		_box_collider(feeder, Vector3(2.0, 2.3, 1.4))
	_build_mushrooms()

func _build_mushrooms() -> void:
	# Stratified placement covers the whole playable forest, including its interior.
	# Zombie navigation excludes deep forest; players can still forage there.
	# A dedicated seed keeps item ordering identical for co-op peers.
	var random := RandomNumberGenerator.new()
	random.seed = 731942
	var bounds := Map.BOUNDS.grow(-2.0)
	var cell_size := 18.0
	for row in ceili(bounds.size.y / cell_size):
		for column in ceili(bounds.size.x / cell_size):
			var origin := bounds.position + Vector2(column, row) * cell_size
			var cell_end := (origin + Vector2.ONE * cell_size).min(bounds.end)
			var placed: Array[Vector2] = []
			for attempt in 16:
				var point := Vector2(random.randf_range(origin.x, cell_end.x), random.randf_range(origin.y, cell_end.y))
				if not _mushroom_ground_clear(point): continue
				if not placed.is_empty() and point.distance_to(placed[0]) < 2.0: continue
				_mushroom(point.x, point.y, Inventory.Mushrooms.choose(random), random.randf_range(0.22, 0.4))
				placed.append(point)
				if placed.size() == 2: break

func _mushroom_ground_clear(point: Vector2) -> bool:
	if not Map.in_forest(point.x, point.y) or Map.is_clear_zone(point.x, point.y): return false
	if Map.ground_normal(point.x, point.y).y < 0.82: return false
	if not Map.POND.is_empty() and point.distance_to(Map.POND.pos) < float(Map.POND.r) + 2.0: return false
	for tree in Map.TREES:
		var radius: float = Trees.SPECIES[tree[2]].radius * float(tree[3]) * 1.15 + 0.75
		if point.distance_squared_to(Vector2(tree[0], tree[1])) < radius * radius: return false
	for log_entry in Map.LOGS:
		if point.distance_to(Vector2(log_entry[0], log_entry[1])) < float(log_entry[2]) * 0.5 + 0.6: return false
	for npc: Dictionary in Progression.NPCS.values():
		if point.distance_to(npc.pos) < 3.0: return false
	return true

func _mushroom(x: float, z: float, kind: String, height: float) -> void:
	var n: Node3D
	if kind in ["steinpilz", "fliegenpilz"]:
		n = _place("mushroom_cluster" if kind == "steinpilz" else "mushroom_fly", x, z, height, -1.0, 1.0, 0.0)
	else:
		n = Inventory.Mushrooms.model(kind)
		add_child(n)
		n.position = Map.ground_pos(x, z)
		n.scale = Vector3.ONE * height / 0.4
	if not n:
		return
	var l := Loot.new()
	l.setup("mushroom", kind, Inventory.MUSHROOMS[kind].name)
	add_child(l)
	l.global_transform = n.global_transform
	n.reparent(l)
	loots.append(l)

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
		if Map.in_building(x, z) or (Map.in_clearing(x, z) and r.randf() > 0.45):
			return null
		return Map.ground_pos(x, z)
	if not "--no-leaves" in _flags:
		add_child(Foliage.ground_leaves(100000, leaf_sampler, rng))
	if not "--no-grass" in _flags:
		add_child(Foliage.meadow_grass())
		add_child(Foliage.forest_floor())
	if not "--no-particles" in _flags:
		add_child(Foliage.falling_leaves(Map.ground_pos(Map.FIRE.x, Map.FIRE.y) + Vector3(0, 9, 10), Vector3(45, 7, 40)))

# ---------------------------------------------------------------- game flow
func should_play_intro() -> bool:
	if _restarted or _autotest: return false
	for flag in _flags:
		if flag in ["--no-intro", "--benchmark", "--smoke-test", "--shot-ui"] or flag.begins_with("--view=") or flag.begins_with("--views="):
			return false
	return true

func _on_start(play_intro: bool = true) -> void:
	if not navigation_ready:
		return
	if NetSession.enabled and not NetSession._applying:
		if NetSession.phase == "over":
			NetSession.restart()
			return
		if not started:
			NetSession.start_game()
			return
	if over:
		NetSession.restart_pending = true
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	get_tree().paused = false
	hud.hide_overlay()
	player.active = player.alive and not (intro.active and intro.phase == "logo")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if player.active else Input.MOUSE_MODE_VISIBLE
	if not started:
		# The host supplies the decision to clients, including late joins.
		var show_intro := play_intro if NetSession.enabled else play_intro and should_play_intro()
		if not show_intro:
			if not "--no-music" in _flags:
				music.play("night")
		else:
			waves.phase = "intro"
			music.stop_all()   # only the intro track plays during the opening, the menu music fades out
			intro.begin(NetSession.enabled)
	started = true

func _pause() -> void:
	if cheat_menu and cheat_menu.is_open: cheat_menu.close()
	if progression and progression.is_open: progression.close()
	if not started or over:
		return
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = not NetSession.enabled
	hud.show_overlay("MENÜ" if NetSession.enabled else "PAUSE", "Koop läuft weiter. Dein Spieler bleibt in der Welt." if NetSession.enabled else "Verschnaufpause. Die Zombies warten, die Uhr steht.", "Weiter", "", "pause")

func _to_main_menu() -> void:
	if NetSession.enabled:
		NetSession.leave()
		return
	get_tree().paused = false
	get_tree().reload_current_scene()

func _game_over() -> void:
	if NetSession.enabled:
		if NetSession.world: NetSession.world.check_team()
		return
	_end_round("GESTORBEN", "Du hast %d Welle%s überstanden mit %d Punkten." % [waves.completed, "" if waves.completed == 1 else "n", player.score])

# the Waldhütte fell: the round is lost even with everyone alive
func _hut_lost() -> void:
	if over: return
	if NetSession.enabled:
		if NetSession.world: NetSession.world.hut_lost()
		return
	_end_round("HÜTTE VERLOREN", "Die Waldhütte ist zerstört. Du hast %d Welle%s überstanden mit %d Punkten." % [waves.completed, "" if waves.completed == 1 else "n", player.score])

func _end_round(title: String, text: String) -> void:
	if over: return
	over = true
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	music.horde = 0.0
	music.play("gameover")
	get_tree().paused = true
	var rank := stats.finish(player.score, waves.completed, str(difficulty["name"]))
	hud.show_overlay(title, text, "Nochmal", "", "over")
	hud.show_run_summary(stats, player.score, waves.completed, rank, str(difficulty["name"]))

func spawn_zombie(type: String, p: Vector2, speed_mul: float, lane := "", minimum_distance := 0.0) -> bool:
	if NetSession.is_client(): return false
	var spawn := Map.ground_pos(p.x, p.y)
	var nav_map := nav_region.get_navigation_map()
	if minimum_distance > 0.0 and NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return false
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		spawn = NavigationServer3D.map_get_closest_point(nav_map, spawn)
	# Check the final navigable position, since projection can move a spawn toward a player.
	if minimum_distance > 0.0:
		var actors: Array = [player]
		if NetSession.is_host() and NetSession.world:
			actors.append_array(NetSession.world.actors.values())
		for actor in actors:
			if not is_instance_valid(actor) or not actor.alive: continue
			var offset: Vector3 = spawn - actor.global_position
			if Vector2(offset.x, offset.z).length_squared() < minimum_distance * minimum_distance:
				return false
	var z: Zombie = Titan.new() if Zombie.is_titan_kind(type) else Zombie.new()
	z.setup(type, player, barricades, speed_mul, _zombie_killed)
	z.hp *= float(difficulty["hp"])
	if Zombie.is_titan_kind(type):
		z.hp *= (1.0 + maxf(0, waves.wave - 8) * 0.12) * (1.0 + 0.65 * (NetSession.roster.size() - 1) if NetSession.enabled else 1.0)
		var message := "%s\nEin %d Meter großer Titan nähert sich über die Wiese!" % [z.type.get("name", "DER FELDTITAN"), int(z.height)]
		hud.message(message, 5)
		if NetSession.is_host():
			for peer in NetSession.ready_peers:
				if peer != 1: NetSession.feedback(peer, "message", [message, 5.0])
	z.max_hp = z.hp
	var lane_slots := {"north": 0, "east": 1, "south": 2, "west": 3}
	if lane_slots.has(lane): z.lane_bar = barricades[lane_slots[lane]]
	z.damage_mul = float(difficulty["dmg"])
	zombies_root.add_child(z)
	z.global_position = spawn + Vector3(0, 0.2, 0)
	_alive_count += 1
	z.tree_exiting.connect(func():
		if z.alive:
			_alive_count = maxi(0, _alive_count - 1))
	return true

# Points are the only currency (barricades, towers, vendors). Kills pay 60 % of the type value so the
# first barricade takes most of wave 1 and gates, towers and guns have to be earned wave by wave.
const KILL_VALUE := 0.6

func _zombie_killed(zombie: Zombie) -> void:
	stats.record_kill(zombie)
	_alive_count = maxi(0, _alive_count - 1)
	# points: base value x difficulty x KILL_VALUE, plus up to +100 % for a kill streak (from the third kill within 4 s)
	var base := float(zombie.type["score"]) * float(difficulty["score"]) * KILL_VALUE
	var streak := stats.streak() + 1
	var bonus := clampf((streak - 2) * 0.1, 0.0, 1.0)
	var points := int(round(base * (1.0 + bonus) * (1.5 if zombie.last_headshot else 1.0)))
	var scorer: Player = NetSession.world.actor(zombie.killer_peer) if NetSession.is_host() else player
	if not is_instance_valid(scorer): scorer = player
	if zombie.killer_weapon == "tower": points = maxi(1, roundi(points * 0.5))
	points = maxi(1, roundi(points * scorer.relic_multiplier("score")))
	scorer.add_score(points)
	progression.rare_market.on_kill(scorer, zombie.killer_weapon)
	progression.event("kills")
	if zombie.net_kind == "runner": progression.event("runner_kills")
	if zombie.last_headshot: progression.event("headshot_kills")
	if zombie.killer_weapon == "tower": progression.event("tower_kills")
	if Zombie.is_titan_kind(zombie.net_kind): progression.event("titans")
	# Support players earn a modest shared contribution without multiplying the full bounty.
	if NetSession.is_host():
		for peer in NetSession.world.actors:
			var ally: Player = NetSession.world.actor(peer)
			if ally != scorer and ally.alive: ally.add_score(maxi(1, roundi(points * 0.25)))
	stats.kill(zombie.last_headshot, points)
	scorer.hud.score_popup(points, zombie.last_headshot)
	if streak >= 3:
		hud.streak(streak, int(round(bonus * 100.0)))
		if streak == 3 or streak % 5 == 0:
			Sfx.play(self, "streak", -12.0, 1.0 + minf(streak, 10) * 0.03)
	if achievements:
		achievements.event("kills")
		if streak >= 10:
			achievements.event("streak_10")

func alive_zombies() -> int:
	return _alive_count

var _shadow_cells_t := 0.0

func _process(delta: float) -> void:
	_update_notice()
	var t := Time.get_ticks_msec() / 1000.0
	if started and not over and player and (player.active or NetSession.is_host()) and not get_tree().paused and not NetSession.is_client():
		stats.tick(delta)
	_shadow_cells_t -= delta
	if _shadow_cells_t <= 0.0 and player:
		_shadow_cells_t = 0.5
		var cam := player.camera.global_position if player.camera.current else get_viewport().get_camera_3d().global_position
		Trees.update_shadows(Vector2(cam.x, cam.z), 65.0)
	if fire_light:
		var daylight_multiplier := day_night.fire_energy_multiplier if day_night else 1.0
		fire_light.light_energy = 5.0 * daylight_multiplier * (0.8 + 0.2 * sin(t * 11.0) * sin(t * 7.3) + 0.1 * sin(t * 23.0))
	if player and player.active and not player.mounted_tower and not defences.placing and defences.input_grace <= 0:
		if not intro.showing_guidance():
			_tower_hint_remaining = maxf(0.0, _tower_hint_remaining - delta)
		var near = null
		var nd := Barricade.BUILD_REACH
		for b in barricades:
			var d: float = b.distance_to_line(player.global_position)
			if d < nd:
				nd = d
				near = b
		near_bar = near
		for b in barricades:
			b.set_preview(b == near)
		var loot = null
		var ld := Door.INTERACT_REACH
		for l in loots:
			if not is_instance_valid(l) or l.taken:
				continue
			if l is Door or l is ForestKey:
				var d: float = player.camera.global_position.distance_to(l.interaction_point())
				if d < ld and l.can_interact(player):
					ld = d
					loot = l
			else:
				var d: float = l.global_position.distance_to(player.global_position + Vector3(0, 0.8, 0))
				if d >= minf(ld, 2.4):
					continue
				var target: Vector3 = l.global_position + Vector3(0, 0.3, 0)
				var q := PhysicsRayQueryParameters3D.create(player.camera.global_position, target, 1 | 8, [player.get_rid()])
				var hit := get_world_3d().direct_space_state.intersect_ray(q)
				if not hit.is_empty():
					continue
				ld = d
				loot = l
		var downed: int = NetSession.world.nearby_downed_player() if NetSession.enabled and NetSession.world else 0
		var tower := defences.nearest(player)
		var npc := progression.nearest(player)
		var reading_notice := _looking_at_notice() and not downed
		var idle_prompt := "[T] Turmbaumenü · ab 120 P" if _tower_hint_remaining > 0.0 and not intro.showing_guidance() else ""
		var hut_fix: bool = hut != null and not downed and loot == null and tower == null and near == null and npc.is_empty() and hut.can_repair(player)
		if hut_fix: idle_prompt = hut.prompt_text()
		hud.set_prompt("[E] %s wiederbeleben · 3 Sekunden in der Nähe bleiben" % NetSession.roster[downed] if downed else (loot.prompt_text() if loot else ("Turm besetzt" if tower and tower.operator_peer else "[E] Aufsteigen / Bedienen · [R] Ausrichten · [F] Reparieren\nReichweite %d m · heller Sektor: Automatik" % roundi(tower.attack_range()) if tower else (near.prompt_text() if near else idle_prompt))))
		if not npc.is_empty() and not downed: hud.set_prompt(progression.prompt(npc))
		if reading_notice: hud.set_prompt("[E] Schild lesen · Eine seltsame Notiz")
		if _notice_open: hud.set_prompt("[E] Hinweis schließen")
		if _notice_open and Input.is_action_just_pressed("interact"):
			_close_notice()
		elif reading_notice and Input.is_action_just_pressed("interact"):
			_read_notice()
		elif not npc.is_empty() and not downed and Input.is_action_just_pressed("interact"):
			progression.interact(npc)
		elif downed and Input.is_action_just_pressed("interact"):
			NetSession.command("revive", [downed])
		elif loot and Input.is_action_just_pressed("interact"):
			var was_weapon: bool = loot is Loot and loot.kind == "weapon" and not weapons.unlocked.get(loot.id, false)
			if loot is Door:
				if loot.take(weapons, hud) and loot.is_open and achievements:
					achievements.event("door")
			else:
				loot.take(weapons, hud)
				if was_weapon and achievements:
					achievements.event("weapons")
			hud.set_prompt("")
		elif tower and Input.is_action_just_pressed("interact"):
			defences.request_mount(tower)
		elif near and Input.is_action_just_pressed("interact"):
			if NetSession.enabled: NetSession.command("repair" if near.level > 0 and near.hp < near.max_hp() else "build", [barricades.find(near)])
			else: near.purchase(player, "repair" if near.level > 0 and near.hp < near.max_hp() else "build")
		elif hut_fix and Input.is_action_just_pressed("interact"):
			if NetSession.enabled: NetSession.command("hut_repair")
			else:
				var error := hut.repair(player)
				if not error.is_empty(): hud.message(error, 2.0)
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
		var show := ["pistol", "revolver", "smg", "ak47", "shotgun"]
		if idx < show.size():
			weapons.unlock(show[idx])
			weapons.set_weapon(show[idx])
		for i in 8:
			await get_tree().process_frame
		print("VIEW %d fps=%d" % [idx, Engine.get_frames_per_second()])
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
