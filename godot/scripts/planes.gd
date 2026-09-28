extends Node3D
## A separate, explicitly solo exploration scene. No wave/progress writes.
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

func _ready() -> void:
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
	await get_tree().physics_frame
	await get_tree().physics_frame
	started = true
	player.active = true
	ready_for_exploration = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	boot.close()
	boot = null
	print("PLANES_READY trees=%d birds=%d crops=%s" % [landscape.tree_count,birds.size(),cornfield.counts])

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
	menu.position = Vector2(-205,-190)
	menu.custom_minimum_size = Vector2(410,350)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.045,0.035,0.97)
	style.set_content_margin_all(24)
	menu.add_theme_stylebox_override("panel",style)
	ui.add_child(menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	menu.add_child(column)
	var label := Label.new()
	label.text = "THE PLANES · EXPLORATION"
	label.add_theme_font_size_override("font_size",22)
	column.add_child(label)
	for spec in [["Continue exploring",-1],["View towards Sennhof",0],["View of the junction",1],["View towards Core",2],["Back to region selection",3]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size.y = 38
		var action: int = spec[1]
		button.pressed.connect(func():
			if action==3: return_to_map()
			else:
				if action>=0: set_view(action)
				set_menu(false))
		column.add_child(button)
	menu.hide()

func set_menu(open: bool) -> void:
	menu.visible = open
	player.active = not open
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open: menu.get_child(0).get_child(1).grab_focus()

func return_to_map() -> void:
	if _leaving: return
	_leaving = true
	player.active = false
	get_tree().set_meta("open_campaign_map",true)
	BootScreen.cover(get_tree())
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_exploration: return
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
