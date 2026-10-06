// FLUX DROP energy trail ribbon. `style` selects the cosmetic trail look.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 head_color : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.24, 0.8, 1.0);
uniform float intensity = 1.6;
uniform int style = 0;
// 1 while the trail carries the form colour (PHASE/DASH/SURGE): colour-overriding
// styles give way to it.
uniform float form_lock = 0.0;

void fragment() {
	// UV.x: 0 at head, 1 at tail. UV.y: across the ribbon.
	float along = UV.x;
	float across = abs(UV.y - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 1.0, across);
	float fade = pow(1.0 - along, 2.2);
	float m = 1.0;
	vec3 col = mix(head_color.rgb, tail_color.rgb, along);
	if (style == 1) { // pulses
		m = 0.4 + 0.6 * step(0.5, fract(along * 8.0 - TIME * 4.0));
	} else if (style == 2) { // sparkle
		m = 0.5 + 1.5 * step(0.93, fd_hash13(vec3(floor(UV * vec2(40.0, 6.0)), floor(TIME * 12.0))));
	} else if (style == 3) { // flame
		m = 0.6 + 0.8 * fd_fbm(vec3(along * 6.0 - TIME * 5.0, UV.y * 3.0, 0.0));
	} else if (style == 4) { // rainbow
		vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (along + TIME * 0.5 + vec3(0.0, 0.33, 0.67)));
		col = mix(rainbow, col, form_lock);
	} else if (style == 5) { // helix
		float h = abs(sin(along * 18.0 - TIME * 8.0) * 0.5 + 0.5 - UV.y);
		core = 1.0 - smoothstep(0.0, 0.18, h);
	} else if (style == 6) { // digital
		m = step(0.35, fd_hash13(vec3(floor(along * 30.0), floor(UV.y * 4.0), floor(TIME * 10.0))));
	} else if (style == 7) { // ghost
		m = 0.35;
	} else if (style == 8) { // comet: a hot head that tapers to a thin tail
		core = 1.0 - smoothstep(0.0, mix(1.0, 0.25, along), across);
		m = 1.0 + 2.0 * (1.0 - smoothstep(0.0, 0.12, along));
	} else if (style == 9) { // neon dashes: separate bars streaming back
		m = step(0.45, fract(along * 12.0 - TIME * 6.0)) * (1.0 - smoothstep(0.6, 0.9, across));
	} else if (style == 10) { // starlight: scattered points that twinkle
		vec2 cell = floor(UV * vec2(24.0, 5.0));
		float star = step(0.88, fd_hash13(vec3(cell, 1.0)));
		m = 0.25 + star * 2.0 * (0.5 + 0.5 * sin(TIME * 7.0 + fd_hash13(vec3(cell, 4.0)) * 6.2831));
	} else if (style == 11) { // inferno: embers drift off the edges
		float ember = step(0.9, fd_hash13(vec3(floor(along * 30.0 - TIME * 8.0), floor(UV.y * 6.0), 2.0)));
		m = 0.7 + 0.5 * fd_fbm(vec3(along * 5.0 - TIME * 4.0, UV.y * 2.0, 1.0)) + ember * 1.5;
		core = max(core, ember * (1.0 - along));
	}
	ALBEDO = col * core * fade * m * intensity * COLOR.a;
}
