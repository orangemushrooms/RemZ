class_name ViewmodelViewport
extends CanvasLayer

# First-person geometry is rendered at native resolution, independently of the
# world's FSR scale. It cannot disappear into nearby walls or inherit forest fog.
var camera: Camera3D
var viewport: SubViewport

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
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.87, 0.94)
	env.ambient_light_energy = 0.65
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.26, 0.32, 0.42)
	sky_material.sky_horizon_color = Color(0.64, 0.66, 0.69)
	sky_material.ground_bottom_color = Color(0.12, 0.14, 0.11)
	sky_material.ground_horizon_color = Color(0.46, 0.47, 0.44)
	env.sky = Sky.new()
	env.sky.sky_material = sky_material
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

func _resize() -> void:
	# The root's canvas may use logical pixels. The view model uses window pixels.
	var pixels := DisplayServer.window_get_size()
	viewport.size = Vector2i(maxi(pixels.x, 64), maxi(pixels.y, 64))
