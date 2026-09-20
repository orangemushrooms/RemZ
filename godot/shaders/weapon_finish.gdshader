shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform vec4 color_c : source_color;
uniform float finish_metal = 0.2;
uniform float finish_roughness = 0.6;
uniform int pattern = 0;
varying vec3 local_pos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 cell = floor(p); vec3 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(cell), hash(cell+vec3(1,0,0)), f.x), mix(hash(cell+vec3(0,1,0)), hash(cell+vec3(1,1,0)), f.x), f.y), mix(mix(hash(cell+vec3(0,0,1)), hash(cell+vec3(1,0,1)), f.x), mix(hash(cell+vec3(0,1,1)), hash(cell+vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { local_pos = VERTEX; }
void fragment() {
	vec3 original = texture(base_tex, UV).rgb;
	float n = noise(local_pos * 16.0 + noise(local_pos * 5.0) * 2.5);
	if (pattern == 1) n = noise(local_pos * 4.0);
	if (pattern == 2) n = sin(local_pos.x * 38.0 + local_pos.y * 12.0 + n * 6.0) * 0.5 + 0.5;
	vec3 paint = mix(color_a.rgb, color_b.rgb, smoothstep(0.36, 0.42, n));
	paint = mix(paint, color_c.rgb, smoothstep(0.58, 0.64, n));
	float detail = clamp(dot(original, vec3(0.3, 0.59, 0.11)) * 1.8, 0.35, 1.2);
	float wear = smoothstep(0.78, 0.91, noise(local_pos * 140.0));
	ALBEDO = mix(paint * detail, original, 0.15 + wear * 0.6);
	METALLIC = finish_metal;
	ROUGHNESS = finish_roughness + (n - 0.5) * 0.12;
	if (has_normal) NORMAL_MAP = texture(normal_tex, UV).rgb;
}
