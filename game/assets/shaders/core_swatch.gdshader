// FLUX DROP shop swatch for a core skin: the skin's real animated style
// (core_styles.gdshaderinc, the same code the run uses) on a sphere-shaded
// disc, so every skin is seen as it is before it is bought.
shader_type canvas_item;

#include "res://assets/shaders/noise.gdshaderinc"
#include "res://assets/shaders/core_styles.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.24, 0.8, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int style = 0;
uniform float anim_speed = 1.0;
// 1 owned, lower for items still to buy (the grid's dim rule).
uniform float dim = 1.0;
// Disc radius as a share of the rect's half size.
uniform float radius = 0.6;

// SimConst.CORE_RADIUS: the styles are tuned in the core's object units.
const float CORE_RADIUS = 0.3;
// Rim light share of the run's rim_strength (the UI has no bloom).
const float SWATCH_RIM = 0.9;
// Soft shoulder that maps the core's HDR energy into the UI's range.
const float SHOULDER = 0.35;

void fragment() {
	vec2 q = (UV - 0.5) * 2.0 / radius;
	float r = length(q);
	float edge = 1.0 - smoothstep(1.0 - fwidth(r) * 1.5, 1.0, r);
	if (edge <= 0.0) {
		discard;
	}
	vec3 n = vec3(q.x, -q.y, sqrt(max(1.0 - r * r, 0.0)));
	float ndv = n.z;
	vec3 col = fd_core_style(style, n * CORE_RADIUS, ndv, TIME * anim_speed, color_a.rgb, color_b.rgb, rim_color.rgb, 0.0);
	col += rim_color.rgb * pow(1.0 - ndv, 2.4) * SWATCH_RIM;
	col = col / (1.0 + col * SHOULDER);
	COLOR = vec4(col, edge * dim);
}
