// Deep Ocean backdrop bake: a reef canyon on the sea floor. Sun rays slant
// down from the surface through blue-green water, kelp sways up from rock
// shelves dotted with bioluminescent corals, a natural arch spans the canyon
// far ahead, fish school in the open water and marine snow drifts past.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 9.0, 0.0);
const float FAR = 900.0;
const float KELP_CELL = 9.0;
const vec3 ARCH = vec3(0.0, 0.0, -230.0);

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 sun_dir() {
	return normalize(vec3(0.12, 1.0, -0.35));
}

float meander(float z) {
	return 10.0 * sin(z * 0.012) + 5.0 * sin(z * 0.031 + 2.0);
}

float ground_h(vec2 xz, int octaves) {
	float x = abs(xz.x - meander(xz.y));
	float walls = smoothstep(26.0, 70.0, x) * 46.0 + smoothstep(70.0, 160.0, x) * 40.0;
	float rock = terrain_fbm(xz * 0.03, octaves) * 18.0 * smoothstep(14.0, 50.0, x);
	float ripples = sin(dot(xz, vec2(0.6, 0.3)) + noise2(xz * 0.08) * 4.0) * 0.25;
	return walls + rock + ripples - 1.0;
}

// The arch: a thick bent tube of rock across the canyon.
float arch(vec3 p) {
	vec3 q = p - ARCH;
	float r = length(vec2(q.x, q.y + 8.0)) - 58.0;
	float d = length(vec2(r, q.z)) - 13.0;
	d += (fbm3(p * 0.06, 4) - 0.5) * 9.0;
	return max(d, -q.y - 4.0);
}

// Kelp: tall ribbons rising from the shelves, swaying with height.
float kelp(vec3 p, out float h_frac) {
	vec2 cell = floor(p.xz / KELP_CELL);
	vec2 centre = (cell + 0.5) * KELP_CELL;
	float seed = hash12(cell);
	h_frac = 0.0;
	float x = abs(centre.x - meander(centre.y));
	if (seed < 0.68 || x < 22.0 || x > 120.0 || centre.y > -10.0) {
		return KELP_CELL * 0.45;
	}
	float base = ground_h(centre, 3) - 1.0;
	float h = 10.0 + (seed - 0.68) * 70.0;
	float y = p.y - base;
	vec2 sway = vec2(sin(y * 0.11 + seed * 9.0), cos(y * 0.07 + seed * 4.0)) * y * 0.06;
	vec2 c = centre + (hash22(cell) - 0.5) * KELP_CELL * 0.4 + sway;
	// A flat blade that twists slowly as it rises, widest in the middle.
	float frac_y = clamp(y / h, 0.0, 1.0);
	vec2 local = rot(y * 0.12 + seed * 6.0) * (p.xz - c);
	vec2 rad = vec2(0.25 + 1.1 * sin(frac_y * 3.1416) * smoothstep(0.0, 0.08, frac_y), 0.1);
	float stalk = (length(local / rad) - 1.0) * rad.y;
	h_frac = clamp(y / h, 0.0, 1.0);
	return max(stalk, max(y - h, -y));
}

// .x distance, .y material (0 rock / floor, 1 arch, 2 kelp), .z kelp height.
vec3 map(vec3 p, float t) {
	int oct = t < 120.0 ? 7 : 5;
	float g = (p.y - ground_h(p.xz, oct)) * 0.55;
	vec3 best = vec3(g, 0.0, 0.0);
	float a = arch(p) * 0.7;
	if (a < best.x) {
		best = vec3(a, 1.0, 0.0);
	}
	float hf;
	float k = kelp(p, hf) * 0.8;
	if (k < best.x) {
		best = vec3(k, 2.0, hf);
	}
	return best;
}

vec3 normal_at(vec3 p, float t) {
	float e = 0.02 + t * 0.001;
	vec2 k = vec2(1.0, -1.0);
	return normalize(
		k.xyy * map(p + k.xyy * e, t).x + k.yyx * map(p + k.yyx * e, t).x + k.yxy * map(p + k.yxy * e, t).x
		+ k.xxx * map(p + k.xxx * e, t).x
	);
}

// Caustics: the surface's light net on the floor.
float caustics(vec2 xz) {
	vec2 v1 = voronoi2(xz * 0.22 + vec2(0.0, 1.3));
	vec2 v2 = voronoi2(xz * 0.31 + vec2(4.0, 0.0));
	return pow(smoothstep(0.25, 0.0, v1.y - v1.x), 2.0) * 0.6 + pow(smoothstep(0.2, 0.0, v2.y - v2.x), 2.0) * 0.4;
}

// Light shafts along the view ray: the sun's rays seen through the water.
float shafts(vec3 ro, vec3 rd, float tmax) {
	float acc = 0.0;
	vec3 sd = sun_dir();
	for (int i = 0; i < 40; i++) {
		float t = (float(i) + 0.5) / 40.0 * min(tmax, 420.0);
		vec3 p = ro + rd * t;
		// Project back up to the surface along the sun direction.
		vec3 sp = p + sd * ((120.0 - p.y) / sd.y);
		float beam = smoothstep(0.55, 0.85, noise2(sp.xz * 0.025)) * smoothstep(0.4, 0.75, noise2(sp.xz * 0.06 + 7.0));
		acc += beam * exp(-t * 0.006) * smoothstep(-2.0, 30.0, p.y);
	}
	return acc / 40.0;
}

vec3 water(vec3 rd) {
	vec3 deep = lin(vec3(0.02, 0.07, 0.09));
	vec3 up = lin(vec3(0.12, 0.34, 0.36));
	vec3 col = mix(deep, up, smoothstep(-0.1, 0.9, rd.y));
	// Brighter toward the sun overhead.
	col += lin(vec3(0.3, 0.55, 0.5)) * pow(max(dot(rd, sun_dir()), 0.0), 6.0) * 0.5;
	return col;
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	float t = 0.3;
	vec3 hit = vec3(-1.0);
	for (int i = 0; i < 420; i++) {
		vec3 p = ro + rd * t;
		if (t > FAR || (p.y > 140.0 && rd.y > 0.0)) {
			break;
		}
		vec3 m = map(p, t);
		if (m.x < 0.0012 * t) {
			hit = vec3(t, m.yz);
			break;
		}
		t += max(m.x, 0.0015 * t);
	}
	vec3 sd = sun_dir();
	vec3 col = water(rd);
	float dist = hit.x > 0.0 ? hit.x : FAR;
	if (hit.x > 0.0) {
		vec3 p = ro + rd * hit.x;
		vec3 n = normal_at(p, hit.x);
		float dif = max(dot(n, sd), 0.0);
		vec3 sun = lin(vec3(0.55, 0.85, 0.8)) * 1.3;
		vec3 amb = lin(vec3(0.08, 0.2, 0.22)) * (0.4 + 0.5 * n.y);
		vec3 bio = lin(vec3(0.35, 0.95, 0.9));
		vec3 c;
		if (hit.y < 1.5) {
			// Rock and coral: dark, mossy on top, sand on the canyon floor.
			float floor_sand = smoothstep(0.85, 0.95, n.y) * smoothstep(8.0, 1.0, p.y);
			vec3 rock = mix(lin(vec3(0.07, 0.1, 0.1)), lin(vec3(0.13, 0.17, 0.14)), fbm2(p.xz * 0.2 + p.y * 0.1, 4));
			rock = mix(rock, lin(vec3(0.12, 0.2, 0.12)), smoothstep(0.5, 0.9, n.y) * 0.6);
			vec3 alb = mix(rock, lin(vec3(0.42, 0.44, 0.38)), floor_sand);
			c = alb * (dif * sun * (0.6 + 1.2 * caustics(p.xz) * smoothstep(0.3, 0.9, n.y)) + amb);
			// Coral polyps: bioluminescent dots on the rock.
			vec2 v = voronoi2(vec2(p.x + p.z * 0.5, p.y + p.z * 0.3) * 0.9);
			float polyp = smoothstep(0.12, 0.0, v.x) * step(0.78, hash12(floor(vec2(p.x + p.z * 0.5, p.y + p.z * 0.3) * 0.9)));
			polyp *= (1.0 - floor_sand) * (hit.y > 0.5 ? 0.5 : 1.0);
			c += bio * polyp * 1.8 * exp(-hit.x * 0.004);
			// Coral fans in muted rose and violet on some shelves.
			float fan = smoothstep(0.62, 0.7, fbm2(p.xz * 0.08 + 3.0, 4)) * smoothstep(0.4, 0.8, n.y) * (1.0 - floor_sand);
			c = mix(c, lin(vec3(0.42, 0.26, 0.34)) * (dif * sun + amb), fan * 0.7);
		} else {
			// Kelp: olive-green fronds, translucent toward the light.
			vec3 alb = mix(lin(vec3(0.16, 0.2, 0.06)), lin(vec3(0.34, 0.38, 0.12)), hit.z);
			float back = pow(max(dot(rd, sd), 0.0), 2.0);
			c = alb * (dif * sun + amb * 1.4) + lin(vec3(0.4, 0.5, 0.15)) * back * 0.35;
		}
		col = c;
	}
	// Water absorbs: distance turns everything to the deep blue-green.
	float fog = 1.0 - exp(-dist * 0.0085);
	vec3 water_col = mix(lin(vec3(0.03, 0.1, 0.12)), lin(vec3(0.08, 0.24, 0.26)), smoothstep(-0.2, 0.6, rd.y));
	col = mix(col, water_col, fog);
	// Sun shafts.
	col += lin(vec3(0.5, 0.8, 0.72)) * shafts(ro, rd, dist) * 0.55;
	// A school of fish: small dark slivers in a loose band.
	vec2 sph = vec2(atan(rd.x, -rd.z), asin(rd.y));
	vec2 fp = sph * vec2(110.0, 150.0);
	vec2 fid = floor(fp);
	float school = smoothstep(0.62, 0.8, noise2(sph * vec2(7.0, 11.0) + 3.0)) * smoothstep(0.05, 0.15, rd.y);
	vec2 ff = fract(fp) - 0.5 - (hash22(fid + 4.0) - 0.5) * 0.6;
	float size = 0.5 + hash12(fid + 8.0) * 0.5;
	float fish = step(0.72, hash12(fid)) * smoothstep(0.2, 0.1, length(ff * vec2(0.9, 2.6) / size));
	col = mix(col, lin(vec3(0.02, 0.05, 0.06)), fish * school * 0.55);
	// Marine snow and a few bubbles.
	vec2 sp = uv * vec2(300.0, 200.0);
	vec2 sid = floor(sp);
	vec2 sf = fract(sp) - 0.5 - (hash22(sid) - 0.5) * 0.6;
	col += lin(vec3(0.6, 0.8, 0.78)) * step(0.985, hash12(sid)) * exp(-dot(sf, sf) * 60.0) * 0.2;
	COLOR = vec4(finish(col * 1.25, uv), 1.0);
}
