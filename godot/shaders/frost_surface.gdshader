shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	vec3 p = local_position * 24.0;
	float cracks = pow(abs(sin(p.x + sin(p.y)) * sin(p.z - p.y * 0.7)), 12.0);
	ALBEDO = mix(vec3(0.18, 0.5, 0.75), vec3(0.8, 0.95, 1.0), rim + cracks);
	ALPHA = 0.22 + rim * 0.38 + cracks * 0.25;
}
