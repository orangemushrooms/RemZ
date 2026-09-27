shader_type canvas_item;
render_mode unshaded;
uniform float clock = 0.0;
uniform float strength = 0.26;
uniform sampler2D mist_texture : filter_linear, repeat_enable;
void fragment() {
	vec2 drift = vec2(clock * 0.018, -clock * 0.009);
	vec2 p = UV * vec2(1.8, 1.2);
	// Broad banks drift across finer counter-moving wisps; a slow flow field curls their edges.
	vec2 flow = vec2(texture(mist_texture, p * 0.65 + drift * 0.4).r,
		texture(mist_texture, p * 0.65 - drift * 0.3 + vec2(0.43, 0.71)).r) - 0.5;
	float bank = texture(mist_texture, p + drift + flow * 0.12).r;
	float wisp = texture(mist_texture, p * 2.3 - drift * 1.35 + flow * 0.18).r;
	float mist = bank * 0.64 + wisp * 0.36;
	float banks = smoothstep(0.29, 0.78, mist);
	COLOR = vec4(vec3(0.68, 0.74, 0.71), banks * strength);
}
