// FLUX DROP breakable glass, light variant for Low and Medium: the same block,
// tint and transparency as glass.gdshader, with an analytic impact fracture
// (five irregular rays from one point and broken ring arcs) instead of a
// Voronoi search. No hash and no cell loop: a handful of ALU per fragment.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/glass_common.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.56, 1.0);
uniform float base_alpha = 0.42;

// Impact point and ring radius in fracture units (object xy x 3.2, as glass.gdshader).
const vec2 IMPACT = vec2(0.3, -0.2);
const float RING = 1.1;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

// Distance to a ray leaving the impact point at [param angle] (far behind it).
float ray(vec2 q, float angle) {
	vec2 d = vec2(cos(angle), sin(angle));
	return dot(q, d) > 0.0 ? abs(q.x * d.y - q.y * d.x) : 1.0;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec2 q = obj_pos.xy * 3.2 + obj_pos.z * 1.7 - IMPACT;
	float rays = min(min(ray(q, 0.35), ray(q, 1.55)), min(min(ray(q, 2.7), ray(q, 3.95)), ray(q, 5.1)));
	// The ring breaks into arcs between the rays.
	float arcs = step(0.2, sin(atan(q.y, q.x) * 3.0 + 1.0));
	float ring = mix(1.0, abs(length(q) - RING), arcs);
	float edge = min(rays, ring);
	float crack = 1.0 - smoothstep(0.02, 0.06, edge);
	ALBEDO = fd_glass_albedo(crack, tint.rgb);
	ROUGHNESS = fd_glass_roughness(crack);
	ALPHA = fd_glass_alpha(crack, fres, base_alpha);
	METALLIC = 0.0;
	SPECULAR = 0.75;
}
