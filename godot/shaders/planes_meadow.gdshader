shader_type spatial;
render_mode cull_disabled;

// Reuse Forest's grass atlas, repeating within each cell only after UV interpolation.
// Repeating in vertex() collapses both card edges onto the same transparent texel.
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 cells = vec2(4.0, 1.0);
uniform float wind = 1.0;
uniform bool meadow_distance_thinning = true;
uniform vec3 tint : source_color = vec3(0.55, 0.72, 0.37);
global uniform float remz_wetness;
varying float bright;
varying flat float cell;

void vertex() {
	cell = INSTANCE_CUSTOM.x;
	bright = INSTANCE_CUSTOM.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = INSTANCE_CUSTOM.z * wind * (1.0 - UV.y);
	float t = TIME * 1.6 + wp.x * 0.35 + wp.z * 0.27;
	VERTEX.x += sin(t) * sway * 0.12;
	VERTEX.z += cos(t * 0.8) * sway * 0.08;
	if (meadow_distance_thinning) {
		float distance_to_camera = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
		// Each distant card carries twice the original blade count. Fewer
		// subpixel tufts preserve coverage while paying for the denser foreground.
		float keep = mix(1.0, 0.14, smoothstep(10.0, 45.0, distance_to_camera));
		VERTEX *= smoothstep(INSTANCE_CUSTOM.w - 0.055, INSTANCE_CUSTOM.w + 0.055, keep);
	}
}

void fragment() {
	vec2 atlas_uv = (vec2(fract(UV.x * 2.0), UV.y) + vec2(mod(cell, cells.x), floor(cell / cells.x))) / cells;
	// Derivatives come from the continuous UVs, so repeating a cell cannot select
	// an excessively blurry mip at its seam.
	vec2 atlas_scale = vec2(2.0, 1.0) / cells;
	vec4 sample_color = textureGrad(atlas, atlas_uv, dFdx(UV) * atlas_scale, dFdy(UV) * atlas_scale);
	ALBEDO = sample_color.rgb * tint * bright * mix(1.0, 0.55, UV.y);
	ALPHA = sample_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	// Tufts represent upright blades, including on their back faces. A shared
	// upward lighting normal avoids black triangular backs on crossed cards.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float wet = clamp(remz_wetness, 0.0, 1.0);
	ALBEDO *= mix(1.0, 0.62, wet);
	ROUGHNESS = mix(0.94, 0.86, wet);
	SPECULAR = mix(0.04, 0.06, wet);
}
