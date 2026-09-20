shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float age = 0.0;
uniform float fall = 2.2;
uniform float drag = 0.25;
uniform float star_size = 0.13;
varying float opacity;
varying vec3 tint;
void vertex() {
	float tail = COLOR.a;
	float t = max(0.0, age - tail * 0.42);
	float life = INSTANCE_CUSTOM.w;
	vec3 v = INSTANCE_CUSTOM.xyz;
	vec3 offset = v * (1.0 - exp(-drag * t)) / drag;
	offset.y -= fall * t * t;
	float fade = (1.0 - smoothstep(life * 0.55, life, age)) * smoothstep(0.0, 0.07, age);
	float twinkle = 0.72 + 0.28 * sin(age * 27.0 + v.x * 8.0 + v.z * 3.0);
	opacity = fade * mix(1.0, 0.14, tail) * twinkle;
	tint = COLOR.rgb;
	float size = star_size * mix(1.0, 0.5, tail);
	vec3 center = (MODEL_MATRIX * vec4(offset, 1.0)).xyz;
	vec3 world_vertex = center + INV_VIEW_MATRIX[0].xyz * VERTEX.x * size + INV_VIEW_MATRIX[1].xyz * VERTEX.y * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_vertex, 1.0);
}
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = exp(-r * r * 14.0);
	float halo = max(0.0, 1.0 - r);
	ALBEDO = mix(tint, vec3(1.0), core * 0.7) * 4.0;
	ALPHA = (core + halo * 0.12) * opacity;
}
