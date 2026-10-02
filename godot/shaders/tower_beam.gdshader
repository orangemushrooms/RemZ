// The searchlight's visible beam (2 Oct 2026): a soft additive cone that fades along its length and
// towards its rim, so the lamp reads as a shaft of light in the forest haze without lighting anything itself.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform float strength = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.93, 0.74);
varying float along;
void vertex() {
	// CylinderMesh UV.y runs from the top cap (the lamp, after the -90 degree turn) to the bottom (the far end)
	along = UV.y;
}
void fragment() {
	float rim = 1.0 - smoothstep(0.55, 1.0, abs(UV.x * 2.0 - 1.0));
	float fade = pow(1.0 - along, 1.6);
	float near = smoothstep(0.0, 0.04, along);
	ALBEDO = tint;
	ALPHA = clamp(fade * near * 0.055 * strength, 0.0, 0.25) * (0.35 + 0.65 * rim);
}
