shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_enable;

uniform float effect_brightness = 1.0;

void fragment() {
	// Source additive materials use ONE/ONE: texture alpha must not dim RGB again.
	ALBEDO = texture(atlas, UV).rgb * COLOR.rgb * effect_brightness;
	ALPHA = 1.0;
}
