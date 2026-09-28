shader_type spatial;
render_mode cull_disabled;
uniform sampler2D cover_map : filter_linear;
uniform sampler2D crop_map : filter_linear;
uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 origin;
uniform vec2 size;
varying vec2 world;
global uniform float remz_wetness;
void vertex() { world = VERTEX.xz; }
void fragment() {
 vec2 uv = (world-origin+vec2(0.25))/size;
 vec3 cover = texture(cover_map,uv).rgb;
 vec3 crop = texture(crop_map,uv).rgb;
 // Hoist gradients out of the mask branches: neighbouring pixels at a path
 // edge must retain the same mip/anisotropic filtering as the full shader.
 vec2 dx = dFdx(world);
 vec2 dy = dFdy(world);
 // Most pixels use just one layer. Keep the exact mask blends at borders,
 // but avoid fetching gravel, litter and soil over an ordinary meadow.
 vec3 earth = vec3(0.0);
 if (crop.r > 0.0 || crop.g > 0.0 || cover.r > 0.0 || crop.b > 0.0) {
  earth = textureGrad(soil,world*0.32,dx*0.32,dy*0.32).rgb;
 }
 vec3 grass = vec3(0.0);
 if (cover.r < 1.0 && cover.b < 1.0 && crop.b < 1.0) {
  if (crop.g < 1.0) {
   grass = textureGrad(meadow,world*0.36,dx*0.36,dy*0.36).rgb * vec3(0.75,0.86,0.57);
   grass = mix(grass,earth*vec3(0.64,0.7,0.33),crop.r*0.86);
  }
  float stripes = 0.95+0.05*sin(world.x*7.7+world.y*2.2);
  grass = mix(grass,vec3(0.43,0.30,0.12)*stripes+earth*0.16,crop.g);
 }
 vec3 woodland = vec3(0.0);
 if (cover.r > 0.0 && cover.b < 1.0 && crop.b < 1.0) {
  vec3 leaves = textureGrad(litter,world*0.45,dx*0.45,dy*0.45).rgb;
  woodland = mix(earth*vec3(0.20,0.13,0.07),leaves*vec3(0.32,0.26,0.16),0.6);
 }
 vec3 stones = vec3(0.0);
 vec3 stone_normal = vec3(0.5,0.5,1.0);
 if (cover.b > 0.0) {
  stones = textureGrad(gravel,world*0.55,dx*0.55,dy*0.55).rgb * vec3(1.0,0.95,0.84);
  stone_normal = textureGrad(gravel_normal,world*0.55,dx*0.55,dy*0.55).rgb;
 }
 ALBEDO = mix(grass,woodland,cover.r);
 ALBEDO = mix(ALBEDO,stones,cover.b);
 ALBEDO = mix(ALBEDO,vec3(0.17,0.18,0.17)*(0.8+earth.r),crop.b);
 ALBEDO *= mix(1.0,0.65,remz_wetness);
 NORMAL_MAP = mix(vec3(0.5,0.5,1.0),stone_normal,cover.b*0.55);
 ROUGHNESS = 0.94;
 SPECULAR = 0.15;
}
