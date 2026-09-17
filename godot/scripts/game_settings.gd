class_name GameSettings
extends Node

const PATH := "user://settings.cfg"
const PROFILES := ["Flüssig", "Ausgewogen", "Hohe Qualität"]
const LIMITS := [0, 60, 100, 120, 144, 165, 240]
const RANGES := [
	{"trees": 190.0, "props": 100.0, "detail": 45.0, "leaves": 32.0, "grass": 55.0},
	{"trees": 230.0, "props": 140.0, "detail": 65.0, "leaves": 45.0, "grass": 75.0},
	{"trees": 280.0, "props": 180.0, "detail": 90.0, "leaves": 65.0, "grass": 100.0},
]
var profile := 0
var fps_limit := 144
var vsync := false
var sensitivity := 1.0
var volume := 0.8
var show_fps := true
var env: Environment
var sun: DirectionalLight3D
var main: Node
var _flags: PackedStringArray
var _save_timer: Timer
var _testing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = get_parent()
	_flags = OS.get_cmdline_user_args()
	_testing = "--autotest" in _flags or "--benchmark" in _flags or "--smoke-test" in _flags
	if not _testing:
		var cfg := ConfigFile.new()
		if cfg.load(PATH) == OK:
			profile = clampi(int(cfg.get_value("video", "profile", 0)), 0, 2)
			fps_limit = int(cfg.get_value("video", "fps_limit", 144))
			if not fps_limit in LIMITS:
				fps_limit = 144
			vsync = bool(cfg.get_value("video", "vsync", false))
			show_fps = bool(cfg.get_value("video", "show_fps", true))
			sensitivity = clampf(float(cfg.get_value("input", "sensitivity", 1.0)), 0.2, 3.0)
			volume = clampf(float(cfg.get_value("audio", "volume", 0.8)), 0.0, 1.0)
	for arg in _flags:
		if arg.begins_with("--quality="):
			profile = clampi(arg.get_slice("=", 1).to_int(), 0, 2)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	Input.use_accumulated_input = false

func apply() -> void:
	var viewport := get_viewport()
	viewport.msaa_3d = Viewport.MSAA_DISABLED if profile == 0 else Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if profile == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.mesh_lod_threshold = [4.0, 2.5, 1.5][profile]
	viewport.scaling_3d_scale = [0.85, 1.0, 1.0][profile]
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if profile == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW if profile < 2 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW if profile < 2 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	Engine.max_fps = 0 if _testing else fps_limit
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync and not _testing else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	if env:
		env.ssao_enabled = profile > 0 and not "--no-ssao" in _flags
		env.ssil_enabled = profile == 2 and not "--no-ssil" in _flags
		env.volumetric_fog_enabled = profile > 0 and not "--no-vfog" in _flags
	if sun:
		sun.directional_shadow_max_distance = [65.0, 100.0, 150.0][profile]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if profile == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	for category: String in RANGES[profile]:
		for node in get_tree().get_nodes_in_group("render_" + category):
			node.visibility_range_end = RANGES[profile][category]
			node.visibility_range_end_margin = 4.0
	if main.player:
		main.player.mouse_sensitivity = sensitivity
	if main.hud:
		main.hud.fps_label.visible = show_fps

func _changed() -> void:
	apply()
	if not _testing:
		_save_timer.start()

func save() -> void:
	if _testing:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("video", "profile", profile)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("audio", "volume", volume)
	if cfg.save(PATH) != OK:
		push_warning("Einstellungen konnten nicht gespeichert werden.")

func add_controls(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	parent.add_child(grid)
	var quality := OptionButton.new()
	for name in PROFILES:
		quality.add_item(name)
	quality.select(profile)
	quality.item_selected.connect(func(i: int): profile = i; _changed())
	_row(grid, "Grafik", quality)
	var cap := OptionButton.new()
	for limit in LIMITS:
		cap.add_item("Unbegrenzt" if limit == 0 else "%d FPS" % limit)
	cap.select(LIMITS.find(fps_limit))
	cap.item_selected.connect(func(i: int): fps_limit = LIMITS[i]; _changed())
	_row(grid, "Bildratenlimit", cap)
	var sync := CheckButton.new()
	sync.button_pressed = vsync
	sync.toggled.connect(func(on: bool): vsync = on; _changed())
	_row(grid, "VSync", sync)
	var fps := CheckButton.new()
	fps.button_pressed = show_fps
	fps.toggled.connect(func(on: bool): show_fps = on; _changed())
	_row(grid, "FPS anzeigen", fps)
	var mouse := HSlider.new()
	mouse.min_value = 0.2
	mouse.max_value = 3.0
	mouse.step = 0.05
	mouse.value = sensitivity
	mouse.value_changed.connect(func(value: float): sensitivity = value; _changed())
	_row(grid, "Mausempfindlichkeit", mouse)
	var audio := HSlider.new()
	audio.max_value = 1.0
	audio.step = 0.01
	audio.value = volume
	audio.value_changed.connect(func(value: float): volume = value; _changed())
	_row(grid, "Lautstärke", audio)
	var fullscreen := Button.new()
	fullscreen.text = "Vollbild umschalten (F11)"
	fullscreen.pressed.connect(_fullscreen)
	parent.add_child(fullscreen)
	var quit_button := Button.new()
	quit_button.text = "Spiel beenden"
	quit_button.pressed.connect(func(): save(); get_tree().quit())
	parent.add_child(quit_button)

func _row(grid: GridContainer, title: String, control: Control) -> void:
	var label := Label.new()
	label.text = title
	grid.add_child(label)
	control.custom_minimum_size.x = 220
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)

func _fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if main.barricade_menu and main.barricade_menu.is_open:
			main.barricade_menu.close()
		elif main.inventory and main.inventory.is_open:
			main.inventory.close()
		elif main.skills and main.skills.is_open:
			main.skills.close()
		elif main.started and not main.over:
			if get_tree().paused:
				main._on_start()
			else:
				main._pause()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_fullscreen()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _testing and is_instance_valid(main) and main.started and not main.over and not get_tree().paused:
		main._pause()
