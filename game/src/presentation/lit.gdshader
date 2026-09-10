shader_type spatial;
render_mode unshaded, cull_back;

// Sample the original display-color texture before legacy lighting modulation.
uniform sampler2D atlas : filter_linear_mipmap, repeat_enable;
uniform vec3 light_direction = vec3(0.0, 0.0, 1.0);
uniform vec3 light_ambient = vec3(0.0);
uniform vec3 light_diffuse = vec3(0.0);
varying vec3 vertex_light;

void vertex() {
	// CUSTOM0 keeps the source short-normal conversion, including non-unit length.
	// An explicit inverse transpose also preserves the effect of object scaling.
	vec3 normal_world = transpose(inverse(mat3(MODEL_MATRIX))) * CUSTOM0.xyz;
	vertex_light = clamp(light_ambient + light_diffuse * max(dot(normal_world, light_direction), 0.0), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec3 display_color = texture(atlas, UV).rgb * vertex_light;
	// Compatibility writes display color directly. Linear renderers need conversion.
	ALBEDO = OUTPUT_IS_SRGB ? display_color : mix(display_color / 12.92, pow((display_color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), display_color));
}
