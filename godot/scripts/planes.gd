extends Node3D
## Solo exploration and an explicitly started 25-wave survival run.
var player: Player
var weapons: Weapons
var hud: Hud
var settings: GameSettings
var day_night: DayNightCycle
var intro: Intro
var cornfield: Node3D
var landscape: Node3D
var started := false
var over := false
var ready_for_exploration := false
var birds: Array[Node3D] = []
var menu: PanelContainer
var ui: CanvasLayer
var minimap: Control
var compass: Label
var _building_cells: Dictionary = {}
var _leaving := false
var _wind: AudioStreamPlayer
var boot: BootScreen
var campaign := Campaign.new()
var difficulty: Dictionary
var waves: Node
var weather: Weather
var zombies_root: Node3D
var nav_region: NavigationRegion3D
var survival_active := false
var preparing_survival := false
var victory := false
var secret_night: SecretNight
var fill_light: DirectionalLight3D
var progression: Progression
var stats: RunStats
var classes: Node
var hunting: Node3D
var _menu_actions := {}
var _spawn_rng := RandomNumberGenerator.new()
var _nav_shape := CapsuleShape3D.new()
var _kills := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if NetSession.enabled:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	boot = BootScreen.find(get_tree())
	if not boot:
		boot = BootScreen.new()
		add_child(boot)
	boot.step(0.04)
	await get_tree().process_frame
	Map.use_region("planes")
	Map._ensure()
	_index_buildings()
	settings = GameSettings.new()
	add_child(settings)
	settings.set_process_unhandled_input(false)
	difficulty = GameSettings.DIFFICULTIES[settings.difficulty]
	campaign.select("planes")
	_environment()
	boot.step(0.15,true)
	landscape = load("res://scripts/planes_landscape.gd").new()
	add_child(landscape)
	landscape.build()
	boot.step(0.48,true)
	player = load("res://scripts/planes_player.gd").new()
	player.name = "Explorer"
	add_child(player)
	player.camera.far = 1800
	player.flashlight.visible = false
	set_view(0)
	cornfield = load("res://scripts/planes_crops.gd").new()
	add_child(cornfield)
	cornfield.build(self)
	boot.step(0.85,true)
	day_night = DayNightCycle.new()
	day_night.clock_seconds = 12.0*3600
	day_night.set_process(false)
	add_child(day_night)
	zombies_root = Node3D.new()
	zombies_root.name = "Zombies"
	add_child(zombies_root)
	_spawn_rng.seed = 935728
	_nav_shape.radius = 0.65
	_nav_shape.height = 2.5
	player.died.connect(func(): finish_survival(false))
	_birds()
	_interface()
	settings.apply()
	# Summer reference lighting: no Forest-specific morning fog or weather schedule.
	settings.env.volumetric_fog_enabled = false
	_wind = AudioStreamPlayer.new()
	_wind.stream = load("res://assets/audio/sfx/Forest_Wind_Ambiance.mp3")
	_wind.volume_db = -22
	_wind.finished.connect(func(): _wind.play())
	add_child(_wind)
	_wind.play()
	for child in get_children():
		if child!=ui and child!=boot: child.process_mode = Node.PROCESS_MODE_PAUSABLE
	child_entered_tree.connect(func(child: Node): child.process_mode = Node.PROCESS_MODE_PAUSABLE)
	await get_tree().physics_frame
	await get_tree().physics_frame
	started = true
	player.active = true
	ready_for_exploration = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	boot.close()
	boot = null
	print("PLANES_READY trees=%d birds=%d crops=%s" % [landscape.tree_count,birds.size(),cornfield.counts])
	if "--planes-survival" in OS.get_cmdline_user_args(): start_survival.call_deferred()

func _index_buildings() -> void:
	for building: Dictionary in Map.VILLAGE:
		var rect := Rect2(Vector2(building.poly[0][0],building.poly[0][1]),Vector2.ZERO)
		for p in building.poly: rect = rect.expand(Vector2(p[0],p[1]))
		rect = rect.grow(4)
		for z in range(floori(rect.position.y/32),floori(rect.end.y/32)+1):
			for x in range(floori(rect.position.x/32),floori(rect.end.x/32)+1):
				var key := Vector2i(x,z)
				if not _building_cells.has(key): _building_cells[key] = []
				_building_cells[key].append(rect)

func near_building(p: Vector2) -> bool:
	for rect: Rect2 in _building_cells.get(Vector2i(floori(p.x/32),floori(p.y/32)),[]):
		if rect.has_point(p): return true
	return false

func _environment() -> void:
	RenderingServer.global_shader_parameter_set("remz_wetness",0.0)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color(0.15,0.39,0.78)
	material.sky_horizon_color = Color(0.66,0.79,0.89)
	material.sky_curve = 0.35
	material.ground_horizon_color = material.sky_horizon_color
	material.ground_bottom_color = Color(0.2,0.27,0.15)
	material.sun_angle_max = 4
	sky.sky_material = material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.68,0.77,0.85)
	environment.fog_density = 0.00018
	environment.fog_sky_affect = 0.12
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56,-32,0)
	sun.light_color = Color(1.0,0.97,0.88)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140
	add_child(sun)
	settings.env = environment
	settings.sun = sun

func _birds() -> void:
	for i in 14:
		var bird := load("res://scripts/field_bird.gd").new() as Node3D
		bird.game = self
		bird.index = i
		bird.owl = i>=12
		var at := Vector2(-94+(i%6)*18,28+(i/6)*18)
		bird.home = Map.ground_pos(at.x,at.y)+Vector3.UP*(4 if bird.owl else 0.2)
		bird.position = bird.home
		add_child(bird)
		birds.append(bird)

func set_view(index: int) -> void:
	var view: Dictionary = Map._d.views[clampi(index,0,2)]
	var p := Vector2(view.pos[0],view.pos[1])
	var target := Vector2(view.target[0],view.target[1])
	player.position = Map.ground_pos(p.x,p.y)+Vector3.UP*0.08
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(-(target.x-p.x),-(target.y-p.y))
	player.pitch = 0.015
	player.head.rotation.x = player.pitch
	player.reset_physics_interpolation()
	player._motion_ready = false
	if cornfield: cornfield.update_lod()

func _interface() -> void:
	ui = CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var title := Label.new()
	title.text = "THE PLANES  /  REMETSCHWIL"
	title.position = Vector2(28,24)
	title.add_theme_font_size_override("font_size",22)
	ui.add_child(title)
	var controls := Label.new()
	controls.text = "WASD Walk · Shift Sprint · Space Jump · Ctrl Crouch · M Map · Esc Menu"
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(28,-40)
	controls.add_theme_color_override("font_shadow_color",Color.BLACK)
	controls.add_theme_constant_override("shadow_offset_x",1)
	controls.add_theme_constant_override("shadow_offset_y",1)
	ui.add_child(controls)
	compass = Label.new()
	compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-80,28)
	compass.custom_minimum_size.x = 160
	compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(compass)
	minimap = load("res://scripts/planes_minimap.gd").new()
	minimap.game = self
	minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.position = Vector2(-272,-228)
	minimap.size = Vector2(244,190)
	ui.add_child(minimap)
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.position = Vector2(-205,-245)
	menu.custom_minimum_size = Vector2(410,440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.045,0.035,0.97)
	style.set_content_margin_all(24)
	menu.add_theme_stylebox_override("panel",style)
	ui.add_child(menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	menu.add_child(column)
	var label := Label.new()
	label.text = "THE PLANES"
	label.add_theme_font_size_override("font_size",22)
	column.add_child(label)
	for spec in [["Continue",-1],["Start 25-wave survival",4],["View towards Sennhof",0],["View of the junction",1],["View towards Core",2],["Back to exploration",5],["Back to region selection",3]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size.y = 38
		var action: int = spec[1]
		button.pressed.connect(func():
			if action==3: return_to_map()
			elif action==4: start_survival()
			elif action==5: stop_survival()
			else:
				if action>=0: set_view(action)
				set_menu(false))
		column.add_child(button)
		_menu_actions[action] = button
	menu.hide()

func set_menu(open: bool) -> void:
	menu.visible = open
	player.active = not open and not over
	player.velocity = Vector3.ZERO
	get_tree().paused = open
	_menu_actions[-1].disabled = over
	_menu_actions[4].disabled = survival_active and not over
	_menu_actions[5].visible = survival_active or over
	for action in [0,1,2]: _menu_actions[action].disabled = survival_active
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open: menu.get_child(0).get_child(1).grab_focus()

func _pause() -> void:
	if ready_for_exploration and not preparing_survival: set_menu(true)

func return_to_map() -> void:
	if _leaving: return
	_leaving = true
	player.active = false
	get_tree().set_meta("open_campaign_map",true)
	BootScreen.cover(get_tree())
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_exploration or preparing_survival: return
	if event.is_action_pressed("pause"):
		set_menu(not menu.visible)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_M: minimap.visible = not minimap.visible
		if event.keycode==KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(_delta: float) -> void:
	if not ready_for_exploration: return
	var heading := fposmod(-rad_to_deg(player.rotation.y),360)
	var dirs := ["N","NE","E","SE","S","SW","W","NW"]
	compass.text = "%s  %03d°" % [dirs[roundi(heading/45)%8],heading]
	minimap.queue_redraw()

func start_survival() -> void:
	if preparing_survival or (survival_active and not over) or _leaving: return
	preparing_survival = true
	set_menu(false)
	player.active = false
	boot = BootScreen.cover(get_tree())
	boot.step(0.1)
	await get_tree().process_frame
	if not nav_region:
		nav_region = await load("res://scripts/planes_navigation.gd").prepare(self)
	if nav_region.navigation_mesh.get_polygon_count()==0:
		preparing_survival = false
		boot.close()
		boot = null
		nav_region.queue_free()
		nav_region = null
		set_menu(true)
		push_error("Planes navigation could not be prepared")
		return
	boot.step(0.4,true)
	if not weapons:
		hud = load("res://scripts/planes_hud.gd").new()
		hud.game = self
		hud.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(hud)
		player.hud = hud
		weapons = Weapons.new()
		weapons.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(weapons)
		weapons.setup(player,hud,zombies_root)
		weapons.unlocked.ak47 = true
		weapons.unlocked.shotgun = true
		boot.step(0.6,true)
		Zombie.preload_models(self,load("res://scripts/planes_waves.gd").KINDS)
		await Zombie.prewarm_visuals(self,false)
	_clear_combat()
	if waves: waves.queue_free()
	waves = load("res://scripts/planes_waves.gd").new()
	waves.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(waves)
	waves.setup(self)
	if not weather:
		weather = load("res://scripts/planes_weather.gd").new()
		weather.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(weather)
		weather.setup(self)
	weather.elapsed = 0.0
	weather.force("clear")
	weather.release()
	weapons.process_mode = Node.PROCESS_MODE_PAUSABLE
	weapons.viewmodel.show()
	weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	weapons.set_weapon("ak47")
	weapons.refill_all()
	weapons.grenades = 3
	weapons.update_hud()
	hud.show()
	over = false
	victory = false
	survival_active = true
	_kills = 0
	player.alive = true
	player.downed = false
	player.self_revives = 1
	player.hp = player.max_hp
	player.regen_timer = 0
	player.regen_mul = float(difficulty.regen)
	player.set_crouching(false,false)
	hud.set_health(player.hp)
	hud.message(Lang.t("25 waves · 1/2/3 weapons · R reload · G grenade · Enter starts the next wave"),8)
	set_view(0)
	await get_tree().physics_frame
	player.active = true
	preparing_survival = false
	boot.close()
	boot = null
	print("PLANES_SURVIVAL_READY")

func stop_survival() -> void:
	if preparing_survival: return
	survival_active = false
	over = false
	victory = false
	if waves:
		waves.queue_free()
		waves = null
	_clear_combat()
	if weapons:
		weapons.process_mode = Node.PROCESS_MODE_DISABLED
		weapons.viewmodel.hide()
		weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		weapons._reset_scope()
	if hud: hud.hide()
	player.alive = true
	player.downed = false
	player.hp = player.max_hp
	player.set_crouching(false,false)
	set_menu(false)

func _clear_combat() -> void:
	for enemy in zombies_root.get_children():
		if enemy is Zombie and is_instance_valid(enemy._pool): enemy._pool.queue_free()
		enemy.queue_free()
	for child in get_children():
		if child is Grenade or child is Pickup: child.queue_free()

func finish_survival(won: bool) -> void:
	if not survival_active or over: return
	over = true
	victory = won
	if hud: hud.message(Lang.t("THE PLANES SECURED · 25 / 25") if won else Lang.t("Run ended. Try again or continue exploring."),3600)
	set_menu(true)

func alive_zombies() -> int:
	var count := 0
	for enemy in zombies_root.get_children():
		if enemy is Zombie and enemy.alive: count += 1
	return count

func spawn_enemy(kind: String, wave_number: int) -> Zombie:
	var nav := nav_region.get_navigation_map()
	var target := NavigationServer3D.map_get_closest_point(nav,player.position)
	for attempt in 14:
		var angle := _spawn_rng.randf()*TAU
		var distance := _spawn_rng.randf_range(32,52)
		var p := Vector2(player.position.x,player.position.z)+Vector2(cos(angle),sin(angle))*distance
		if not Map.BOUNDS.grow(-4).has_point(p) or near_building(p): continue
		var surface := Map.ground_pos(p.x,p.y)
		var at := NavigationServer3D.map_get_closest_point(nav,surface)
		if at.distance_to(surface)>1.5 or at.distance_to(player.position)<28: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _nav_shape
		query.transform.origin = at+Vector3.UP*1.5
		query.collision_mask = 1|2
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		var path := NavigationServer3D.map_get_path(nav,at,target,true)
		if path.is_empty() or path[-1].distance_to(target)>1.5: continue
		return create_enemy(kind,at,wave_number)
	return null

func create_enemy(kind: String, at: Vector3, wave_number: int) -> Zombie:
	var enemy := Zombie.new()
	enemy.setup(kind,player,[],minf(1.65,1+(wave_number-1)*0.025)*float(difficulty.speed),_enemy_killed)
	enemy.hp *= (1.0+(wave_number-1)*0.055)*float(difficulty.hp)
	enemy.max_hp = enemy.hp
	enemy.damage_mul = float(difficulty.dmg)
	enemy.position = at+Vector3.UP*0.15
	zombies_root.add_child(enemy)
	enemy.begin_hunt()
	return enemy

func _enemy_killed(enemy: Zombie) -> void:
	if waves: waves.trim_corpses.call_deferred()
	_kills += 1
	# Predictable supplies keep later waves viable without shops or an economy.
	if _kills%3==0:
		var drop := Pickup.new()
		drop.setup("ammo")
		drop._light.visible = false
		add_child(drop)
		drop.position = Map.ground_pos(enemy.position.x,enemy.position.z)
