shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform int mode = 0; // fire, smoke, muzzle flash
varying vec4 tint;
varying float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	tint = COLOR;
	seed = float(INSTANCE_ID) * 1.731;
	float sx = length(MODEL_MATRIX[0].xyz), sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 flow = UV * vec2(4.0, 5.0) + vec2(seed, -TIME * (mode == 1 ? 0.7 : 3.7));
	float n = noise(flow) * 0.65 + noise(flow * 2.1) * 0.25 + noise(flow * 4.2) * 0.1;
	float envelope = 1.0 - smoothstep(0.18, 1.0, length(p));
	float mask = smoothstep(0.20, 0.7, envelope * (0.4 + n));
	if (mode == 1) {
		ALBEDO = tint.rgb * (0.65 + n * 0.35);
		ALPHA = mask * tint.a;
	} else {
		if (mode == 2) {
			float rays = pow(abs(cos(atan(p.y, p.x) * 3.0 + seed)), 12.0);
			mask *= 0.35 + rays * 0.65;
		}
		vec3 hot = mix(vec3(0.95, 0.13, 0.015), vec3(1.0, 0.82, 0.39), smoothstep(0.25, 0.8, envelope * n));
		ALBEDO = hot * tint.rgb;
		EMISSION = hot * tint.rgb * (mode == 2 ? 3.0 : 1.6);
		ALPHA = mask * tint.a;
	}
}
