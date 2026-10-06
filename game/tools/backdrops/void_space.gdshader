// Void Space backdrop bake: a ringed gas giant lit from the side, a glowing
// nebula with dark dust lanes behind it, dense stars, and asteroids drifting
// near the horizon, rim-lit by the distant star.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const float PLANET_DIST = 1000.0;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 star_dir() {
	return normalize(vec3(-0.78, 0.32, 0.3));
}

vec3 planet_centre() {
	return dir_from(-9.0, 11.5) * PLANET_DIST;
}

float planet_radius() {
	return PLANET_DIST * sin(radians(7.5));
}

vec3 ring_normal() {
	return normalize(-normalize(planet_centre()) * 0.5 + vec3(0.32, 1.0, 0.0));
}

vec3 nebula(vec3 rd) {
	vec3 col = vec3(0.0);
	float shade = 0.0;
	for (int i = 0; i < 40; i++) {
		float fi = float(i) / 40.0;
		vec3 p = rd * (2.4 + fi * 1.6) + vec3(1.3, -0.4, 0.8);
		float den = fbm3(p * 1.4, 7);
		float band = exp(-pow((dot(rd, normalize(vec3(0.5, 1.0, 0.2))) - 0.05) * 2.4, 2.0));
		float e = smoothstep(0.42, 0.9, den) * band;
		float dust = smoothstep(0.52, 0.7, fbm3(p * 3.1 + 5.0, 6)) * band;
		vec3 tint = mix(lin(vec3(0.38, 0.26, 0.66)), lin(vec3(0.16, 0.4, 0.62)), smoothstep(0.3, 0.7, noise3(p * 0.9)));
		tint = mix(tint, lin(vec3(0.85, 0.4, 0.7)), pow(smoothstep(0.62, 0.95, den), 2.0) * 0.8);
		col += tint * e * (1.0 - shade) * 0.07;
		shade = clamp(shade + dust * 0.035, 0.0, 0.85);
	}
	return col;
}

vec3 stars(vec3 rd) {
	vec3 col = star_field(rd, 0.14, 320.0) + star_field(rd.zxy, 0.35, 760.0) * 0.5;
	col += star_field(rd.yzx, 0.5, 1400.0) * 0.25;
	// A few bright stars with diffraction spikes.
	vec2 sph = vec2(atan(rd.x, -rd.z), asin(rd.y)) * 9.0;
	vec2 id = floor(sph);
	if (hash12(id + 0.7) < 0.07) {
		vec2 f = fract(sph) - 0.5 - (hash22(id) - 0.5) * 0.6;
		float b = hash12(id + 2.0);
		float core = exp(-dot(f, f) * 2400.0);
		float spikes = exp(-abs(f.x) * 900.0) * exp(-abs(f.y) * 40.0) + exp(-abs(f.y) * 900.0) * exp(-abs(f.x) * 40.0);
		col += mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.85, 0.75), b) * (core * 6.0 + spikes * 0.8) * (0.4 + b);
	}
	return col;
}

// Gas giant surface colour at a point of its sphere (normal n).
vec3 planet_surface(vec3 n) {
	vec3 axis = ring_normal();
	// Seamless: noise on the sphere itself, no longitude wrap.
	float lat = dot(n, axis);
	float warp = (fbm3(n * 2.5, 5) - 0.5) * 0.18;
	float bands = sin((lat + warp) * 46.0 + fbm2(vec2(lat * 20.0, 1.0), 3) * 4.0) * 0.5 + 0.5;
	float fine = fbm3(n * 7.0 + axis * (lat + warp * 0.5) * 80.0, 4);
	vec3 a = lin(vec3(0.56, 0.52, 0.74));
	vec3 b = lin(vec3(0.3, 0.3, 0.46));
	vec3 c = lin(vec3(0.75, 0.66, 0.78));
	vec3 col = mix(b, a, bands);
	col = mix(col, c, smoothstep(0.6, 0.8, fine) * 0.5);
	// A storm.
	vec3 storm_at = normalize(-normalize(planet_centre()) + vec3(-0.35, -0.2, 0.0));
	float storm = length((n - storm_at) * vec3(1.0, 2.6, 1.0));
	col = mix(col, lin(vec3(0.82, 0.7, 0.8)), smoothstep(0.2, 0.1, storm) * 0.7);
	return col;
}

// Ring colour and opacity at a radius fraction (0 inner, 1 outer).
vec4 ring_at(float f) {
	if (f < 0.0 || f > 1.0) {
		return vec4(0.0);
	}
	float n = noise2(vec2(f * 160.0, 0.5)) * 0.6 + noise2(vec2(f * 40.0, 3.5)) * 0.4;
	float gap = smoothstep(0.02, 0.0, abs(f - 0.62)) + smoothstep(0.012, 0.0, abs(f - 0.3)) * 0.8;
	float a = (0.25 + 0.65 * n) * (1.0 - gap) * smoothstep(0.0, 0.05, f) * smoothstep(1.0, 0.9, f);
	vec3 col = mix(lin(vec3(0.62, 0.58, 0.72)), lin(vec3(0.82, 0.76, 0.78)), n);
	return vec4(col, a);
}

float sphere_hit(vec3 ro, vec3 rd, vec3 c, float r) {
	vec3 oc = ro - c;
	float b = dot(oc, rd);
	float h = b * b - (dot(oc, oc) - r * r);
	return h < 0.0 ? -1.0 : -b - sqrt(h);
}

// Asteroids: a few big lumpy rocks near the horizon, then a sprinkle of
// small ones.
float rock(vec3 p, vec3 c, float r) {
	vec3 q = p - c;
	float d = length(q * vec3(1.0, 0.8, 1.1)) - r;
	return d + (fbm3(q * (2.2 / r) + c * 0.01, 5) - 0.5) * r * 0.55;
}

float rocks(vec3 p) {
	float d = rock(p, vec3(-150.0, 18.0, -420.0), 34.0);
	d = min(d, rock(p, vec3(-95.0, 42.0, -520.0), 12.0));
	d = min(d, rock(p, vec3(190.0, 4.0, -500.0), 46.0));
	d = min(d, rock(p, vec3(120.0, 52.0, -560.0), 10.0));
	d = min(d, rock(p, vec3(40.0, -20.0, -330.0), 9.0));
	d = min(d, rock(p, vec3(-60.0, -6.0, -900.0), 26.0));
	return d;
}

vec3 rocks_normal(vec3 p) {
	vec2 e = vec2(0.05, 0.0);
	return normalize(vec3(
		rocks(p + e.xyy) - rocks(p - e.xyy), rocks(p + e.yxy) - rocks(p - e.yxy), rocks(p + e.yyx) - rocks(p - e.yyx)
	));
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = vec3(0.0);
	vec3 L = star_dir();
	vec3 col = mix(lin(vec3(0.03, 0.03, 0.06)), lin(vec3(0.012, 0.012, 0.03)), smoothstep(-0.2, 0.8, rd.y));
	col += nebula(rd);
	col += stars(rd);
	// The star itself, off to the left, just out of frame: its glow.
	col += lin(vec3(0.9, 0.85, 1.0)) * pow(max(dot(rd, L), 0.0), 18.0) * 0.6;
	vec3 pc = planet_centre();
	float pr = planet_radius();
	vec3 rn = ring_normal();
	float tp = sphere_hit(ro, rd, pc, pr);
	float tr = dot(pc - ro, rn) / dot(rd, rn);
	vec4 ring_front = vec4(0.0);
	vec4 ring_back = vec4(0.0);
	if (tr > 0.0) {
		vec3 rp = ro + rd * tr;
		float f = (length(rp - pc) / pr - 1.35) / 1.15;
		vec4 rc = ring_at(f);
		if (rc.a > 0.0) {
			// Lit side of the rings and the planet's shadow on them.
			float lit = abs(dot(rn, L)) * 0.8 + 0.25;
			float ts = sphere_hit(rp, L, pc, pr);
			lit *= ts > 0.0 ? 0.08 : 1.0;
			rc.rgb *= lit * 1.4;
			if (tp > 0.0 && tr > tp) {
				ring_back = rc;
			} else {
				ring_front = rc;
			}
		}
	}
	if (tp > 0.0) {
		vec3 p = ro + rd * tp;
		vec3 n = normalize(p - pc);
		float dif = max(dot(n, L), 0.0);
		// Ring shadow on the planet.
		float trs = dot(pc - p, rn) / dot(L, rn);
		float ring_sh = 1.0;
		if (trs > 0.0) {
			float f = (length(p + L * trs - pc) / pr - 1.35) / 1.15;
			ring_sh = 1.0 - ring_at(f).a * 0.8;
		}
		vec3 surf = planet_surface(n);
		vec3 pcol = surf * (dif * ring_sh * lin(vec3(1.0, 0.96, 0.92)) * 1.6 + lin(vec3(0.1, 0.08, 0.18)) * 0.25);
		float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
		pcol += lin(vec3(0.45, 0.5, 0.95)) * rim * (0.2 + 0.8 * smoothstep(-0.2, 0.4, dot(n, L))) * 0.8;
		col = pcol;
	} else {
		// Thin atmosphere glow just outside the limb.
		vec3 oc = pc - ro;
		float closest = length(oc - rd * dot(oc, rd));
		float halo = exp(-max(closest - pr, 0.0) / (pr * 0.04));
		vec3 out_dir = normalize(rd * dot(oc, rd) - oc);
		col += lin(vec3(0.4, 0.45, 0.95)) * halo * 0.25 * smoothstep(-0.2, 0.5, dot(out_dir, L));
		col = mix(col, ring_back.rgb, ring_back.a);
	}
	col = mix(col, ring_front.rgb, ring_front.a);
	// Asteroids in front of everything.
	float t = 1.0;
	bool hit = false;
	for (int i = 0; i < 220; i++) {
		float d = rocks(ro + rd * t);
		if (d < 0.001 * t) {
			hit = true;
			break;
		}
		t += d * 0.7;
		if (t > 1200.0) {
			break;
		}
	}
	if (hit) {
		vec3 p = ro + rd * t;
		vec3 n = rocks_normal(p);
		float dif = max(dot(n, L), 0.0);
		vec3 alb = mix(lin(vec3(0.16, 0.15, 0.17)), lin(vec3(0.3, 0.27, 0.27)), fbm3(p * 0.4, 4));
		vec3 neb_amb = lin(vec3(0.2, 0.16, 0.36)) * (0.3 + 0.2 * n.y);
		vec3 rcol = alb * (dif * lin(vec3(1.0, 0.95, 0.9)) * 2.0 + neb_amb * 0.5);
		rcol += lin(vec3(0.6, 0.55, 0.9)) * pow(1.0 - max(dot(n, -rd), 0.0), 4.0) * dif * 0.6;
		col = rcol;
	}
	COLOR = vec4(finish(col * 1.1, uv), 1.0);
}
