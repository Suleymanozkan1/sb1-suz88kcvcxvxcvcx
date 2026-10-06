// Neon Core backdrop bake: a rain-hazed night city seen from high above its
// main avenue, towers lit window by window, a low cloud ceiling glowing with
// the city's light, and far ahead The Turbine, the world's boss machine: a
// giant rotor ring standing over the skyline with lights along its rim.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 34.0, 0.0);
const float FAR = 3200.0;
const float CELL = 46.0;
const vec3 TURBINE = vec3(-20.0, 300.0, -1700.0);
const float TURBINE_R = 250.0;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

// One tower per cell beside the avenue: .x distance, .y seed, .z height.
vec3 tower_in(vec3 p, vec2 cell) {
	vec2 centre = (cell + 0.5) * CELL;
	float seed = hash12(cell);
	float side = abs(centre.x);
	if (side < 100.0 || centre.y > -20.0 || seed < 0.12) {
		return vec3(1e5, 0.0, 0.0);
	}
	vec2 jitter = (hash22(cell + 3.0) - 0.5) * 6.0;
	float far_boost = smoothstep(200.0, 1400.0, -centre.y);
	float h = (40.0 + pow(hash12(cell + 9.0), 2.2) * 260.0) * (0.6 + 0.8 * far_boost) * (0.7 + 0.3 * smoothstep(70.0, 300.0, side));
	vec2 half_size = vec2(10.0 + seed * 7.0, 10.0 + hash12(cell + 5.0) * 7.0);
	vec3 q = p - vec3(centre.x + jitter.x, 0.0, centre.y + jitter.y);
	float d = sdf_box(q - vec3(0.0, h * 0.5, 0.0), vec3(half_size.x, h * 0.5, half_size.y));
	// A narrower crown on the taller towers.
	if (h > 160.0) {
		d = min(d, sdf_box(q - vec3(0.0, h + 12.0, 0.0), vec3(half_size.x * 0.6, 12.0, half_size.y * 0.6)));
		d = min(d, sdf_box(q - vec3(0.0, h + 34.0, 0.0), vec3(0.6, 14.0, 0.6)));
	}
	return vec3(d, seed, h);
}

// Towers over the 2x2 nearest cells (a tower stays inside its cell).
vec3 towers(vec3 p) {
	vec3 best = vec3(1e5, 0.0, 0.0);
	vec2 corner = floor(p.xz / CELL - 0.5);
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec3 t = tower_in(p, corner + vec2(float(i), float(j)));
			if (t.x < best.x) {
				best = t;
			}
		}
	}
	return best;
}

// The Turbine: a rim ring, a hub and five spokes, standing facing the city.
float turbine(vec3 p) {
	vec3 q = p - TURBINE;
	q.xy = rot(0.12) * q.xy;
	float r = length(q.xy);
	float rim = length(vec2(r - TURBINE_R, q.z)) - 16.0;
	// Segmented outer housing: boxes around the rim.
	float ang = atan(q.y, q.x);
	float seg = 6.2832 / 36.0;
	float a = mod(ang + seg * 0.5, seg) - seg * 0.5;
	vec2 rq = vec2(cos(a), sin(a)) * r;
	float housing = sdf_box(vec3(rq.x - TURBINE_R, rq.y, q.z), vec3(22.0, 15.0, 26.0));
	float hub = length(q * vec3(1.0, 1.0, 0.7)) - 42.0;
	float spokes = 1e5;
	for (int k = 0; k < 5; k++) {
		float sa = 6.2832 * float(k) / 5.0 + 0.4;
		vec2 dir = vec2(cos(sa), sin(sa));
		float along = dot(q.xy, dir);
		float across = dot(q.xy, vec2(-dir.y, dir.x));
		spokes = min(spokes, sdf_box(vec3(along - TURBINE_R * 0.5, across, q.z), vec3(TURBINE_R * 0.5, 9.0 + 6.0 * (1.0 - along / TURBINE_R), 5.0)));
	}
	return min(min(rim, housing), min(hub, spokes));
}

// .x distance, .y material (0 street, 1 tower, 2 turbine), .z seed, .w height.
vec4 map(vec3 p) {
	float street = p.y;
	vec3 t = towers(p);
	float tb = turbine(p);
	vec4 best = vec4(street, 0.0, 0.0, 0.0);
	if (t.x < best.x) {
		best = vec4(t.x, 1.0, t.y, t.z);
	}
	if (tb < best.x) {
		best = vec4(tb, 2.0, 0.0, 0.0);
	}
	return best;
}

vec3 normal_at(vec3 p, float t) {
	float e = 0.02 + t * 0.0008;
	vec2 k = vec2(1.0, -1.0);
	return normalize(
		k.xyy * map(p + k.xyy * e).x + k.yyx * map(p + k.yyx * e).x + k.yxy * map(p + k.yxy * e).x
		+ k.xxx * map(p + k.xxx * e).x
	);
}

// Lit windows on a tower face: floors every 3.6 u, windows every 2.8 u, each
// lit or dark by hash, a few warm, most cool white or teal.
vec3 windows(vec3 p, vec3 n, float seed, float h, float t) {
	vec2 f = abs(n.x) > 0.5 ? p.zy : p.xy;
	vec2 cell = floor(f / vec2(2.1, 2.9));
	vec2 local = fract(f / vec2(2.1, 2.9));
	float pane = step(0.18, local.x) * step(local.x, 0.82) * step(0.25, local.y) * step(local.y, 0.8);
	float block = hash12(floor(cell / vec2(4.0, 3.0)) + seed * 91.0);
	float lit = step(0.45 + 0.35 * block, hash12(cell + seed * 37.0));
	lit *= 1.0 - smoothstep(h * 0.9, h, p.y) * 0.6;
	float tone = hash12(cell * 1.3 + seed * 5.0);
	vec3 c = tone < 0.2 ? lin(vec3(1.0, 0.8, 0.55)) : (tone < 0.65 ? lin(vec3(0.75, 0.9, 0.95)) : lin(vec3(0.45, 0.85, 0.88)));
	// Far away the panes merge: average them so the distance does not sparkle.
	float merge = smoothstep(500.0, 1500.0, t);
	return c * mix(pane * lit, 0.22 * (0.4 + block), merge) * 1.6;
}

vec3 sky(vec3 rd) {
	vec3 col = mix(lin(vec3(0.11, 0.16, 0.2)), lin(vec3(0.025, 0.035, 0.05)), smoothstep(-0.02, 0.45, rd.y));
	// A low cloud ceiling glowing with the city below it.
	if (rd.y > 0.0) {
		vec2 cp = rd.xz / rd.y * 800.0;
		float cl = fbm2(cp * 0.0018 + vec2(3.0, 1.0), 6);
		float lit = exp(-rd.y * 5.0);
		vec3 cloud = mix(lin(vec3(0.04, 0.05, 0.065)), lin(vec3(0.24, 0.3, 0.33)), lit * (0.5 + 0.5 * cl));
		col = mix(col, cloud, smoothstep(0.35, 0.65, cl) * 0.85);
	}
	return col;
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	float t = 0.5;
	vec4 hit = vec4(-1.0);
	for (int i = 0; i < 480; i++) {
		vec3 p = ro + rd * t;
		if (t > FAR || (p.y > 620.0 && rd.y > 0.0)) {
			break;
		}
		vec4 m = map(p);
		if (m.x < 0.0008 * t) {
			hit = vec4(t, m.yzw);
			break;
		}
		t += max(m.x * 0.9, 0.0012 * t);
	}
	vec3 col = sky(rd);
	vec3 moon = normalize(vec3(0.4, 0.5, -0.6));
	float dist = hit.x > 0.0 ? hit.x : FAR;
	if (hit.x > 0.0) {
		vec3 p = ro + rd * hit.x;
		vec3 n = normal_at(p, hit.x);
		vec3 amb = lin(vec3(0.12, 0.16, 0.19)) * (0.35 + 0.25 * n.y);
		// City glow from below lights the undersides.
		vec3 glow = lin(vec3(0.2, 0.26, 0.28)) * max(-n.y, 0.0) * 0.6;
		vec3 c;
		if (hit.y < 0.5) {
			// Wet street far below: dark, catching the sky and the towers' glow.
			c = lin(vec3(0.03, 0.035, 0.04)) + lin(vec3(0.16, 0.22, 0.24)) * 0.15 * fbm2(p.xz * 0.05, 3);
			// Traffic: a few streaks of head and tail lights down the avenue.
			float lane = step(0.97, fract(p.x / 9.0)) * step(0.85, hash12(vec2(floor(p.x / 9.0), floor(p.z / 60.0))));
			c += lin(vec3(1.0, 0.85, 0.6)) * lane * 0.22 * exp(-hit.x * 0.003);
		} else if (hit.y < 1.5) {
			vec3 wall = lin(vec3(0.05, 0.06, 0.075)) * (0.8 + 0.4 * hash12(vec2(hit.z, 3.0)));
			c = wall * (amb * 3.0 + glow + max(dot(n, moon), 0.0) * 0.08);
			if (abs(n.y) < 0.5) {
				c += windows(p, n, hit.z, hit.w, hit.x);
				// Some towers carry neon edge strips.
				if (hit.z > 0.72) {
					vec2 f = abs(n.x) > 0.5 ? p.zy : p.xy;
					float to_line = (0.5 - abs(fract(f.x / 18.0 + hit.z * 3.0) - 0.5)) * 18.0;
					float edge = smoothstep(0.7, 0.25, to_line);
					c += lin(vec3(0.4, 0.88, 0.92)) * edge * 1.4 * step(p.y, hit.w);
				}
			} else {
				// Rooftop beacons.
				c += lin(vec3(0.6, 0.9, 0.95)) * step(0.995, hash12(floor(p.xz * 0.4))) * 2.0;
			}
			// Antenna tips.
			c += lin(vec3(0.7, 0.95, 1.0)) * smoothstep(hit.w + 44.0, hit.w + 48.0, p.y) * 3.0;
		} else {
			// The Turbine: dark machined metal, rim lights in the world's cyan.
			vec3 q = p - TURBINE;
			q.xy = rot(0.12) * q.xy;
			float r = length(q.xy);
			float ang = atan(q.y, q.x);
			c = lin(vec3(0.07, 0.08, 0.09)) * (amb * 3.5 + glow * 1.5 + max(dot(n, moon), 0.0) * 0.2);
			c += lin(vec3(0.3, 0.38, 0.4)) * pow(1.0 - max(dot(n, -rd), 0.0), 3.0) * 0.25;
			float rim_band = smoothstep(14.0, 4.0, abs(r - TURBINE_R - 18.0)) * step(0.0, q.z + 5.0);
			float dots = step(0.55, fract(ang * 36.0 / 6.2832 * 3.0));
			c += lin(vec3(0.35, 0.9, 0.94)) * rim_band * dots * 2.2;
			// Hub: a ring of lights round its face, the core a dim glow.
			float hub_r = length(q.xy);
			c += lin(vec3(0.35, 0.9, 0.94)) * smoothstep(3.0, 0.0, abs(hub_r - 30.0)) * step(0.5, fract(ang * 12.0 / 6.2832)) * 1.6;
			c += lin(vec3(0.35, 0.9, 0.94)) * smoothstep(14.0, 4.0, hub_r) * 0.6;
		}
		col = c;
	}
	// Haze: thick near the street, lit by the city; the turbine stands in it.
	float ry = abs(rd.y) < 1e-4 ? 1e-4 : rd.y;
	float amount = 0.0022 / 0.012 * exp(-ro.y * 0.012) * (1.0 - exp(-dist * ry * 0.012)) / ry;
	float fog = 1.0 - exp(-amount - dist * 0.00018);
	vec3 haze = mix(lin(vec3(0.07, 0.1, 0.12)), lin(vec3(0.17, 0.23, 0.26)), exp(-max(rd.y, 0.0) * 8.0));
	col = mix(col, haze, fog);
	// Fine rain.
	vec2 rp = uv * vec2(420.0, 14.0) + vec2(uv.y * 14.0, 0.0);
	float rain = step(0.93, hash12(floor(rp))) * smoothstep(0.0, 0.5, fract(rp.y + hash12(floor(rp.xx)) * 5.0));
	col += lin(vec3(0.5, 0.6, 0.65)) * rain * 0.008;
	COLOR = vec4(finish(col * 1.15, uv), 1.0);
}
