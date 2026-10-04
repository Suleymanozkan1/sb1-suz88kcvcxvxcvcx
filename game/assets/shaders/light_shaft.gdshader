// FLUX DROP light shaft: a faint additive beam of the world's key light far
// ahead in the shaft (volumetric look without volumetric fog). Atmosphere stays
// under 8 % opacity (ART_DIRECTION §7) and never crosses the lanes' readability.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 shaft_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float opacity = 0.06;
instance uniform float seed = 0.0;

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.15, 1.0, across);
	// Brightest near the top (the light source), fading out towards the floor.
	float along = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.45, 1.0, UV.y));
	float drift = 0.75 + 0.25 * sin(TIME * 0.35 + seed * 6.2831 + UV.x * 2.0);
	ALBEDO = shaft_color.rgb * edge * along * drift * opacity;
}
