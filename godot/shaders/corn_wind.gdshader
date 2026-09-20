shader_type spatial;
render_mode cull_disabled, vertex_lighting, shadows_disabled, specular_disabled;
varying vec4 tint;
void vertex() {
 vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 float weight = pow(clamp(VERTEX.y/2.7,0.0,1.0),2.0);
 VERTEX.x += sin(TIME*1.4+world.x*0.4+world.z*0.24)*0.12*weight;
 VERTEX.z += cos(TIME*1.1+world.z*0.3)*0.06*weight;
 tint = COLOR;
}
void fragment() { ALBEDO=pow(tint.rgb,vec3(2.2)); ROUGHNESS=0.95; }
