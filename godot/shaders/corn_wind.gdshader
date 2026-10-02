shader_type spatial;
render_mode cull_disabled, vertex_lighting, shadows_disabled, specular_disabled;
uniform bool burn_enabled = false;
uniform sampler2D burn_mask : filter_nearest, repeat_disable;
uniform vec2 burn_origin;
uniform vec2 burn_size = vec2(1.0);
varying float burned;
varying vec4 tint;
void vertex() {
 vec2 plant = MODEL_MATRIX[3].xz;
 burned = burn_enabled ? texture(burn_mask, (plant-burn_origin)/burn_size).r : 0.0;
 VERTEX.y *= mix(1.0,0.14,burned);
 vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 float weight = pow(clamp(VERTEX.y/2.7,0.0,1.0),2.0);
 VERTEX.x += sin(TIME*1.4+world.x*0.4+world.z*0.24)*0.12*weight;
 VERTEX.z += cos(TIME*1.1+world.z*0.3)*0.06*weight;
 tint = COLOR;
}
void fragment() {
 // Fade subpixel veins instead of letting their stripes sparkle in the wind.
 float detail = 1.0-smoothstep(0.3,1.0,fwidth(UV.y)*80.0+fwidth(UV.x)*12.0);
 float veins = 0.975 + sin(UV.y*160.0 + sin(UV.x*23.0)*0.5)*0.025*detail;
 float rib = 1.0 + 0.12*exp(-abs(UV.y-0.5)*90.0)*detail;
 ALBEDO=mix(pow(tint.rgb,vec3(2.2)),vec3(0.035,0.025,0.018),burned)*mix(1.0,veins*rib,UV2.x); ROUGHNESS=0.95; }
