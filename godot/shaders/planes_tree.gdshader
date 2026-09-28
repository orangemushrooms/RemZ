shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool vertex_colour = false;
uniform float base;
uniform float height;
varying float crown;
varying vec3 local_pos;
global uniform float remz_wetness;
void vertex() {
 crown = smoothstep(0.28,0.5,(VERTEX.y-base)/height);
 local_pos = VERTEX / height;
}
void fragment() {
 vec4 c = vertex_colour ? vec4(pow(COLOR.rgb,vec3(2.2)),1.0) : texture(albedo,UV);
 float leaf = smoothstep(0.018,0.085,c.r-c.b)*crown;
 float value = dot(c.rgb,vec3(0.45,0.4,0.15));
 vec3 wood = texture(bark,vec2(local_pos.x+local_pos.z,local_pos.y)*vec2(14.0,5.0)).rgb*vec3(0.43,0.39,0.32);
 vec3 foliage = vec3(0.19,0.36,0.07)*value*1.2;
 ALBEDO = mix(mix(wood,c.rgb*0.65,crown),foliage,leaf)*mix(1.0,0.65,remz_wetness);
 BACKLIGHT = foliage*leaf*0.15;
 ROUGHNESS = 1.0;
 SPECULAR = 0.08;
}
