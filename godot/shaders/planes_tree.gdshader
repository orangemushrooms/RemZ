shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo : source_color, filter_linear_mipmap_anisotropic;
uniform float base;
uniform float height;
varying float crown;
void vertex() {
 crown = smoothstep(0.28,0.5,(VERTEX.y-base)/height);
}
void fragment() {
 vec4 c = texture(albedo,UV);
 float leaf = smoothstep(0.025,0.10,c.r-c.b);
 float value = dot(c.rgb,vec3(0.45,0.4,0.15));
 ALBEDO = mix(c.rgb,vec3(0.25,0.42,0.11)*value*1.25,leaf);
 ROUGHNESS = 1.0;
 SPECULAR = 0.08;
}
