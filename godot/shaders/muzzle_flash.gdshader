shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float phase = 0.0;
uniform float intensity = 1.0;
uniform bool axial = false;
uniform vec3 edge_color : source_color = vec3(1.0, 0.18, 0.015);
uniform vec3 core_color : source_color = vec3(1.0, 0.91, 0.57);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float radius = length(p);
	float lobes = 0.64 + 0.19 * sin(a * 5.0 + phase) + 0.12 * sin(a * 9.0 - phase);
	float flame = 1.0 - smoothstep(0.08, lobes, radius);
	if (axial) {
		float along = UV.y;
		float width = (0.06 + 0.38 * pow(along, 0.7)) * (0.8 + 0.2 * sin(along * 28.0 + phase));
		flame = (1.0 - smoothstep(width * 0.3, width, abs(p.x))) * smoothstep(0.0, 0.22, along);
	}
	vec3 heat = mix(edge_color, core_color, pow(flame, 2.0));
	ALBEDO = heat * 2.8;
	ALPHA = flame * intensity;
}
