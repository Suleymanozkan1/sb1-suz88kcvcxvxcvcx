// FLUX DROP breakable glass: same chamfered block, but transparent with dark
// fracture lines so "destructible" reads differently from a solid barrier.
// Fine Voronoi fractures (a 3x3 cell search per fragment): High and Ultra.
// Low and Medium use glass_lite.gdshader (analytic lines, no loop).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/glass_common.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.56, 1.0);
uniform float base_alpha = 0.42;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

float cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = fract(sin(vec2(dot(i + o, vec2(127.1, 311.7)), dot(i + o, vec2(269.5, 183.3)))) * 43758.5453);
			float d = length(o + h - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	// Fracture lines in world-unit scale (no stretching): darker, slightly opaque.
	float edge = cell_edge(obj_pos.xy * 3.2 + obj_pos.z * 1.7);
	float crack = 1.0 - smoothstep(0.02, 0.06, edge);
	ALBEDO = fd_glass_albedo(crack, tint.rgb);
	ROUGHNESS = fd_glass_roughness(crack);
	ALPHA = fd_glass_alpha(crack, fres, base_alpha);
	METALLIC = 0.0;
	SPECULAR = 0.75;
}
