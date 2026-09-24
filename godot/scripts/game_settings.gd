class_name GameSettings
extends Node

const PATH := "user://settings.cfg"
const PROFILES := ["Smooth", "Balanced", "High quality"]
const LIMITS := [0, 60, 100, 120, 144, 165, 240]
# hp / dmg: zombie health and damage, count: zombies per wave, speed: zombie speed, drop: supply drop chance,
# score: points per kill, regen: player regeneration
const DIFFICULTIES := [
	{ "name": "Easy", "desc": "For getting to know the hut: weaker zombies, smaller waves, plenty of supplies.", "hp": 0.8, "dmg": 0.7, "count": 0.8, "speed": 1.0, "drop": 1.4, "score": 0.8, "regen": 1.3 },
	{ "name": "Normal", "desc": "The balanced night on the Heitersberg.", "hp": 1.0, "dmg": 1.0, "count": 1.0, "speed": 1.0, "drop": 1.0, "score": 1.0, "regen": 1.0 },
	{ "name": "Hard", "desc": "Tougher and faster hordes, fewer supplies, 30% more Rem Dollars.", "hp": 1.25, "dmg": 1.3, "count": 1.25, "speed": 1.05, "drop": 0.8, "score": 1.3, "regen": 0.8 },
	{ "name": "Nightmare", "desc": "Huge waves, brutal hits, barely any regeneration. 70% more Rem Dollars for the high scores.", "hp": 1.5, "dmg": 1.7, "count": 1.5, "speed": 1.12, "drop": 0.6, "score": 1.7, "regen": 0.5 },
]
const RANGES := [
	{"trees": 190.0, "props": 100.0, "detail": 45.0, "leaves": 32.0, "grass": 55.0},
	{"trees": 230.0, "props": 140.0, "detail": 65.0, "leaves": 45.0, "grass": 75.0},
	{"trees": 280.0, "props": 180.0, "detail": 90.0, "leaves": 65.0, "grass": 100.0},
]
var profile := 0
var difficulty := 1
var fps_limit := 144
var vsync := false
var sensitivity := 1.0
var volume := 0.8
var tremor := 1.0
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
			tremor = clampf(float(cfg.get_value("video", "tremor", 1.0)), 0.0, 1.0)
			difficulty = clampi(int(cfg.get_value("game", "difficulty", 1)), 0, DIFFICULTIES.size() - 1)
	for arg in _flags:
		if arg.begins_with("--quality="):
			profile = clampi(arg.get_slice("=", 1).to_int(), 0, 2)
		if arg.begins_with("--difficulty="):
			difficulty = clampi(arg.get_slice("=", 1).to_int(), 0, DIFFICULTIES.size() - 1)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	Input.use_accumulated_input = false

# "--gfx-off=a,b": leave out single upgrades of the high profile for benchmarks (ssaoultra, mip, aniso,
# radiance, debanding, smaa). Measured 24 Sep 2026 on the plaza (docs/PERFORMANCE.md): an 8k shadow atlas cost
# 40 %, full-resolution SSAO/SSIL 8 %, blended shadow splits 7 %, PCSS SOFT_HIGH 3 %, a 24-bit shadow atlas 3 %,
# 16x anisotropy 2.5 %, 96^3 fog froxels 1.5 % - those stay out; what is left costs about 2 % together
# (8x anisotropy 1.2 %, the rest within the noise).
func _gfx(feature: String) -> bool:
	for flag in _flags:
		if flag.begins_with("--gfx-off=") and feature in flag.substr(10).split(","):
			return false
	return true

func apply() -> void:
	var viewport := get_viewport()
	viewport.msaa_3d = Viewport.MSAA_DISABLED if (profile == 0 or "--no-msaa" in _flags) else Viewport.MSAA_2X
	# SMAA (Godot 4.7) resolves the fast profile's edges cleaner than FXAA at the same cost.
	viewport.screen_space_aa = (Viewport.SCREEN_SPACE_AA_SMAA if _gfx("smaa") else Viewport.SCREEN_SPACE_AA_FXAA) if profile == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = _gfx("debanding")           # dusk sky and fog gradients without banding, no measurable cost
	viewport.mesh_lod_threshold = [4.0, 2.5, 1.5][profile]
	viewport.scaling_3d_scale = [0.85, 1.0, 1.0][profile]
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if profile == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	# Texture sharpness: 8x anisotropy from the balanced profile up and a slightly negative mipmap bias on
	# the high one, which TAA resolves into crisper ground, bark and cloth detail at grazing angles.
	viewport.anisotropic_filtering_level = [Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_8X][profile] if _gfx("aniso") else Viewport.ANISOTROPY_4X
	viewport.texture_mipmap_bias = [0.0, -0.15, -0.3][profile] if _gfx("mip") else 0.0
	var soft: Array = [RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft[profile])
	RenderingServer.positional_soft_shadow_filter_set_quality(soft[profile])
	RenderingServer.directional_shadow_atlas_set_size(4096, true)   # an 8k atlas halved the frame rate, 24-bit depth cost 3 %
	# SSAO / SSIL at ultra sampling on the high profile, still at half resolution (full resolution cost 8 %).
	var ao_quality: Array = [RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_HIGH, RenderingServer.ENV_SSAO_QUALITY_ULTRA if _gfx("ssaoultra") else RenderingServer.ENV_SSAO_QUALITY_HIGH]
	var gi_quality: Array = [RenderingServer.ENV_SSIL_QUALITY_LOW, RenderingServer.ENV_SSIL_QUALITY_HIGH, RenderingServer.ENV_SSIL_QUALITY_ULTRA if _gfx("ssaoultra") else RenderingServer.ENV_SSIL_QUALITY_HIGH]
	RenderingServer.environment_set_ssao_quality(ao_quality[profile], true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(gi_quality[profile], true, 0.5, 4, 50.0, 300.0)
	Engine.max_fps = 0 if _testing else fps_limit
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync and not _testing else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	if env:
		env.ssao_enabled = profile > 0 and not "--no-ssao" in _flags
		env.ssil_enabled = profile == 2 and not "--no-ssil" in _flags
		env.volumetric_fog_enabled = profile > 0 and not "--no-vfog" in _flags
		# sharper sky reflections on wet gunmetal and the pond; the incremental bake keeps it free
		if env.sky: env.sky.radiance_size = Sky.RADIANCE_SIZE_256 if profile == 2 and _gfx("radiance") else Sky.RADIANCE_SIZE_128
	if sun:
		sun.directional_shadow_max_distance = [65.0, 100.0, 150.0][profile]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if profile == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	for category: String in RANGES[profile]:
		for node in get_tree().get_nodes_in_group("render_" + category):
			node.visibility_range_end = RANGES[profile][category]
			node.visibility_range_end_margin = 4.0
	if main.player:
		main.player.mouse_sensitivity = sensitivity
		main.player.tremor_scale = tremor
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
	cfg.set_value("video", "tremor", tremor)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "language", Lang.current)
	if cfg.save(PATH) != OK:
		push_warning("Settings could not be saved.")

func add_controls(parent: VBoxContainer, with_quit: bool = true) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	parent.add_child(grid)
	# Language names stay in their own language (never translated), so a player always finds theirs.
	var language := OptionButton.new()
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for name in Lang.language_names():
		language.add_item(name)
	language.select(maxi(Lang.language_codes().find(Lang.current), 0))
	language.item_selected.connect(func(i: int): Lang.set_language(Lang.language_codes()[i]); _changed())
	_row(grid, "Language", language)
	var quality := OptionButton.new()
	for name in PROFILES:
		quality.add_item(name)
	quality.select(profile)
	quality.item_selected.connect(func(i: int): profile = i; _changed())
	_row(grid, "Graphics", quality)
	var cap := OptionButton.new()
	for limit in LIMITS:
		cap.add_item("Unlimited" if limit == 0 else "%d FPS" % limit)
	cap.select(LIMITS.find(fps_limit))
	cap.item_selected.connect(func(i: int): fps_limit = LIMITS[i]; _changed())
	_row(grid, "Frame rate limit", cap)
	var sync := CheckButton.new()
	sync.button_pressed = vsync
	sync.toggled.connect(func(on: bool): vsync = on; _changed())
	_row(grid, "VSync", sync)
	var fps := CheckButton.new()
	fps.button_pressed = show_fps
	fps.toggled.connect(func(on: bool): show_fps = on; _changed())
	_row(grid, "Show FPS", fps)
	var mouse := HSlider.new()
	mouse.min_value = 0.2
	mouse.max_value = 3.0
	mouse.step = 0.05
	mouse.value = sensitivity
	mouse.value_changed.connect(func(value: float): sensitivity = value; _changed())
	_row(grid, "Mouse sensitivity", mouse)
	var audio := HSlider.new()
	audio.max_value = 1.0
	audio.step = 0.01
	audio.value = volume
	audio.value_changed.connect(func(value: float): volume = value; _changed())
	_row(grid, "Volume", audio)
	var shake := HSlider.new()
	shake.max_value = 1.0
	shake.step = 0.05
	shake.value = tremor
	shake.tooltip_text = "Ground tremors from titans: off on the left, full strength on the right."
	shake.value_changed.connect(func(value: float): tremor = value; _changed())
	_row(grid, "Titan ground tremors", shake)
	var fullscreen := Button.new()
	fullscreen.text = "Toggle fullscreen (F11)"
	fullscreen.pressed.connect(_fullscreen)
	parent.add_child(fullscreen)
	if with_quit:
		var quit_button := Button.new()
		quit_button.text = "Quit game"
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
		if main.progression and main.progression.is_open:
			main.progression.close()
		elif main.barricade_menu and main.barricade_menu.is_open:
			main.barricade_menu.close()
		elif main.inventory and main.inventory.is_open:
			main.inventory.close()
		elif main.skills and main.skills.is_open:
			main.skills.close()
		elif main.started and not main.over:
			if get_tree().paused or (NetSession.enabled and main.hud.overlay.visible):
				main._on_start()
			else:
				main._pause()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_fullscreen()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _testing and is_instance_valid(main) and main.started and not main.over and main.player.active and not get_tree().paused:
		main._pause()
