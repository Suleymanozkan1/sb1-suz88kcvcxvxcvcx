// Crystal Valley backdrop bake: a moonlit valley walled by eroded ridges, its
// slopes grown over with clusters of glowing hexagonal crystals, one giant
// spire far ahead, mist pooled on the valley floor, a nebula and the moon.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 11.0, 0.0);
const float FAR = 1400.0;
const float CELL = 28.0;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 moon_dir() {
	return dir_from(4.0, 15.0);
}

float meander(float z) {
	return 14.0 * sin(z * 0.006) + 6.0 * sin(z * 0.017 + 1.3);
}

float ground_h(vec2 xz, int octaves) {
	float x = abs(xz.x - meander(xz.y));
	float walls = pow(max(x - 80.0, 0.0), 1.1) * 0.3;
	float hills = terrain_fbm(xz * 0.011, octaves) * 32.0 * smoothstep(30.0, 110.0, x);
	float distant = smoothstep(380.0, 900.0, -xz.y) * terrain_fbm(xz * 0.003 + 7.0, max(octaves - 2, 3)) * 230.0;
	return walls + hills + distant - 6.0 + noise2(xz * 0.08) * 1.6;
}

// Hexagonal crystal with a pointed tip: radius r, tip at height h.
float crystal_shape(vec3 q, float r, float h) {
	vec2 a = abs(q.xz);
	float hex = max(a.x * 0.8660254 + a.y * 0.5, a.y);
	float side = hex - r;
	float tip = (hex + (q.y - h) * 0.42) * 0.92;
	return max(max(side, tip), -q.y - 30.0);
}

// Base height of a crystal cell (cheap terrain: the crystals sink well in).
float cell_base(vec2 c) {
	return ground_h(c, 3) - 3.0;
}

// One cell's cluster (up to three crystals) at p; .x distance, .y the cell's
// hue seed, .z height fraction along the struck crystal.
vec3 cluster(vec3 p, vec2 cell) {
	vec3 best = vec3(1e5, 0.0, 0.0);
	vec2 centre = (cell + 0.5) * CELL;
	float x = abs(centre.x - meander(centre.y));
	float seed = hash12(cell);
	if (x < 56.0 || x > 240.0 || centre.y > -40.0 || seed > 0.34 - 0.2 * smoothstep(300.0, 800.0, -centre.y)) {
		return best;
	}
	float base = cell_base(centre);
	vec2 jitter = (hash22(cell + 4.0) - 0.5) * CELL * 0.2;
	float grow = (1.0 + smoothstep(60.0, 180.0, x) * 0.5) * (0.45 + 0.55 * smoothstep(60.0, 260.0, -centre.y));
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 h2 = hash22(cell * 1.7 + fi * 13.1);
		vec3 q = p - vec3(centre.x + jitter.x + (h2.x - 0.5) * 7.0 * fi, base, centre.y + jitter.y + (h2.y - 0.5) * 7.0 * fi);
		q.xy = rot((h2.x - 0.5) * 0.3 * min(fi, 1.0)) * q.xy;
		q.zy = rot((h2.y - 0.5) * 0.3 * min(fi, 1.0)) * q.zy;
		q.xz = rot(seed * 6.28 + fi) * q.xz;
		float r = mix(3.4, 1.5, fi * 0.5) * (0.7 + seed * 0.6) * grow;
		float h = mix(36.0, 15.0, fi * 0.5) * (0.6 + h2.y * 0.7) * grow;
		float d = crystal_shape(q, r, h);
		if (d < best.x) {
			best = vec3(d, seed, clamp(q.y / h, 0.0, 1.0));
		}
	}
	return best;
}

// Crystal clusters on the valley sides plus the giant spire. A cluster reaches
// less than a cell from its centre, so the four nearest cells see all of them
// (one cell alone sliced the leaning crystals into stripes).
vec3 crystals(vec3 p) {
	vec3 best = vec3(1e5, 0.0, 0.0);
	vec2 corner = floor(p.xz / CELL - 0.5);
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec3 c = cluster(p, corner + vec2(float(i), float(j)));
			if (c.x < best.x) {
				best = c;
			}
		}
	}
	// The giant spire ahead, left of the moon.
	vec3 g = p - vec3(-70.0, -20.0, -620.0);
	g.xy = rot(0.07) * g.xy;
	float giant = crystal_shape(g, 22.0, 215.0);
	vec3 g2 = p - vec3(-30.0, -20.0, -600.0);
	g2.xy = rot(-0.22) * g2.xy;
	giant = min(giant, crystal_shape(g2, 11.0, 120.0));
	if (giant < best.x) {
		best = vec3(giant, 0.37, clamp((p.y + 20.0) / 215.0, 0.0, 1.0));
	}
	return best;
}

// .x distance, .y material (0 ground, 1 crystal).
vec2 map(vec3 p, float t) {
	int oct = t < 120.0 ? 8 : (t < 400.0 ? 6 : 5);
	float g = (p.y - ground_h(p.xz, oct)) * 0.5;
	vec3 c = crystals(p);
	return c.x < g ? vec2(c.x * 0.8, 1.0) : vec2(g, 0.0);
}

vec3 normal_at(vec3 p, float t) {
	float e = 0.02 + t * 0.0012;
	vec2 k = vec2(1.0, -1.0);
	return normalize(
		k.xyy * map(p + k.xyy * e, t).x + k.yyx * map(p + k.yyx * e, t).x + k.yxy * map(p + k.yxy * e, t).x
		+ k.xxx * map(p + k.xxx * e, t).x
	);
}

vec3 sky(vec3 rd) {
	vec3 top = lin(vec3(0.035, 0.04, 0.1));
	vec3 low = lin(vec3(0.16, 0.15, 0.28));
	vec3 col = mix(low, top, smoothstep(-0.05, 0.6, rd.y));
	vec3 md = moon_dir();
	float mu = max(dot(rd, md), 0.0);
	// Nebula: two tinted fbm clouds in a band across the sky.
	vec3 np = rd * 3.2;
	float n1 = fbm3(np + vec3(0.0, 0.0, 4.0), 6);
	float n2 = fbm3(np * 1.7 + vec3(5.0, 1.0, 0.0), 5);
	float band = exp(-pow((rd.y - 0.28 - rd.x * 0.35) * 3.0, 2.0));
	float dust = smoothstep(0.5, 0.68, fbm3(np * 2.6 + vec3(9.0, 2.0, 1.0), 6));
	col += lin(vec3(0.36, 0.26, 0.64)) * pow(smoothstep(0.4, 0.85, n1), 1.5) * band * 1.1 * (1.0 - dust * 0.7);
	col += lin(vec3(0.2, 0.36, 0.6)) * pow(smoothstep(0.45, 0.9, n2), 1.5) * band * 0.8 * (1.0 - dust * 0.7);
	col += star_field(rd, 0.09, 260.0) * (1.0 - band * 0.5) * smoothstep(0.02, 0.2, rd.y);
	col += star_field(rd.zxy, 0.25, 600.0) * 0.5 * smoothstep(0.02, 0.2, rd.y);
	// Moon halo, then the disc with its maria.
	col += lin(vec3(0.62, 0.56, 0.85)) * (pow(mu, 900.0) * 0.5 + pow(mu, 40.0) * 0.1);
	float disc = smoothstep(0.99925, 0.99935, mu);
	if (disc > 0.0) {
		vec3 tangent = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec3 bit = cross(tangent, md);
		vec2 dp = vec2(dot(rd, tangent), dot(rd, bit)) * 36.0;
		float maria = smoothstep(0.45, 0.7, fbm2(dp * 0.12 + 2.0, 5));
		float limb = sqrt(max(1.0 - dot(dp, dp) / 0.9, 0.0));
		vec3 moon = lin(vec3(0.92, 0.89, 1.0)) * (1.0 - maria * 0.35) * (0.55 + 0.45 * limb) * 2.4;
		col = mix(col, moon, disc);
	}
	return col;
}

vec3 shade(vec3 p, vec3 rd, float t, float mat_id) {
	vec3 n = normal_at(p, t);
	vec3 md = moon_dir();
	float dif = max(dot(n, md), 0.0);
	float amb = 0.55 + 0.45 * n.y;
	vec3 moon_light = lin(vec3(0.75, 0.72, 0.95)) * 1.7;
	vec3 sky_light = lin(vec3(0.24, 0.21, 0.4)) * 0.5;
	vec3 c = crystals(p);
	if (mat_id > 0.5) {
		// Glassy: a dark body, light caught inside toward the tip and at the
		// root, bright rims and the moon's glint. Most violet, some ice blue,
		// Most violet, some ice blue.
		vec3 hue = lin(vec3(0.62, 0.53, 0.92));
		hue = mix(hue, lin(vec3(0.56, 0.8, 0.94)), step(0.2, fract(c.y * 7.3)) * step(fract(c.y * 7.3), 0.42));
		float facing = max(dot(n, -rd), 0.0);
		float fres = pow(1.0 - facing, 3.0);
		vec3 refl = sky(reflect(rd, n));
		vec3 inner = hue * (0.1 + 1.1 * pow(c.z, 4.0) + 0.5 * pow(1.0 - c.z, 6.0));
		vec3 col = lin(vec3(0.05, 0.045, 0.09)) * (dif * moon_light + amb * sky_light);
		col += inner + refl * (0.06 + 0.7 * fres) + hue * fres * 0.9;
		float rm = max(dot(reflect(rd, n), md), 0.0);
		col += moon_light * (pow(rm, 80.0) * 2.0 + pow(rm, 6.0) * 0.25);
		return col;
	}
	// Rock: dark violet-grey, lighter and frosted on gentle moonlit slopes,
	// with crystal grit glinting and a glow where crystals stand close.
	float slope = n.y;
	vec3 rock = mix(lin(vec3(0.13, 0.13, 0.17)), lin(vec3(0.24, 0.24, 0.29)), fbm2(p.xz * 0.15, 4));
	rock = mix(rock, lin(vec3(0.62, 0.62, 0.72)), smoothstep(0.78, 0.94, slope) * smoothstep(8.0, 50.0, p.y) * 0.7);
	// A cool fill from behind the viewer so the slopes facing us keep their form.
	vec3 fill_dir = normalize(vec3(-0.35, 0.55, 0.75));
	vec3 fill = lin(vec3(0.42, 0.44, 0.62)) * 0.35 * max(dot(n, fill_dir), 0.0);
	float strata = 0.85 + 0.15 * sin(p.y * 0.9 + fbm2(p.xz * 0.05, 3) * 6.0);
	vec3 col = rock * strata * (dif * moon_light + amb * sky_light + fill);
	vec2 v = voronoi2(p.xz * 1.3);
	float grit = smoothstep(0.08, 0.0, v.x) * step(0.82, hash12(floor(p.xz * 1.3)));
	col += lin(vec3(0.7, 0.6, 1.0)) * grit * 0.8 * exp(-t * 0.01);
	col += lin(vec3(0.55, 0.42, 1.0)) * exp(-max(c.x, 0.0) * 0.28) * 0.35;
	return col;
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	float t = 0.5;
	float mat_id = -1.0;
	for (int i = 0; i < 420; i++) {
		vec3 p = ro + rd * t;
		if (t > FAR || (p.y > 420.0 && rd.y > 0.0)) {
			break;
		}
		vec2 h = map(p, t);
		if (h.x < 0.0015 * t) {
			mat_id = h.y;
			break;
		}
		t += max(h.x, 0.002 * t);
	}
	vec3 col = sky(rd);
	vec3 md = moon_dir();
	if (mat_id >= 0.0) {
		vec3 p = ro + rd * t;
		vec3 surf = shade(p, rd, t, mat_id);
		// Height fog pooled in the valley, lit toward the moon.
		float ry = abs(rd.y) < 1e-4 ? 1e-4 : rd.y;
		float amount = 0.0032 / 0.035 * exp(-ro.y * 0.035) * (1.0 - exp(-t * ry * 0.035)) / ry;
		float fog = 1.0 - exp(-amount - t * 0.0003);
		vec3 fog_col = mix(lin(vec3(0.13, 0.12, 0.23)), lin(vec3(0.34, 0.31, 0.5)), pow(max(dot(rd, md), 0.0), 6.0));
		col = mix(surf, fog_col, fog);
	} else {
		// Mist above the horizon too, so the far mountains meet the sky softly.
		col = mix(col, lin(vec3(0.17, 0.16, 0.29)), exp(-max(rd.y, 0.0) * 16.0) * 0.4);
	}
	COLOR = vec4(finish(col * 1.1, uv), 1.0);
}
