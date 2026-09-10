shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool opaque = false;

void vertex() {
	// Keep source angular geometry and camera rotation, but remove translation.
	vec3 direction = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * VERTEX;
	POSITION = PROJECTION_MATRIX * vec4(direction, 1.0);
	POSITION.z = CLIP_SPACE_FAR * POSITION.w;
}

void fragment() {
	vec4 color = texture(atlas, UV) * tint;
	ALBEDO = color.rgb;
	ALPHA = opaque ? 1.0 : color.a;
}
