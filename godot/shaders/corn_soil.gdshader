shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 field_size = vec2(140.0,52.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec2 uv=UV;
	vec3 soil=texture(albedo_tex,uv).rgb;
	// Broad variations break tiling; the original PBR set supplies stones, leaves and soil relief.
	float patch=noise(UV2*0.17);
	float compact=smoothstep(0.25,0.85,COLOR.r);
	float furrow=0.5+0.5*sin(UV2.y*18.85+noise(UV2*0.5)*0.3);
	vec3 fine=texture(albedo_tex,uv*2.37+vec2(0.31,0.57)).rgb;
	ALBEDO=mix(soil,soil*0.72+fine*0.28,compact)*mix(0.78,1.08,patch)*mix(0.88+furrow*0.12,1.07,compact);
	NORMAL_MAP=texture(normal_tex,uv).rgb;
	NORMAL_MAP_DEPTH=mix(0.85,0.48,compact);
	ROUGHNESS=clamp(texture(rough_tex,uv).r*mix(0.98,0.91,compact),0.75,1.0);
	AO=texture(ao_tex,uv).r;
	float edge=min(min(UV2.x,UV2.y),min(field_size.x-UV2.x,field_size.y-UV2.y));
	ALPHA=smoothstep(0.0,0.85,edge-noise(UV2*3.0)*0.23);
}
