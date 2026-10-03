// FLUX DROP portal / form gate surface: swirling energy membrane.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.24, 0.8, 1.0);
uniform float intensity = 1.4;
uniform float swirl = 1.0;
uniform float opacity = 1.0;

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float a = atan(c.y, c.x);
	float s = fd_fbm(vec3(a * 1.5 + r * 3.0 - TIME * swirl * 2.0, r * 2.0, TIME * 0.3));
	float ring = smoothstep(1.0, 0.85, r) * (0.35 + 0.65 * smoothstep(0.55, 1.0, r));
	vec3 col = mix(color_a.rgb, color_b.rgb, s);
	ALBEDO = col * ring * intensity * opacity * (0.6 + s);
}
