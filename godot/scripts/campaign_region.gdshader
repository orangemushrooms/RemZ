shader_type canvas_item;
render_mode unshaded;
uniform float saturation = 1.0;
uniform float brightness = 1.0;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float grey = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), tex.rgb, saturation) * brightness, tex.a);
}
