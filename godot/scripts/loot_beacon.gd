# A depth-tested, softly animated column visible above a valuable world pickup.
class_name LootBeacon
extends Node3D

const COLORS := {"epic": Color(0.67, 0.22, 1.0), "legendary": Color(1.0, 0.62, 0.12)}
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color;
uniform float strength = 1.0;
void fragment() {
	float vertical = smoothstep(0.0, 0.28, UV.y) * smoothstep(0.0, 0.06, 1.0 - UV.y);
	float ribbons = pow(0.5 + 0.5 * sin(UV.x * 50.265 + sin(UV.y * 12.0 - TIME * 1.1)), 5.0);
	float pulse = 0.88 + 0.12 * sin(TIME * 1.8 - UV.y * 7.0);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * 1.8;
	ALPHA = vertical * pulse * (0.10 + ribbons * 0.22) * strength;
}
"""
static var _shader: Shader
var tier := "epic"

func setup(rarity: String, item_name: String) -> void:
	tier = rarity
	name = "LootBeacon"
	var color: Color = COLORS[tier]
	var height := 9.0 if tier == "legendary" else 7.5
	if not _shader:
		_shader = Shader.new()
		_shader.code = SHADER
	for halo in 2:
		var mesh := CylinderMesh.new()
		mesh.height = height
		mesh.bottom_radius = 0.52 if halo else 0.18
		mesh.top_radius = 0.32 if halo else 0.09
		mesh.radial_segments = 32
		mesh.cap_top = false
		mesh.cap_bottom = false
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter("tint", color)
		material.set_shader_parameter("strength", 0.3 if halo else 1.0)
		var column := MeshInstance3D.new()
		column.mesh = mesh
		column.material_override = material
		column.position.y = height * 0.5
		column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(column)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 2.0
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.43
	torus.outer_radius = 0.47
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = glow
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var sparks := CPUParticles3D.new()
	sparks.amount = 18
	sparks.lifetime = 2.8
	sparks.preprocess = 2.8
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.38
	sparks.direction = Vector3.UP
	sparks.spread = 12.0
	sparks.initial_velocity_min = 0.45
	sparks.initial_velocity_max = 1.1
	sparks.gravity = Vector3(0, 0.15, 0)
	sparks.scale_amount_min = 0.018
	sparks.scale_amount_max = 0.035
	var spark := SphereMesh.new()
	spark.radial_segments = 6
	spark.rings = 3
	spark.material = glow
	sparks.mesh = spark
	sparks.position.y = 0.12
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)
	var label := Label3D.new()
	label.text = Lang.t(tier.to_upper()) + "\n" + Lang.t(item_name)
	label.position.y = 1.15
	label.modulate = color.lightened(0.35)
	label.outline_modulate = Color(0.015, 0.01, 0.02, 0.95)
	label.font_size = 34
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 35.0
	label.visibility_range_end_margin = 5.0
	add_child(label)
