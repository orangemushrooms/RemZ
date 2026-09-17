shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

varying float age;
varying float opacity;
varying float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
	age = INSTANCE_CUSTOM.r;
	opacity = INSTANCE_CUSTOM.g;
	seed = INSTANCE_CUSTOM.b * 51.0;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 flow = UV * 4.0 + vec2(seed, -age * 1.8);
	float wisps = noise(flow) * 0.6 + noise(flow * 2.1 + age) * 0.3 + noise(flow * 4.3) * 0.1;
	float edge = 1.0 - smoothstep(0.15, 1.0, length(p));
	float density = smoothstep(0.22, 0.78, wisps) * edge;
	ALBEDO = mix(vec3(0.36, 0.38, 0.40), vec3(0.72, 0.73, 0.74), wisps);
	ALPHA = density * opacity;
}
