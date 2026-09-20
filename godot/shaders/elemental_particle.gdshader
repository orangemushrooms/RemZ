shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform bool frost = false;
varying vec4 tint;
void vertex() {
	tint = COLOR;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float mask;
	vec3 color;
	if (frost) {
		float angle = atan(p.y, p.x);
		float ray = pow(abs(cos(angle * 3.0)), 18.0);
		mask = (1.0 - smoothstep(0.15, 1.0, length(p))) * (0.2 + 0.8 * ray);
		color = mix(vec3(0.12, 0.55, 1.0), vec3(0.8, 0.97, 1.0), mask);
	} else {
		float rise = 1.0 - UV.y;
		float flicker = sin(UV.y * 17.0 - TIME * 13.0 + tint.r * 9.0) * 0.09;
		float width = mix(0.65, 0.03, rise);
		mask = (1.0 - smoothstep(width * 0.3, width, abs(p.x + flicker))) * sin(UV.y * 3.14159);
		color = mix(vec3(1.0, 0.055, 0.005), vec3(1.0, 0.85, 0.24), mask * UV.y);
	}
	ALBEDO = color * 2.3;
	ALPHA = mask * tint.a;
}
