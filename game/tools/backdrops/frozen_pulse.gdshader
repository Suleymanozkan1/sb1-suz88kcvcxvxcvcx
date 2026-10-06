// Frozen Pulse backdrop bake: a frozen lake between snow-covered ridges under
// aurora curtains. The ice reflects the mountains and the aurora; snow lies on
// the gentle slopes, dark rock shows on the steep ones, soft moon shadows.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 9.0, 0.0);
const float FAR = 2200.0;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 light_dir() {
	return normalize(vec3(-0.55, 0.42, -0.35));
}

float ground_h(vec2 xz, int octaves) {
	float x = abs(xz.x + 30.0 * sin(xz.y * 0.004));
	float open = smoothstep(60.0, 460.0, x);
	float far = smoothstep(380.0, 1100.0, -xz.y);
	float m = terrain_fbm(xz * 0.0032 + vec2(3.0, 1.0), octaves);
	float peaks = pow(m, 1.4) * 165.0 * max(open, far * 0.95);
	float shore = noise2(xz * 0.03) * 3.0;
	return peaks + shore - 4.0 + smoothstep(40.0, 140.0, x) * 14.0;
}

float map(vec3 p, float t) {
	int oct = t < 200.0 ? 9 : (t < 700.0 ? 7 : 5);
	return (p.y - ground_h(p.xz, oct)) * 0.3;
}

vec3 normal_at(vec3 p, float t) {
	float e = 0.03 + t * 0.0015;
	int oct = t < 200.0 ? 11 : (t < 700.0 ? 9 : 7);
	float h = ground_h(p.xz, oct);
	return normalize(vec3(h - ground_h(p.xz + vec2(e, 0.0), oct), e, h - ground_h(p.xz + vec2(0.0, e), oct)));
}

float soft_shadow(vec3 p, vec3 l) {
	float res = 1.0;
	float t = 1.0;
	for (int i = 0; i < 64; i++) {
		vec3 q = p + l * t;
		float h = q.y - ground_h(q.xz, 5);
		res = min(res, 10.0 * h / t);
		t += clamp(h * 0.6, 2.0, 40.0);
		if (res < 0.0 || q.y > 500.0) {
			break;
		}
	}
	return clamp(res, 0.0, 1.0);
}

// Aurora: a few wavy curtains in the xz plane, sampled on stacked sheets so
// each stands up as a band of vertical rays: green at the foot, violet above.
float curtain(vec2 pt, float z0, float amp, float seed) {
	float line = z0 + amp * sin(pt.x * 0.0016 + seed) + amp * 0.45 * sin(pt.x * 0.0041 + seed * 2.3)
		+ (noise2(vec2(pt.x * 0.0009, seed)) - 0.5) * amp * 1.2;
	float d = (pt.y - line) / 70.0;
	float body = exp(-d * d);
	float rays = 0.25 + 0.75 * pow(noise2(vec2(pt.x * 0.045, seed * 7.0)), 2.0);
	rays *= 0.6 + 0.4 * noise2(vec2(pt.x * 0.006, seed * 3.0));
	return body * rays;
}

vec3 aurora(vec3 rd) {
	if (rd.y < 0.02) {
		return vec3(0.0);
	}
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 64; i++) {
		float fi = float(i) / 64.0;
		float height = 120.0 + fi * 430.0;
		vec2 pt = (rd.xz / rd.y) * height;
		float c = curtain(pt, -1350.0, 320.0, 1.0) + curtain(pt, -2100.0, 460.0, 4.0) * 0.8
			+ curtain(pt, -950.0, 200.0, 9.0) * 0.6;
		float foot = smoothstep(0.0, 0.06, fi);
		vec3 tint = mix(lin(vec3(0.42, 0.86, 0.7)), lin(vec3(0.52, 0.5, 0.9)), smoothstep(0.1, 0.7, fi));
		acc += tint * c * foot * (1.0 - fi) * (1.0 - fi);
	}
	return acc * 0.09 * smoothstep(0.02, 0.15, rd.y);
}

vec3 sky(vec3 rd) {
	vec3 col = mix(lin(vec3(0.2, 0.28, 0.38)), lin(vec3(0.05, 0.07, 0.12)), smoothstep(-0.02, 0.55, rd.y));
	col += star_field(rd, 0.12, 300.0) * smoothstep(0.0, 0.15, rd.y);
	col += star_field(rd.zxy, 0.3, 700.0) * 0.4 * smoothstep(0.0, 0.15, rd.y);
	col += aurora(rd);
	return col;
}

vec3 shade_ground(vec3 p, vec3 rd, float t, bool shadows) {
	vec3 n = normal_at(p, t);
	vec3 l = light_dir();
	float dif = max(dot(n, l), 0.0);
	float sha = (shadows && dif > 0.0) ? soft_shadow(p + n * 0.5, l) : 1.0;
	float snow = smoothstep(0.62, 0.8, n.y + 0.12 * (fbm2(p.xz * 0.04, 4) - 0.5));
	vec3 rock = mix(lin(vec3(0.1, 0.11, 0.14)), lin(vec3(0.2, 0.21, 0.25)), fbm2(p.xz * 0.08, 4));
	vec3 alb = mix(rock, lin(vec3(0.82, 0.88, 0.96)), snow);
	vec3 moon = lin(vec3(0.85, 0.92, 1.0)) * 1.1;
	vec3 sky_amb = lin(vec3(0.24, 0.32, 0.46)) * (0.5 + 0.5 * n.y);
	vec3 aur = lin(vec3(0.3, 0.6, 0.5)) * 0.12 * (0.5 + 0.5 * n.y);
	vec3 col = alb * (dif * sha * moon + sky_amb * 0.55 + aur);
	// Wind-blown sparkle on the snow.
	col += snow * step(0.985, hash12(floor(p.xz * 3.0))) * dif * sha * 0.6 * exp(-t * 0.01);
	return col;
}

float march(vec3 ro, vec3 rd, float tmax, int steps) {
	float t = 0.5;
	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * t;
		if (t > tmax || (p.y > 520.0 && rd.y > 0.0)) {
			return -1.0;
		}
		float h = map(p, t);
		if (h < 0.0012 * t) {
			return t;
		}
		t += max(h, 0.002 * t);
	}
	return -1.0;
}

vec3 haze(vec3 col, vec3 rd, float t) {
	float f = 1.0 - exp(-t * 0.00055);
	vec3 hz = mix(lin(vec3(0.2, 0.27, 0.37)), lin(vec3(0.3, 0.38, 0.48)), pow(max(dot(rd, light_dir()), 0.0), 4.0));
	return mix(col, hz, f);
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	float t_ground = march(ro, rd, FAR, 800);
	float t_ice = rd.y < 0.0 ? -ro.y / rd.y : -1.0;
	vec3 col = sky(rd);
	if (t_ice > 0.0 && (t_ground < 0.0 || t_ice < t_ground)) {
		// The frozen lake: a slightly bumpy mirror with cracks and snow drifts.
		vec3 p = ro + rd * t_ice;
		vec2 bump = vec2(noise2(p.xz * 0.6), noise2(p.xz * 0.6 + 9.0)) - 0.5;
		vec3 n = normalize(vec3(bump.x * 0.05, 1.0, bump.y * 0.05));
		vec3 rr = reflect(rd, n);
		float tr = march(p + vec3(0.0, 0.05, 0.0), rr, FAR, 260);
		vec3 refl = tr > 0.0 ? haze(shade_ground(p + rr * tr, rr, tr, false), rr, tr) : sky(rr);
		float fres = 0.08 + 0.92 * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
		vec3 ice = lin(vec3(0.1, 0.16, 0.22));
		col = mix(ice, refl, clamp(fres + 0.35, 0.0, 1.0));
		vec2 v = voronoi2(p.xz * 0.3);
		float crack = smoothstep(0.035, 0.0, v.y - v.x) * exp(-t_ice * 0.006);
		col += lin(vec3(0.55, 0.7, 0.8)) * crack * 0.18;
		float drift = smoothstep(0.55, 0.75, fbm2(p.xz * 0.02 + 4.0, 5));
		col = mix(col, shade_ground(vec3(p.x, 0.0, p.z), rd, t_ice, false) * 0.9, drift * 0.85);
		col = haze(col, rd, t_ice);
	} else if (t_ground > 0.0) {
		vec3 p = ro + rd * t_ground;
		col = haze(shade_ground(p, rd, t_ground, true), rd, t_ground);
	}
	COLOR = vec4(finish(col * 1.15, uv), 1.0);
}
