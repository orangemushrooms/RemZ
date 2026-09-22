shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// A warm sheen around the visible silhouette. Depth testing keeps the rare
// mushroom hidden behind trees/terrain; no lights or CPU animation are needed.
void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.6);
	float shimmer = 0.85 + 0.15 * sin(TIME * 1.7 + VERTEX.y * 3.0);
	ALBEDO = vec3(0.0);
	EMISSION = vec3(1.0, 0.56, 0.075) * (0.045 + rim * 0.9) * shimmer;
	ALPHA = 1.0;
}
