shader_type spatial;
render_mode cull_disabled;
uniform bool wood = false;
varying vec3 local;
void vertex(){ local=VERTEX; }
void fragment(){
 float grain=sin(local.x*1700.0+local.z*520.0+sin(local.y*25.0)*2.0);
 float fine=fract(sin(dot(local,vec3(913.1,721.7,631.4)))*43758.5453);
 if(wood){
  ALBEDO=mix(vec3(0.19,0.085,0.028),vec3(0.43,0.25,0.10),0.55+grain*0.17+fine*0.09);
  ROUGHNESS=0.7; METALLIC=0.0;
 } else {
  ALBEDO=mix(vec3(0.19,0.22,0.23),vec3(0.32,0.35,0.36),fine*0.6);
  ROUGHNESS=0.48+fine*0.15; METALLIC=0.5;
 }
}
