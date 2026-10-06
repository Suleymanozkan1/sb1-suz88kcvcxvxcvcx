// FLUX DROP energy core. Each `style` is a distinct animated look (skins).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://assets/shaders/noise.gdshaderinc"
#include "res://assets/shaders/core_styles.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.24, 0.8, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 1.6;
uniform float pulse = 0.0;
uniform float anim_speed = 1.0;
uniform int style = 0;
uniform float overdrive = 0.0;
uniform float rim_strength = 1.6;
// 1 while the form colour carries meaning (PHASE/DASH/SURGE): styles that
// would hide color_a give way to it (ART_DIRECTION §2, form colour first).
uniform float form_lock = 0.0;
// Depth: the centre burns hotter than the limb, so the body reads as a ball of
// energy with its skin pattern visible, not a flat overexposed disc.
uniform float depth_shade = 0.3;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.4);
	float t = TIME * anim_speed;
	vec3 col = fd_core_style(style, obj_pos, ndv, t, color_a.rgb, color_b.rgb, rim_color.rgb, form_lock);
	col *= mix(1.0 - depth_shade, 1.0 + depth_shade * 0.5, pow(ndv, 1.6));
	col += rim_color.rgb * fres * rim_strength;
	col = mix(col, vec3(1.0, 0.95, 0.7), overdrive * 0.35 * (0.5 + 0.5 * sin(t * 20.0)));
	ALBEDO = col * (intensity + pulse);
}
