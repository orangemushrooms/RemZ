shader_type spatial;
render_mode cull_disabled;
uniform sampler2D cover_map : filter_linear;
uniform sampler2D crop_map : filter_linear;
uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 origin;
uniform vec2 size;
varying vec2 world;
void vertex() { world = VERTEX.xz; }
void fragment() {
 vec2 uv = (world-origin+vec2(0.25))/size;
 vec3 cover = texture(cover_map,uv).rgb;
 vec3 crop = texture(crop_map,uv).rgb;
 vec3 grass = texture(meadow,world*0.36).rgb * vec3(0.75,0.86,0.57);
 vec3 earth = texture(soil,world*0.32).rgb;
 vec3 stones = texture(gravel,world*0.55).rgb * vec3(1.0,0.95,0.84);
 float stripes = 0.95+0.05*sin(world.x*7.7+world.y*2.2);
 grass = mix(grass,earth*vec3(0.64,0.7,0.33),crop.r*0.86);
 grass = mix(grass,vec3(0.43,0.30,0.12)*stripes+earth*0.16,crop.g);
 ALBEDO = mix(grass,earth*0.65,cover.r);
 ALBEDO = mix(ALBEDO,stones,cover.b);
 ALBEDO = mix(ALBEDO,vec3(0.17,0.18,0.17)*(0.8+earth.r),crop.b);
 NORMAL_MAP = mix(vec3(0.5,0.5,1.0),texture(gravel_normal,world*0.55).rgb,cover.b*0.55);
 ROUGHNESS = 0.94;
 SPECULAR = 0.15;
}
