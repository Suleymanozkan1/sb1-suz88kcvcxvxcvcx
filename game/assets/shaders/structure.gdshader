// FLUX DROP structure material (ribs, arches, posts, pads): matter, lit PBR,
// never emissive (ART_DIRECTION §5). Surface detail comes from a procedural
// height field per material kind, turned into a normal with screen-space
// derivatives (no textures, no tangents). Low quality switches it off.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.2, 0.22, 0.26, 1.0);
uniform float roughness = 0.5;
uniform float metallic = 0.5;
uniform float specular = 0.5;
uniform float clearcoat = 0.0;
// 0 anodised, 1 steel, 2 stone, 3 ceramic, 4 coated, 5 ice, 6 sandstone,
// 7 obsidian, 8 lacquer, 9 crystal.
uniform int detail_kind = 0;
// 0 disables the detail entirely (Low quality preset).
uniform float detail_strength = 1.0;
// Height of the relief in world units (a few millimetres on a 3.8 u rib).
uniform float bump_depth = 0.01;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// fd_cells searches neighbours in x and y only, so faces running along z
// showed straight seams. Structure relief uses 2D cells on a projection that
// folds z into the plane instead: continuous on every face.
vec2 fold(vec3 p) {
	return vec2(p.x + p.z * 0.83, p.y - p.z * 0.57);
}

// x: distance to the nearest cell point (facets); y: distance to the cell
// edge (F2 - F1, crack lines).
vec2 cells2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = vec2(fd_hash13(vec3(i + o, 0.0)), fd_hash13(vec3(i + o, 17.0)));
			float d = length(o + h - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d1, d2 - d1);
}

float height(vec3 p) {
	if (detail_kind == 0) { // anodised: fine brushed streaks
		return fd_noise3(p * vec3(2.0, 90.0, 2.0)) * 0.6;
	} else if (detail_kind == 1) { // steel: coarser brushing with faint dents
		return fd_noise3(p * vec3(2.0, 45.0, 2.0)) * 0.5 + fd_noise3(p * 3.0) * 0.4;
	} else if (detail_kind == 2) { // stone: rough grain
		return fd_fbm(p * 7.0);
	} else if (detail_kind == 3) { // ceramic: glaze crackle (thin crack lines)
		return 0.5 * smoothstep(0.0, 0.05, cells2(fold(p) * 4.5).y);
	} else if (detail_kind == 4) { // coated: fine orange peel
		return fd_noise3(p * 34.0) * 0.4;
	} else if (detail_kind == 5) { // ice: frozen facets
		return cells2(fold(p) * 3.2).x * 0.8;
	} else if (detail_kind == 6) { // sandstone: grain over wind strata
		return fd_noise3(p * 40.0) * 0.35 + sin(p.y * 22.0 + fd_noise3(p * 2.0) * 3.0) * 0.25;
	} else if (detail_kind == 7) { // obsidian: conchoidal ripples
		return sin(length(p.xz) * 9.0 + fd_noise3(p * 2.5) * 5.0) * 0.35;
	} else if (detail_kind == 9) { // crystal: sharp facets
		return cells2(fold(p) * 5.0).x;
	}
	return 0.0; // lacquer: mirror smooth
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	if (clearcoat > 0.0) {
		CLEARCOAT = clearcoat;
		CLEARCOAT_ROUGHNESS = 0.15;
	}
	if (detail_strength > 0.0 && detail_kind != 8) {
		// Bump mapping from derivatives (Mikkelsen 2010): no tangent space needed.
		float h = height(world_pos) * bump_depth * detail_strength;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 n = normalize(NORMAL);
		vec3 r1 = cross(dpdy, n);
		vec3 r2 = cross(n, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * n - grad);
	}
}
