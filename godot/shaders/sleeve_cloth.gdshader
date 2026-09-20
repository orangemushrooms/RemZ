shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(0.72, 0.79, 0.59, 1.0);
uniform float normal_strength = 1.0;
uniform float roughness_factor = 1.0;
instance uniform float cloth_clock = 0.0;
instance uniform float shot_age = 10.0;
instance uniform float shot_strength = 0.0;
instance uniform float movement = 0.0;
instance uniform float side = 1.0;
instance uniform vec3 elbow_offset = vec3(0.0);

void vertex() {
	// COLOR.r records distance from the cuff, independent of the texture UVs.
	// The first rings never move, so the glove/sleeve seam stays closed.
	float t = COLOR.r;
	VERTEX += elbow_offset * smoothstep(0.0, 1.0, t);
	float free_cloth = smoothstep(0.035, 0.30, t);
	float shot_wave = sin(shot_age * 29.0 - t * 7.0 + side * 0.35) * exp(-shot_age * 7.5) * shot_strength;
	float stride = sin(cloth_clock * 10.0 - t * 5.0 + side) * movement;
	float breath = sin(cloth_clock * 2.1 + t * 3.0 + side) * 0.12;
	// Position-based motion also agrees across duplicated UV/normal seam vertices.
	// Offsetting along split normals would open tiny cracks in the sleeve.
	VERTEX += vec3(side * 0.65, 0.7, 0.2) * free_cloth * (shot_wave * 0.0035 + stride * 0.0015 + breath * 0.001);
	VERTEX.y += free_cloth * (shot_wave * 0.002 + stride * 0.001);
}
void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb;
	ROUGHNESS = clamp(texture(roughness_tex, UV).g * roughness_factor, 0.55, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.25;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
