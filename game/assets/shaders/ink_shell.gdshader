// FLUX DROP ink shell: inverted-hull outline that gives the energy core value
// contrast in high-key worlds (docs/ART_DIRECTION.md §5, player priority #1).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.043, 0.055, 0.078, 1.0);
uniform float thickness = 0.022;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = ink.rgb;
}
