class_name AlpineAtmosphere
extends RefCounted

const SKY_SHADER := preload("res://shaders/alpine_sky.gdshader")
const PANORAMA := preload("res://assets/sky/alps_field_4k.hdr")

static func apply(env: Environment) -> void:
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	material.set_shader_parameter("alpine_panorama", PANORAMA)
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	# Time-of-day uniforms change only every 30 game seconds. Spread the small
	# reflection bake over frames, avoiding a full quality bake at each update.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0032
	env.fog_light_color = Color(0.59, 0.66, 0.70)
	env.fog_light_energy = 0.8
	env.fog_sun_scatter = 0.22
	env.fog_aerial_perspective = 0.35
	# The photograph already contains horizon haze: do not wash out the ranges.
	env.fog_sky_affect = 0.2
	# Keep height fog and the existing volumetric quality budgets unchanged.
	# Increasing the existing distance-fog density adds no new rendering pass.
