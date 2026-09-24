shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 ink : source_color = vec4(0.08,0.7,0.65,1.0);
void fragment() {
    vec2 p = (UV - vec2(0.5)) * vec2(1.5,1.0);
    float radius = length(p);
    float rings = pow(0.5 + 0.5 * cos(radius * 65.0), 30.0) * step(radius,0.46);
    float angle = atan(p.y,p.x);
    float scan = pow(max(0.0,cos(angle-TIME*1.6)),24.0) * step(radius,0.46);
    float grid = max(step(fract(UV.x*12.0),0.025),step(fract(UV.y*8.0),0.025));
    float blip = exp(-length(p-vec2(0.19,-0.17))*140.0) + exp(-length(p-vec2(-0.23,0.09))*140.0);
    ALBEDO = vec3(0.006,0.018,0.022) + ink.rgb * (rings*0.22+scan*0.24+grid*0.09+blip*0.9);
    EMISSION = ALBEDO*0.45;
}
