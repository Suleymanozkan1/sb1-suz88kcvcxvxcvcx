// FLUX DROP hazard material: bright edges + per-world surface style.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.08, 0.04, 0.12, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.3, 0.42, 1.0);
uniform vec3 half_extents = vec3(0.58, 0.45, 0.22);
uniform float edge_width = 0.07;
uniform float emission_strength = 2.4;
instance uniform float warn = 0.0;
instance uniform float fade = 0.0;
instance uniform float flash = 0.0;
uniform int style = 0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.35;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.1;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	if (fade > 0.0) {
		// Ordered dither keeps the opaque pipeline (no sorting) while fading.
		float dither = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + 0.125 * mod(floor(FRAGCOORD.y), 2.0));
		if (dither < fade) {
			discard;
		}
	}
	vec3 q = abs(obj_pos) / half_extents;
	// Edges are where two axes are both close to the box surface.
	float e = 0.0;
	e = max(e, step(1.0 - edge_width / min(half_extents.x, half_extents.y), min(q.x, q.y)));
	e = max(e, step(1.0 - edge_width / min(half_extents.x, half_extents.z), min(q.x, q.z)));
	e = max(e, step(1.0 - edge_width / min(half_extents.y, half_extents.z), min(q.y, q.z)));
	vec3 surface = base_color.rgb;
	float glow = 0.0;
	vec3 p = obj_pos * 3.0 + vec3(0.0, 0.0, TIME * 0.1);
	if (style == 1) { // crystal
		surface += edge_color.rgb * 0.25 * smoothstep(0.3, 0.0, fd_cells(p * 1.5));
	} else if (style == 2) { // magma
		glow = 1.0 - smoothstep(0.0, 0.1, fd_cells(p * 1.6 + vec3(0.0, TIME * 0.3, 0.0)));
	} else if (style == 3) { // porcelain
		surface = mix(vec3(0.92, 0.94, 1.0), base_color.rgb, 0.25);
		glow = step(0.85, fract(obj_pos.y * 3.0)) * 0.5;
	} else if (style == 4) { // coral
		surface += edge_color.rgb * 0.18 * fd_fbm(p * 2.0);
	} else if (style == 5) { // circuit
		vec2 g = abs(fract(obj_pos.xy * 6.0) - 0.5);
		glow = step(0.46, max(g.x, g.y)) * 0.6;
	} else if (style == 6) { // ice
		surface = mix(surface, vec3(0.75, 0.9, 1.0), 0.35 * fd_fbm(p * 2.5));
	} else if (style == 7) { // sandstone
		surface = mix(surface, edge_color.rgb * 0.35, step(0.5, fract(obj_pos.y * 7.0 + fd_noise3(p) * 0.6)) * 0.4);
	} else if (style == 8) { // void
		surface = vec3(0.0);
	} else if (style == 9) { // candy
		surface = mix(vec3(1.0), edge_color.rgb, step(0.5, fract((obj_pos.x + obj_pos.y) * 3.0)));
	}
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = surface;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	float pulse = 0.5 + 0.5 * sin(TIME * 10.0);
	EMISSION = edge_color.rgb * (e * emission_strength + glow * 1.4 + rim * 0.6 + warn * pulse * 0.8) + vec3(flash * 3.0);
}
