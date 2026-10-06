// Desert Reactor backdrop bake: sharp-crested dunes at golden hour, mesas on
// the horizon, and the reactor: cooling towers and a dome silhouetted against
// a low sun, steam drifting off the towers, warm haze thick toward the sun.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 8.0, 0.0);
const float FAR = 3000.0;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 sun_dir() {
	return dir_from(7.0, 9.0);
}

float dunes(vec2 xz) {
	vec2 w = xz + vec2(fbm2(xz * 0.004, 3), fbm2(xz * 0.004 + 5.0, 3)) * 90.0;
	float a = dot(w, normalize(vec2(1.0, 0.35))) * 0.016;
	float crest = 1.0 - abs(sin(a + sin(w.y * 0.007) * 1.4));
	crest = pow(crest, 1.8);
	float b = dot(w, normalize(vec2(-0.4, 1.0))) * 0.045;
	float ripple = 1.0 - abs(sin(b + noise2(w * 0.01) * 3.0));
	return crest * 16.0 + ripple * 3.5 * (0.5 + 0.5 * noise2(w * 0.006));
}

float mesas(vec2 xz) {
	float m = fbm2(xz * 0.0016 + vec2(2.0, 7.0), 5);
	float top = smoothstep(0.52, 0.56, m) * 120.0 + smoothstep(0.62, 0.64, m) * 60.0;
	float rough = fbm2(xz * 0.02, 4) * 10.0 * smoothstep(0.5, 0.6, m);
	return (top + rough) * smoothstep(900.0, 1500.0, -xz.y);
}

float ground_h(vec2 xz) {
	float near = smoothstep(20.0, 120.0, abs(xz.x));
	return dunes(xz) * (0.35 + 0.65 * near) + mesas(xz) - 4.0;
}

// Hyperboloid cooling tower at c (base), height h, throat radius r.
float tower(vec3 p, vec3 c, float h, float r) {
	vec3 q = p - c;
	float y = clamp(q.y, 0.0, h);
	float throat = h * 0.72;
	float rad = r * sqrt(1.0 + pow((y - throat) / (h * 0.42), 2.0));
	float side = (length(q.xz) - rad) * 0.8;
	return max(side, max(q.y - h, -q.y));
}

// .x distance, .y material (0 sand / rock, 1 reactor).
vec2 map(vec3 p) {
	float g = (p.y - ground_h(p.xz)) * 0.5;
	float r = tower(p, vec3(-240.0, -5.0, -1250.0), 210.0, 52.0);
	r = min(r, tower(p, vec3(-60.0, -5.0, -1420.0), 240.0, 58.0));
	r = min(r, tower(p, vec3(290.0, -5.0, -1320.0), 175.0, 44.0));
	// Reactor dome and its block, a stack and a lattice mast.
	vec3 d = p - vec3(120.0, -10.0, -1180.0);
	r = min(r, max(length(d * vec3(1.0, 1.3, 1.0)) - 80.0, -d.y));
	r = min(r, sdf_box(d - vec3(-100.0, 0.0, 10.0), vec3(70.0, 38.0, 40.0)));
	r = min(r, sdf_cylinder(d - vec3(-10.0, 0.0, -60.0), 7.0, 170.0));
	vec3 m = p - vec3(560.0, 0.0, -1500.0);
	r = min(r, max(sdf_box(m, vec3(9.0, 260.0, 9.0)), -sdf_box(mod(m + 6.0, 12.0) - 6.0, vec3(4.2, 4.2, 20.0))));
	return r < g ? vec2(r, 1.0) : vec2(g, 0.0);
}

vec3 normal_at(vec3 p, float t) {
	float e = 0.03 + t * 0.001;
	vec2 k = vec2(1.0, -1.0);
	return normalize(
		k.xyy * map(p + k.xyy * e).x + k.yyx * map(p + k.yyx * e).x + k.yxy * map(p + k.yxy * e).x
		+ k.xxx * map(p + k.xxx * e).x
	);
}

float soft_shadow(vec3 p, vec3 l) {
	float res = 1.0;
	float t = 0.5;
	for (int i = 0; i < 48; i++) {
		float h = map(p + l * t).x;
		res = min(res, 8.0 * h / t);
		t += clamp(h, 0.5, 30.0);
		if (res < 0.0 || t > 900.0) {
			break;
		}
	}
	return clamp(res, 0.0, 1.0);
}

vec3 sky(vec3 rd) {
	vec3 sd = sun_dir();
	float mu = max(dot(rd, sd), 0.0);
	float h = max(rd.y, 0.0);
	vec3 col = mix(lin(vec3(0.8, 0.52, 0.36)), lin(vec3(0.12, 0.1, 0.13)), pow(smoothstep(0.0, 0.75, h), 0.45));
	col = mix(col, lin(vec3(1.0, 0.78, 0.5)), pow(mu, 8.0) * 0.8 * (1.0 - smoothstep(0.0, 0.4, h)));
	// Thin high clouds lit from below by the sun.
	vec2 cp = rd.xz / max(rd.y, 0.05);
	cp = vec2(cp.x * 0.5, cp.y * 1.5);
	float wisp = fbm2(cp * 1.4 + vec2(0.0, 3.0) + fbm2(cp * 3.0, 4) * 0.6, 7);
	float cl = smoothstep(0.6, 0.9, wisp) * smoothstep(0.03, 0.14, rd.y) * (1.0 - smoothstep(0.25, 0.6, rd.y));
	vec3 cloud = mix(lin(vec3(0.3, 0.17, 0.16)), lin(vec3(1.0, 0.62, 0.38)), pow(mu, 2.0) * 0.8 + 0.2 * (1.0 - h));
	col = mix(col, cloud, cl * 0.8);
	col += lin(vec3(1.0, 0.8, 0.55)) * (pow(mu, 40.0) * 0.45 + pow(mu, 600.0) * 1.5);
	col += lin(vec3(1.0, 0.95, 0.85)) * smoothstep(0.99905, 0.9992, mu) * 8.0;
	return col;
}

// Steam off the towers: soft plumes leaning with the wind, glowing at their
// edges where the sun shines through.
vec4 steam(vec3 ro, vec3 rd, float tmax) {
	vec4 acc = vec4(0.0);
	vec3 sd = sun_dir();
	vec3 tops[3] = vec3[](vec3(-240.0, 205.0, -1250.0), vec3(-60.0, 235.0, -1420.0), vec3(290.0, 170.0, -1320.0));
	for (int k = 0; k < 3; k++) {
		vec3 c = tops[k];
		float t0 = max(length(c - ro) - 260.0, 0.0);
		for (int i = 0; i < 40; i++) {
			float t = t0 + float(i) * 13.0;
			if (t > tmax || acc.a > 0.97) {
				break;
			}
			vec3 p = ro + rd * t;
			vec3 q = p - c;
			float up = max(q.y, 0.0);
			vec2 drift = vec2(up * 0.55, -up * 0.1);
			float r = 24.0 + up * 0.3;
			float shape = 1.0 - length(vec2(q.x - drift.x, q.z - drift.y)) / r;
			float env = smoothstep(-5.0, 20.0, q.y) * (1.0 - smoothstep(150.0, 320.0, q.y));
			if (shape < -0.3 || env <= 0.0) {
				continue;
			}
			float den = clamp(shape * 1.4 + (fbm3(p * 0.025, 5) - 0.55) * 1.2, 0.0, 1.0);
			den *= env * smoothstep(-0.3, 0.05, shape) * 0.16;
			if (den > 0.001) {
				vec3 lit = mix(lin(vec3(0.5, 0.36, 0.32)), lin(vec3(1.0, 0.82, 0.62)), pow(max(dot(rd, sd), 0.0), 4.0));
				lit *= 0.7 + 0.6 * smoothstep(0.3, 0.0, shape);
				acc.rgb += (1.0 - acc.a) * den * lit;
				acc.a += (1.0 - acc.a) * den;
			}
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	float t = 0.5;
	float mat_id = -1.0;
	for (int i = 0; i < 600; i++) {
		vec3 p = ro + rd * t;
		if (t > FAR || (p.y > 300.0 && rd.y > 0.0)) {
			break;
		}
		vec2 h = map(p);
		if (h.x < 0.001 * t) {
			mat_id = h.y;
			break;
		}
		t += max(h.x, 0.0015 * t);
	}
	vec3 sd = sun_dir();
	vec3 col = sky(rd);
	float tmax = mat_id >= 0.0 ? t : FAR;
	if (mat_id >= 0.0) {
		vec3 p = ro + rd * t;
		vec3 n = normal_at(p, t);
		float dif = max(dot(n, sd), 0.0);
		float sha = dif > 0.0 ? soft_shadow(p + n * 0.3, sd) : 0.0;
		vec3 sun = lin(vec3(1.0, 0.78, 0.55)) * 2.2;
		vec3 amb = lin(vec3(0.36, 0.24, 0.24)) * (0.35 + 0.35 * n.y);
		vec3 bounce = lin(vec3(0.5, 0.32, 0.2)) * 0.15 * max(-n.y, 0.0);
		vec3 alb;
		if (mat_id > 0.5) {
			alb = lin(vec3(0.42, 0.38, 0.36)) * (0.85 + 0.15 * noise2(p.xy * 0.2));
			// Aircraft lights on the reactor tops.
			float beacon = step(0.0, p.y - 150.0) * step(0.997, hash12(floor(p.xz * 0.5) + floor(p.y * 0.2)));
			col = alb * (dif * sha * sun + amb) + lin(vec3(1.0, 0.3, 0.2)) * beacon * 3.0;
		} else {
			float grain = noise2(p.xz * 2.0) * 0.1;
			alb = mix(lin(vec3(0.62, 0.42, 0.27)), lin(vec3(0.78, 0.55, 0.34)), smoothstep(0.4, 0.8, n.y) + grain);
			alb = mix(alb, lin(vec3(0.45, 0.3, 0.22)), smoothstep(30.0, 90.0, p.y));
			// Backlit crests: a rim where the slope faces the sun at a grazing angle.
			float rim = pow(1.0 - max(dot(n, -rd), 0.0), 4.0) * dif;
			col = alb * (dif * sha * sun + amb + bounce) + lin(vec3(1.0, 0.75, 0.5)) * rim * sha * 0.5;
		}
		// Warm haze, strongest toward the sun.
		float fog = 1.0 - exp(-t * 0.00042);
		vec3 hz = mix(lin(vec3(0.5, 0.3, 0.22)), lin(vec3(1.0, 0.72, 0.46)), pow(max(dot(rd, sd), 0.0), 5.0));
		col = mix(col, hz, fog);
	}
	vec4 st = steam(ro, rd, tmax);
	col = col * (1.0 - st.a) + st.rgb;
	// God rays: light bleeding round the silhouettes toward the sun.
	col += lin(vec3(1.0, 0.7, 0.45)) * pow(max(dot(rd, sd), 0.0), 16.0) * 0.12;
	COLOR = vec4(finish(col * 0.8, uv), 1.0);
}
