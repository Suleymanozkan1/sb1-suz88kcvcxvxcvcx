// FLUX DROP energy trail ribbon. `style` selects the cosmetic trail look.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 head_color : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.24, 0.8, 1.0);
uniform float intensity = 1.6;
uniform int style = 0;

void fragment() {
	// UV.x: 0 at head, 1 at tail. UV.y: across the ribbon.
	float along = UV.x;
	float across = abs(UV.y - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 1.0, across);
	float fade = 1.0 - along;
	float m = 1.0;
	vec3 col = mix(head_color.rgb, tail_color.rgb, along);
	if (style == 1) { // pulses
		m = 0.4 + 0.6 * step(0.5, fract(along * 8.0 - TIME * 4.0));
	} else if (style == 2) { // sparkle
		m = 0.5 + 1.5 * step(0.93, fd_hash13(vec3(floor(UV * vec2(40.0, 6.0)), floor(TIME * 12.0))));
	} else if (style == 3) { // flame
		m = 0.6 + 0.8 * fd_fbm(vec3(along * 6.0 - TIME * 5.0, UV.y * 3.0, 0.0));
	} else if (style == 4) { // rainbow
		col = 0.5 + 0.5 * cos(6.2831 * (along + TIME * 0.5 + vec3(0.0, 0.33, 0.67)));
	} else if (style == 5) { // helix
		float h = abs(sin(along * 18.0 - TIME * 8.0) * 0.5 + 0.5 - UV.y);
		core = 1.0 - smoothstep(0.0, 0.18, h);
	} else if (style == 6) { // digital
		m = step(0.35, fd_hash13(vec3(floor(along * 30.0), floor(UV.y * 4.0), floor(TIME * 10.0))));
	} else if (style == 7) { // ghost
		m = 0.35;
	}
	ALBEDO = col * core * fade * m * intensity * COLOR.a;
}
