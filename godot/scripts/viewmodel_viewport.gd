class_name ViewmodelViewport
extends CanvasLayer

# First-person geometry is rendered at native resolution, independently of the
# world's FSR scale. It cannot disappear into nearby walls or inherit forest fog.
var camera: Camera3D
var viewport: SubViewport
var _environment: Environment
var _key_light: DirectionalLight3D

func _ready() -> void:
	layer = 0
	viewport = SubViewport.new()
	viewport.name = "ViewmodelViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	add_child(viewport)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	_environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.87, 0.94)
	env.ambient_light_energy = 0.65
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/viewmodel_sky.gdshader")
	env.sky = Sky.new()
	env.sky.sky_material = sky_material
	env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment = env
	viewport.add_child(environment)
	camera = Camera3D.new()
	camera.name = "ViewmodelCamera"
	camera.fov = 75.0
	camera.near = 0.025
	camera.far = 5.0
	camera.cull_mask = 2
	viewport.add_child(camera)
	camera.make_current()
	var key := DirectionalLight3D.new()
	_key_light = key
	key.light_cull_mask = 2
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_color = Color(1.0, 0.95, 0.85)
	key.light_energy = 1.25
	key.shadow_enabled = false
	viewport.add_child(key)
	var image := TextureRect.new()
	image.name = "FirstPerson"
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = viewport.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_resize)
	_resize()

func set_daylight(daylight: float, twilight: float) -> void:
	# Hands remain legible while sharing the world's night/sunset palette.
	_environment.ambient_light_energy = lerpf(0.26, 0.65, daylight)
	_environment.background_energy_multiplier = lerpf(0.22, 1.0, daylight)
	_environment.ambient_light_color = Color(0.65, 0.74, 0.94).lerp(Color(0.82, 0.87, 0.94), daylight)
	_key_light.light_energy = lerpf(0.38, 1.25, daylight)
	_key_light.light_color = Color(0.68, 0.76, 0.92).lerp(Color(1.0, 0.95, 0.85), daylight).lerp(Color(1.0, 0.64, 0.38), twilight * 0.45)

func _resize() -> void:
	# The root's canvas may use logical pixels. The view model uses window pixels.
	var pixels := DisplayServer.window_get_size()
	viewport.size = Vector2i(maxi(pixels.x, 64), maxi(pixels.y, 64))
