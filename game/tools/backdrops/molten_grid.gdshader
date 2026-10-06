// Molten Grid backdrop bake: a basalt plain cut by glowing lava channels,
// crusted plates floating on them, a volcano ahead with lava running down its
// flanks and a fire-lit ash column, heavy clouds lit orange from below, embers.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 10.0, 0.0);
const float FAR = 2600.0;
const vec2 VOLCANO = vec2(150.0, -1500.0);

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

// Lava streaks running down the volcano's flanks (0..1).
float volcano_streaks(vec2 xz) {
	vec2 v = xz - VOLCANO;
	float ang = atan(v.x, v.y);
	return smoothstep(0.75, 0.95, noise2(vec2(ang * 9.0, length(v) * 0.004))) * smoothstep(420.0, 150.0, length(v));
}

// How much a ground point is lava (1) or rock (0).
float lava_mask(vec2 xz) {
	vec2 w = xz + vec2(fbm2(xz * 0.006, 4), fbm2(xz * 0.006 + 3.0, 4)) * 120.0;
	float f = fbm2(w * 0.009, 5);
	float channels = max(smoothstep(0.025, 0.0, abs(f - 0.5)), smoothstep(0.018, 0.0, abs(f - 0.38)) * 0.8);
	// Lava streaks down the volcano's flanks.
	vec2 v = xz - VOLCANO;
	float ang = atan(v.x, v.y);
	float streak = smoothstep(0.75, 0.95, noise2(vec2(ang * 9.0, length(v) * 0.004))) * smoothstep(420.0, 150.0, length(v));
	return max(channels * smoothstep(15.0, 70.0, -xz.y + abs(xz.x) * 0.5), streak);
}

float volcano(vec2 xz) {
	float r = length(xz - VOLCANO);
	float cone = max(380.0 - r * 0.62, 0.0);
	float crater = smoothstep(90.0, 40.0, r) * 70.0;
	return cone - crater + terrain_fbm(xz * 0.01, 5) * 30.0 * smoothstep(0.0, 200.0, cone);
}

float ground_h(vec2 xz, int octaves) {
	float base = terrain_fbm(xz * 0.006, octaves) * 40.0 * smoothstep(40.0, 200.0, abs(xz.x));
	float ridges = ridged2(xz * 0.0025 + 4.0, 5) * 140.0 * smoothstep(500.0, 1200.0, -xz.y);
	float h = max(base + ridges, volcano(xz)) - 3.0;
	return h - lava_mask(xz) * 3.0;
}

float map(vec3 p, float t) {
	int oct = t < 200.0 ? 8 : 5;
	return (p.y - ground_h(p.xz, oct)) * 0.45;
}

vec3 normal_at(vec3 p, float t) {
	float e = 0.04 + t * 0.0012;
	int oct = t < 200.0 ? 9 : 6;
	float h = ground_h(p.xz, oct);
	return normalize(vec3(h - ground_h(p.xz + vec2(e, 0.0), oct), e, h - ground_h(p.xz + vec2(0.0, e), oct)));
}

vec3 lava_color(vec2 xz, float heat) {
	vec2 v = voronoi2(xz * 0.08);
	float crust = smoothstep(0.05, 0.22, v.y - v.x);
	vec3 hot = mix(lin(vec3(1.0, 0.38, 0.08)), lin(vec3(1.0, 0.75, 0.32)), heat);
	return mix(hot * 4.0, lin(vec3(0.08, 0.04, 0.03)) + hot * 0.15, crust * 0.85);
}

// Ash clouds and the eruption column: lit orange from below, dark above.
vec4 clouds(vec3 ro, vec3 rd, float tmax) {
	vec4 acc = vec4(0.0);
	if (rd.y <= 0.0) {
		return acc;
	}
	float t0 = (420.0 - ro.y) / rd.y;
	float t1 = (760.0 - ro.y) / rd.y;
	float dt = (t1 - t0) / 36.0;
	for (int i = 0; i < 36; i++) {
		float t = t0 + dt * (float(i) + 0.5);
		if (t > tmax || acc.a > 0.98) {
			break;
		}
		vec3 p = ro + rd * t;
		float den = fbm3(p * vec3(0.004, 0.009, 0.004) + vec3(0.0, 0.0, 2.0), 7) - 0.5;
		den = clamp(den * 4.0, 0.0, 1.0);
		float under = 1.0 - (p.y - 420.0) / 340.0;
		float glow = exp(-length(p.xz - VOLCANO) * 0.006);
		vec3 lit = mix(lin(vec3(0.07, 0.062, 0.064)), lin(vec3(0.8, 0.32, 0.12)), clamp(under * under * 0.02 + glow * 1.5, 0.0, 1.0));
		float a = den * 0.26;
		acc.rgb += (1.0 - acc.a) * a * lit;
		acc.a += (1.0 - acc.a) * a;
	}
	return acc;
}

vec4 ash_column(vec3 ro, vec3 rd, float tmax) {
	vec4 acc = vec4(0.0);
	float t0 = max(length(vec3(VOLCANO.x, 300.0, VOLCANO.y) - ro) - 350.0, 0.0);
	for (int i = 0; i < 60; i++) {
		float t = t0 + float(i) * 12.0;
		if (t > tmax || acc.a > 0.98) {
			break;
		}
		vec3 p = ro + rd * t;
		vec2 q = p.xz - VOLCANO - vec2((p.y - 300.0) * 0.35, 0.0);
		float up = p.y - 300.0;
		float r = 40.0 + max(up, 0.0) * 0.5;
		float shape = 1.0 - length(q) / r;
		if (shape < -0.3 || up < -20.0) {
			continue;
		}
		float den = clamp(shape * 1.3 + (fbm3(p * 0.012, 5) - 0.5) * 1.3, 0.0, 1.0) * 0.3;
		den *= smoothstep(-20.0, 20.0, up);
		vec3 lit = mix(lin(vec3(1.0, 0.42, 0.12)) * 1.6, lin(vec3(0.07, 0.05, 0.05)), smoothstep(0.0, 260.0, up));
		acc.rgb += (1.0 - acc.a) * den * lit;
		acc.a += (1.0 - acc.a) * den;
	}
	return acc;
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	vec3 col = mix(lin(vec3(0.15, 0.065, 0.045)), lin(vec3(0.025, 0.02, 0.022)), smoothstep(-0.02, 0.3, rd.y));
	// Fire glow on the horizon under the volcano.
	vec3 vdir = normalize(vec3(VOLCANO.x, 300.0, VOLCANO.y));
	col += lin(vec3(1.0, 0.4, 0.12)) * pow(max(dot(rd, vdir), 0.0), 30.0) * 0.35;
	float t = 0.5;
	bool hit = false;
	for (int i = 0; i < 520; i++) {
		vec3 p = ro + rd * t;
		if (t > FAR || (p.y > 420.0 && rd.y > 0.0)) {
			break;
		}
		float h = map(p, t);
		if (h < 0.0012 * t) {
			hit = true;
			break;
		}
		t += max(h, 0.002 * t);
	}
	float tmax = hit ? t : FAR * 2.0;
	if (hit) {
		vec3 p = ro + rd * t;
		vec3 n = normal_at(p, t);
		float lava = lava_mask(p.xz);
		vec3 rock = mix(lin(vec3(0.05, 0.045, 0.045)), lin(vec3(0.13, 0.11, 0.1)), fbm2(p.xz * 0.1, 4));
		// Lit by the lava around it (glow from below), the fiery sky and a dim key.
		vec3 key = lin(vec3(1.0, 0.6, 0.4)) * 0.35 * max(dot(n, normalize(vec3(0.4, 0.5, -0.8))), 0.0);
		vec3 amb = lin(vec3(0.5, 0.22, 0.12)) * (0.3 + 0.2 * n.y);
		vec3 glow = lin(vec3(1.0, 0.4, 0.12)) * (lava_mask(p.xz + n.xz * 6.0) + lava_mask(p.xz - n.xz * 6.0)) * 0.6;
		vec3 c = rock * (key + amb + glow);
		// Near channels stay dim: the bright lava belongs to the volcano, far from the course.
		// Only lava on the volcano burns bright; the plain's channels and any on
		// the ridges are crusted over and dim, so no lava shape in the
		// backdrop looks like the course's lava hazards.
		float on_volcano = smoothstep(650.0, 380.0, length(p.xz - VOLCANO));
		float bright = max(smoothstep(0.2, 0.6, volcano_streaks(p.xz)), on_volcano);
		float level = mix(0.18 * smoothstep(40.0, 0.0, p.y), 1.0, bright);
		c = mix(c, lava_color(p.xz, fbm2(p.xz * 0.02, 3)) * level, smoothstep(0.2, 0.7, lava) * mix(0.6, 1.0, bright));
		float fog = 1.0 - exp(-t * 0.0007);
		vec3 hz = mix(lin(vec3(0.2, 0.09, 0.06)), lin(vec3(0.5, 0.2, 0.08)), pow(max(dot(rd, vdir), 0.0), 8.0));
		col = mix(c, hz, fog);
	}
	vec4 ash = ash_column(ro, rd, tmax);
	col = col * (1.0 - ash.a) + ash.rgb;
	vec4 cl = clouds(ro, rd, tmax);
	col = col * (1.0 - cl.a) + cl.rgb;
	// Embers drifting up.
	vec2 sph = vec2(atan(rd.x, -rd.z), asin(rd.y)) * 140.0;
	vec2 id = floor(sph);
	vec2 f = fract(sph) - 0.5 - (hash22(id) - 0.5) * 0.7;
	float big = hash12(id + 5.0);
	float ember = step(0.993, hash12(id)) * exp(-dot(f * vec2(1.0, 0.45), f * vec2(1.0, 0.45)) * mix(140.0, 30.0, big * big));
	col += lin(vec3(1.0, 0.55, 0.2)) * ember * 1.6 * smoothstep(0.3, 0.0, rd.y);
	COLOR = vec4(finish(col * 1.1, uv), 1.0);
}
