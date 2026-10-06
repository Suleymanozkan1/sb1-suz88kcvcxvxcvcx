// Cyber Garden backdrop bake: a night forest of giant umbrella trees with
// glowing circuit veins up their trunks and bioluminescent lights under their
// canopies, a vast world tree far ahead, layered mist, fireflies, a pale moon.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 9.0, 0.0);
const float CELL = 70.0;
const vec3 WORLD_TREE = vec3(-40.0, 0.0, -1500.0);

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 moon_dir() {
	return dir_from(15.0, 14.0);
}

float ground_h(vec2 xz) {
	return terrain_fbm(xz * 0.008, 5) * 18.0 * smoothstep(10.0, 80.0, abs(xz.x)) - 2.0;
}

// One tree in local space (trunk base at the origin): .x distance,
// .y part (0 trunk, 1 canopy), .z the trunk's height fraction.
vec3 tree(vec3 q, float h, float r, float spread, float seed) {
	float bend = sin(q.y / h * 2.2 + seed * 6.0) * h * 0.04;
	vec3 tq = q - vec3(bend, 0.0, 0.0);
	float taper = mix(1.25, 0.6, clamp(tq.y / h, 0.0, 1.0));
	float trunk = max(length(tq.xz) - r * taper, max(tq.y - h, -tq.y - 8.0)) * 0.8;
	vec3 cq = q - vec3(bend * 1.5, h, 0.0);
	float canopy = length(cq * vec3(1.0, 2.6, 1.0)) - spread;
	canopy = canopy / 2.6 + (fbm3(q * 0.08 + seed * 13.0, 4) - 0.5) * spread * 0.25;
	// Branches flaring into the canopy.
	float branch = max(length(tq.xz) - r * 2.4 * smoothstep(h * 0.75, h, tq.y), abs(tq.y - h * 0.92) - h * 0.1);
	trunk = min(trunk, branch);
	return canopy < trunk ? vec3(canopy, 1.0, 1.0) : vec3(trunk, 0.0, clamp(tq.y / h, 0.0, 1.0));
}

vec4 trees(vec3 p) {
	vec2 cell = floor(p.xz / CELL);
	vec2 centre = (cell + 0.5) * CELL;
	float seed = hash12(cell);
	vec4 best = vec4(1e5, 0.0, 0.0, 0.0);
	if (abs(centre.x) > 40.0 && centre.y < -20.0 && seed < 0.75) {
		vec2 jitter = (hash22(cell + 2.0) - 0.5) * CELL * 0.35;
		float h = 70.0 + seed * 90.0;
		float r = 2.5 + seed * 2.5;
		float spread = 20.0 + seed * 14.0;
		vec3 t = tree(p - vec3(centre.x + jitter.x, ground_h(centre) - 2.0, centre.y + jitter.y), h, r, spread, seed);
		best = vec4(t, seed);
	}
	// The world tree.
	vec3 w = tree(p - WORLD_TREE, 520.0, 34.0, 300.0, 0.4);
	if (w.x < best.x) {
		best = vec4(w, 0.4);
	}
	return best;
}

vec4 map(vec3 p) {
	float g = (p.y - ground_h(p.xz)) * 0.6;
	vec4 t = trees(p);
	// Domain repetition can only see its own cell: keep steps short near cell edges.
	t.x = min(t.x, CELL * 0.35);
	return g < t.x ? vec4(g, -1.0, 0.0, 0.0) : t;
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
	vec3 col = mix(lin(vec3(0.08, 0.14, 0.13)), lin(vec3(0.012, 0.025, 0.03)), smoothstep(-0.02, 0.55, rd.y));
	col += star_field(rd, 0.1, 280.0) * smoothstep(0.1, 0.4, rd.y) * 0.8;
	vec3 md = moon_dir();
	float mu = max(dot(rd, md), 0.0);
	col += lin(vec3(0.6, 0.8, 0.7)) * (pow(mu, 600.0) * 0.4 + pow(mu, 40.0) * 0.08);
	float disc = smoothstep(0.99945, 0.99952, mu);
	vec3 tangent = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec2 dp = vec2(dot(rd, tangent), dot(rd, cross(tangent, md))) * 40.0;
	float maria = smoothstep(0.45, 0.7, fbm2(dp * 0.15 + 3.0, 5));
	col = mix(col, lin(vec3(0.86, 0.95, 0.88)) * (1.0 - maria * 0.3) * 2.0, disc);
	return col;
}

vec3 mist(vec3 col, vec3 rd, float t, float y) {
	float layer = exp(-max(y, 0.0) * 0.012);
	float f = 1.0 - exp(-t * (0.0009 + 0.002 * layer));
	vec3 m = mix(lin(vec3(0.06, 0.12, 0.11)), lin(vec3(0.13, 0.24, 0.21)), layer * 0.6);
	m += lin(vec3(0.3, 0.5, 0.4)) * pow(max(dot(rd, moon_dir()), 0.0), 8.0) * 0.4;
	return mix(col, m, f);
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	float t = 0.5;
	vec4 hit = vec4(-1.0);
	for (int i = 0; i < 520; i++) {
		vec3 p = ro + rd * t;
		if (t > 3500.0 || (p.y > 900.0 && rd.y > 0.0)) {
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
	vec3 md = moon_dir();
	if (hit.x > 0.0) {
		vec3 p = ro + rd * hit.x;
		vec3 n = normal_at(p, hit.x);
		float dif = max(dot(n, md), 0.0);
		vec3 moon = lin(vec3(0.7, 0.85, 0.78)) * 0.5;
		vec3 amb = lin(vec3(0.1, 0.2, 0.17)) * (0.4 + 0.4 * n.y);
		vec3 glow_col = lin(vec3(0.45, 1.0, 0.75));
		vec3 c;
		if (hit.y < -0.5) {
			// Moss with glowing patches.
			vec3 alb = mix(lin(vec3(0.04, 0.07, 0.05)), lin(vec3(0.08, 0.12, 0.08)), fbm2(p.xz * 0.2, 4));
			c = alb * (dif * moon + amb);
			float patch = smoothstep(0.68, 0.76, fbm2(p.xz * 0.05, 5));
			c += glow_col * patch * 0.02;
			c += glow_col * step(0.975, hash12(floor(p.xz * 1.5))) * smoothstep(0.55, 0.7, fbm2(p.xz * 0.03, 3)) * 0.3;
		} else if (hit.y < 0.5) {
			// Bark with circuit veins climbing it.
			vec3 alb = lin(vec3(0.08, 0.08, 0.075)) * (0.7 + 0.3 * noise2(vec2(atan(n.x, n.z) * 6.0, p.y * 0.3)));
			c = alb * (dif * moon + amb);
			float ang = atan(n.x, n.z);
			float vein = smoothstep(0.025, 0.008, abs(fract(ang * 1.9 + noise2(vec2(p.y * 0.05, hit.w * 9.0)) * 1.5) - 0.5));
			float pulse = smoothstep(0.3, 0.9, noise2(vec2(p.y * 0.08, ang * 3.0 + hit.w * 20.0)));
			c += glow_col * vein * pulse * 1.4 * (0.4 + hit.z);
		} else {
			// Canopy: dark foliage above, a field of lights underneath.
			vec3 alb = mix(lin(vec3(0.05, 0.09, 0.07)), lin(vec3(0.1, 0.16, 0.12)), fbm3(p * 0.2, 3));
			c = alb * (dif * moon * 1.4 + amb);
			float under = smoothstep(0.1, -0.5, n.y);
			vec3 cell = floor(p * 0.9);
			float dots = step(0.9, hash13(cell)) * under;
			vec3 tint = hit.w > 0.72 ? lin(vec3(0.82, 0.6, 1.0)) : glow_col;
			// Far away the lights merge into a soft glow instead of sparkling noise.
			float far_soft = smoothstep(300.0, 1200.0, hit.x);
			c += tint * (dots * 1.8 * (1.0 - far_soft * 0.75) + under * (0.08 + 0.35 * far_soft));
		}
		col = mist(c, rd, hit.x, p.y);
	} else {
		col = mist(col, rd, 2500.0, 2500.0 * rd.y);
	}
	// Fireflies.
	vec2 sph = vec2(atan(rd.x, -rd.z), asin(rd.y)) * 110.0;
	vec2 id = floor(sph);
	vec2 f = fract(sph) - 0.5 - (hash22(id) - 0.5) * 0.7;
	float fly = step(0.988, hash12(id + 9.0)) * exp(-dot(f, f) * 90.0);
	col += lin(vec3(0.7, 1.0, 0.5)) * fly * 1.5 * smoothstep(0.35, -0.05, rd.y);
	COLOR = vec4(finish(col, uv), 1.0);
}
