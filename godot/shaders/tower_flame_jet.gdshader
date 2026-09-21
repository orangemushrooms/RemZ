shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float jet_length = 14.0;
uniform float strength = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
void vertex() {
	float t = UV.y;
	VERTEX.xy *= 0.065 + pow(t, 0.85) * jet_length * 0.14;
	VERTEX.z *= jet_length;
	VERTEX.x += sin(t*18.0-TIME*8.0)*t*0.13;
	VERTEX.y += t*t*0.45 + sin(t*14.0-TIME*11.0)*t*0.09;
}
void fragment() {
	float t = UV.y;
	vec2 flow = vec2(t*16.0-TIME*10.0, UV.x*4.0);
	float n = noise(flow)*0.65 + noise(flow*2.17)*0.25 + noise(flow*4.31)*0.1;
	float curl = (noise(vec2(t*8.0-TIME*5.0, 3.7))-0.5)*0.6;
	float edge = 1.0-smoothstep(0.15, 1.0, abs(UV.x*2.0-1.0+curl));
	float tail = 1.0-smoothstep(0.65, 1.0, t + (n-0.5)*0.22);
	float mask = edge * smoothstep(0.18, 0.65, n) * tail * smoothstep(0.0, 0.025, t);
	float core = edge * (1.0-t) * (0.5+n*0.5);
	vec3 fire = mix(vec3(0.8, 0.055, 0.008), vec3(1.0, 0.53, 0.065), n);
	fire = mix(fire, vec3(1.0, 0.91, 0.57), smoothstep(0.35, 0.85, core));
	ALBEDO = fire;
	EMISSION = fire * 2.4;
	ALPHA = mask * strength * 0.8;
}
