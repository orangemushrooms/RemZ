shader_type canvas_item;
render_mode unshaded;
uniform float clock = 0.0;
uniform float strength = 0.22;
uniform sampler2D mist_texture : filter_linear, repeat_enable;
void fragment() {
	vec2 p = UV * vec2(1.8, 1.2) + vec2(clock * 0.007, -clock * 0.004);
	float mist = texture(mist_texture, p).r * 0.7 + texture(mist_texture, p * 1.7 + vec2(-clock * 0.011, 0.3)).r * 0.3;
	float banks = smoothstep(0.32, 0.82, mist);
	COLOR = vec4(vec3(0.68, 0.74, 0.71), banks * strength);
}
