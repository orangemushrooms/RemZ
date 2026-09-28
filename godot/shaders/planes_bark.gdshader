shader_type spatial;
uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float height;
varying vec3 local_pos;
global uniform float remz_wetness;
void vertex() { local_pos = VERTEX / height; }
void fragment() {
 vec2 uv = vec2(local_pos.x+local_pos.z,local_pos.y)*vec2(18.0,5.0);
 ALBEDO = texture(bark,uv).rgb*vec3(0.46,0.43,0.35)*mix(1.0,0.65,remz_wetness);
 ROUGHNESS = 0.95;
 SPECULAR = 0.05;
}
