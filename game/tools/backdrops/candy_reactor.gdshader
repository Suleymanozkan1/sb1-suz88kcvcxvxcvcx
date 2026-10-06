// Candy Reactor backdrop bake: sugar-glazed gumdrop hills at dusk, giant
// swirl lollipops and squat stacked macaron towers (wide, flat tiers: no tall
// round-topped columns), cotton-candy clouds, and far ahead
// the reactor: a giant frosted ring standing on its edge with warm energy
// glowing in its hole.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 12.0, 0.0);
const float CELL = 90.0;
const vec3 REACTOR = vec3(30.0, 300.0, -1800.0);

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 key_dir() {
	return normalize(vec3(0.55, 0.35, -0.6));
}

float ground_h(vec2 xz) {
	float hills = fbm2(xz * 0.0045, 3) * 120.0 * smoothstep(30.0, 200.0, abs(xz.x));
	float far = fbm2(xz * 0.002 + 5.0, 3) * 160.0 * smoothstep(500.0, 1100.0, -xz.y);
	return hills + far - 20.0;
}

float sd_torus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

// Props per cell: lollipop (disc on a stick), macaron stack or gumdrop.
// .x distance, .y material, .z kind seed, .w local radius / height info.
vec4 props(vec3 p) {
	vec2 cell = floor(p.xz / CELL);
	vec2 centre = (cell + 0.5) * CELL;
	float seed = hash12(cell);
	vec4 best = vec4(CELL * 0.35, 0.0, 0.0, 0.0);
	if (abs(centre.x) > 60.0 && centre.y < -40.0 && seed < 0.55) {
		vec2 j = (hash22(cell + 1.0) - 0.5) * CELL * 0.3;
		vec3 q = p - vec3(centre.x + j.x, ground_h(centre) - 4.0, centre.y + j.y);
		float kind = fract(seed * 7.13);
		if (kind < 0.45) {
			float h = 60.0 + seed * 80.0;
			float r = 18.0 + seed * 16.0;
			float stick = sdf_cylinder(q - vec3(0.0, h * 0.5, 0.0), 1.8, h * 0.5);
			vec3 dq = q - vec3(0.0, h, 0.0);
			float disc = max(length(dq.xy) - r, abs(dq.z) - 3.5) - 1.0;
			best = stick < disc ? vec4(stick, 1.0, seed, 0.0) : vec4(disc * 0.9, 2.0, seed, r);
		} else if (kind < 0.75) {
			// Four flattened macarons, each narrower than the one below.
			float r0 = 16.0 + seed * 9.0;
			float stack = 1e5;
			float y = 0.0;
			for (int k = 0; k < 4; k++) {
				float r = r0 * (1.0 - 0.17 * float(k));
				float half_h = r * 0.4;
				vec3 tq = q - vec3(0.0, y + half_h, 0.0);
				stack = min(stack, (length(tq * vec3(1.0, 2.5, 1.0)) - r) * 0.4);
				y += half_h * 1.85;
			}
			best = vec4(stack, 3.0, seed, r0);
		} else {
			float r = 22.0 + seed * 18.0;
			float drop = length(q * vec3(1.0, 1.15, 1.0)) - r;
			best = vec4(drop / 1.15, 4.0, seed, r);
		}
	}
	// The reactor ring.
	vec3 rq = p - REACTOR;
	rq = rq.xzy;
	float ring = sd_torus(rq, vec2(170.0, 55.0));
	if (ring < best.x) {
		best = vec4(ring, 5.0, 0.0, 0.0);
	}
	return best;
}

vec4 map(vec3 p) {
	float g = (p.y - ground_h(p.xz)) * 0.6;
	vec4 pr = props(p);
	return g < pr.x ? vec4(g, 0.0, 0.0, 0.0) : pr;
}

vec3 normal_at(vec3 p, float t) {
	float e = 0.02 + t * 0.001;
	vec2 k = vec2(1.0, -1.0);
	return normalize(
		k.xyy * map(p + k.xyy * e).x + k.yyx * map(p + k.yyx * e).x + k.yxy * map(p + k.yxy * e).x
		+ k.xxx * map(p + k.xxx * e).x
	);
}

vec3 sky(vec3 rd) {
	float h = max(rd.y, 0.0);
	vec3 col = mix(lin(vec3(0.94, 0.6, 0.68)), lin(vec3(0.13, 0.08, 0.2)), pow(smoothstep(0.0, 0.7, h), 0.5));
	col = mix(col, lin(vec3(1.0, 0.8, 0.6)), pow(max(dot(rd, key_dir()), 0.0), 6.0) * 0.5 * (1.0 - h));
	col += star_field(rd, 0.08, 260.0) * smoothstep(0.25, 0.6, rd.y) * 0.7;
	// Cotton-candy clouds: puffy, lit pink-gold toward the low sun, lilac in shade.
	vec2 cp = rd.xz / max(rd.y + 0.08, 0.05);
	float puff = fbm2(cp * 0.9 + vec2(2.0, 0.0), 6);
	float cl = smoothstep(0.5, 0.68, puff) * smoothstep(0.0, 0.1, rd.y) * (1.0 - smoothstep(0.35, 0.7, rd.y));
	float edge = smoothstep(0.68, 0.5, puff);
	vec3 cloud = mix(lin(vec3(0.55, 0.36, 0.55)), lin(vec3(1.0, 0.7, 0.72)), 0.4 + 0.6 * pow(max(dot(rd, key_dir()), 0.0), 2.0));
	cloud += lin(vec3(1.0, 0.85, 0.7)) * edge * 0.25;
	return mix(col, cloud, cl * 0.9);
}

vec3 lollipop(vec3 p, vec4 info, vec3 n) {
	vec2 cell = floor(p.xz / CELL);
	vec2 centre = (cell + 0.5) * CELL;
	vec2 j = (hash22(cell + 1.0) - 0.5) * CELL * 0.3;
	float h = 60.0 + info.z * 80.0;
	vec2 d = p.xy - vec2(centre.x + j.x, ground_h(centre) - 4.0 + h);
	float ang = atan(d.y, d.x);
	float r = length(d) / info.w;
	float swirl = fract(ang / 6.2832 * 3.0 + r * 2.2);
	vec3 a = lin(vec3(1.0, 0.55, 0.75));
	vec3 b = lin(vec3(0.98, 0.94, 0.9));
	vec3 c = info.z > 0.5 ? lin(vec3(0.55, 0.85, 0.8)) : lin(vec3(1.0, 0.85, 0.45));
	return swirl < 0.33 ? a : (swirl < 0.66 ? b : c);
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	float t = 0.5;
	vec4 hit = vec4(-1.0);
	for (int i = 0; i < 480; i++) {
		vec3 p = ro + rd * t;
		if (t > 3500.0 || (p.y > 500.0 && rd.y > 0.0)) {
			break;
		}
		vec4 m = map(p);
		if (m.x < 0.001 * t) {
			hit = vec4(t, m.yzw);
			break;
		}
		t += max(m.x, 0.0015 * t);
	}
	vec3 col = sky(rd);
	vec3 l = key_dir();
	if (hit.x > 0.0) {
		vec3 p = ro + rd * hit.x;
		vec3 n = normal_at(p, hit.x);
		float dif = max(dot(n, l), 0.0);
		vec3 sun = lin(vec3(1.0, 0.8, 0.7)) * 1.5;
		vec3 amb = lin(vec3(0.5, 0.36, 0.55)) * (0.45 + 0.35 * n.y);
		vec3 alb;
		float gloss = 0.5;
		vec3 emit = vec3(0.0);
		if (hit.y < 0.5) {
			// Glazed hills in soft bands of mint, rose and lilac.
			float band = fract(p.y * 0.018 + fbm2(p.xz * 0.01, 3) * 0.8);
			alb = band < 0.33 ? lin(vec3(0.62, 0.85, 0.78)) : (band < 0.66 ? lin(vec3(0.95, 0.68, 0.78)) : lin(vec3(0.76, 0.66, 0.92)));
			alb *= 0.75;
			// Sprinkles.
			vec2 sc = floor(p.xz * 2.2);
			float sp = step(0.965, hash12(sc));
			alb = mix(alb, mix(lin(vec3(1.0, 0.9, 0.5)), lin(vec3(0.5, 0.8, 1.0)), hash12(sc + 3.0)), sp * 0.8);
			gloss = 0.25;
		} else if (hit.y < 1.5) {
			alb = lin(vec3(0.95, 0.92, 0.88));
		} else if (hit.y < 2.5) {
			alb = lollipop(p, hit, n);
			gloss = 0.9;
		} else if (hit.y < 3.5) {
			// Macaron shells in pastel tiers with a cream filling at each waist.
			float tier = floor(p.y / 13.0 + hit.z * 7.0);
			float pick = fract(tier * 0.37);
			alb = pick < 0.25 ? lin(vec3(0.95, 0.68, 0.78)) : (pick < 0.5 ? lin(vec3(0.66, 0.86, 0.76))
				: (pick < 0.75 ? lin(vec3(0.78, 0.7, 0.94)) : lin(vec3(0.98, 0.9, 0.62))));
			alb = mix(alb, lin(vec3(0.98, 0.95, 0.9)), smoothstep(0.16, 0.06, abs(n.y)));
			gloss = 0.4;
		} else if (hit.y < 4.5) {
			// Translucent gumdrops glowing from within.
			alb = hit.z > 0.5 ? lin(vec3(0.5, 0.85, 0.6)) : lin(vec3(0.95, 0.55, 0.7));
			emit = alb * 0.35 * pow(1.0 - max(dot(n, -rd), 0.0), 1.5);
			gloss = 1.0;
		} else {
			// The reactor: frosted on top with sprinkles, glowing on its inner rim.
			vec3 rq = (p - REACTOR).xzy;
			vec2 tq = vec2(length(rq.xz) - 170.0, rq.y);
			float frost = smoothstep(-10.0, 15.0, tq.y + noise2(rq.xz * 0.05) * 12.0);
			alb = mix(lin(vec3(0.75, 0.5, 0.32)), lin(vec3(0.98, 0.7, 0.85)), frost);
			float sp = step(0.9, hash13(floor(p * 0.35))) * frost;
			alb = mix(alb, lin(vec3(0.5, 0.9, 1.0)), sp);
			float inner = smoothstep(10.0, -40.0, tq.x);
			emit = lin(vec3(1.0, 0.82, 0.48)) * inner * 1.6;
			gloss = 0.6;
		}
		vec3 c = alb * (dif * sun + amb) + emit;
		vec3 hv = normalize(l - rd);
		c += sun * pow(max(dot(n, hv), 0.0), 60.0) * gloss * 0.8;
		c += lin(vec3(1.0, 0.75, 0.8)) * pow(1.0 - max(dot(n, -rd), 0.0), 4.0) * 0.25;
		float fog = 1.0 - exp(-hit.x * 0.0006);
		vec3 hz = mix(lin(vec3(0.5, 0.32, 0.45)), lin(vec3(0.95, 0.66, 0.6)), pow(max(dot(rd, l), 0.0), 4.0));
		col = mix(c, hz, fog);
	}
	// Energy glowing in the reactor's hole and around it.
	vec3 rdir = normalize(REACTOR - ro);
	col += lin(vec3(1.0, 0.8, 0.5)) * (pow(max(dot(rd, rdir), 0.0), 2500.0) * 1.2 + pow(max(dot(rd, rdir), 0.0), 120.0) * 0.15);
	COLOR = vec4(finish(col * 0.7, uv), 1.0);
}
