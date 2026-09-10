shader_type sky;
uniform sampler2D nebula : source_color, filter_linear;
uniform bool has_nebula = false;
float hash(vec3 p) { p=fract(p*.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z); }
void sky() {
 vec3 d=normalize(EYEDIR);
 vec2 uv=vec2(atan(d.x,d.z)/6.2831853+.5,asin(d.y)/3.14159265+.5);
 vec3 base=vec3(.003,.008,.018);
 if(has_nebula) {
  // The lower-right quadrant is nebula art; the lower-left holds UI sprites.
  vec3 n=texture(nebula,vec2(.5)+uv*.499).rgb;
  base+=n*vec3(.32,.42,.55);
 }
 vec3 cell=floor(d*630.0);
 float star=step(.9985,hash(cell))*pow(max(0.0,1.0-length(fract(d*630.0)-.5)*1.6),4.0);
 COLOR=base+vec3(.68,.8,1.0)*star*2.0;
}
