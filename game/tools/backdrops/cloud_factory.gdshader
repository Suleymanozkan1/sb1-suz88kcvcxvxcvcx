// Cloud Factory backdrop bake: above a sunlit sea of clouds, giant factory
// stacks rise out of the cloud tops and pour fresh cloud into the sky; a few
// cumulus towers billow up between them. Bright and soft, low contrast.
shader_type canvas_item;
render_mode unshaded;

#include "res://tools/backdrops/bake_common.gdshaderinc"

const vec3 CAM = vec3(0.0, 110.0, 0.0);
const float CLOUD_BOTTOM = -60.0;
const float CLOUD_TOP = 760.0;

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 sun_dir() {
	return dir_from(-10.0, 26.0);
}

// Stacks: base centre (x, z), radius, height above the cloud deck.
const vec4 STACKS[6] = vec4[](
	vec4(-210.0, -900.0, 22.0, 330.0), vec4(-120.0, -1150.0, 26.0, 400.0), vec4(160.0, -820.0, 18.0, 260.0),
	vec4(300.0, -1300.0, 30.0, 420.0), vec4(40.0, -1800.0, 34.0, 480.0), vec4(-420.0, -1600.0, 28.0, 360.0)
);

float stacks(vec3 p, out float band) {
	float d = 1e5;
	band = 0.0;
	for (int i = 0; i < 6; i++) {
		vec4 s = STACKS[i];
		vec3 q = p - vec3(s.x, 0.0, s.y);
		float taper = 1.0 - clamp(q.y / s.w, 0.0, 1.0) * 0.25;
		float c = max(length(q.xz) - s.z * taper, abs(q.y - s.w * 0.5 + 40.0) - s.w * 0.5 - 40.0);
		// A lip at the top.
		c = min(c, max(length(q.xz) - s.z * 0.85, abs(q.y - s.w) - 6.0));
		if (c < d) {
			d = c;
			float top = (s.w - q.y) / s.w;
			band = step(top, 0.14) * step(0.5, fract(q.y / 18.0));
		}
	}
	return d;
}

float cloud_density(vec3 p) {
	// The deck: puffy tops rising and falling; a few towering cumulus.
	float tower = smoothstep(0.5, 0.75, fbm2(p.xz * 0.0013 + 4.0, 3));
	float top = 20.0 + fbm2(p.xz * 0.004, 4) * 60.0 + tower * 230.0;
	// Three cumulus towers framing the stacks.
	top += 300.0 * exp(-pow(length(p.xz - vec2(-640.0, -1500.0)) / 260.0, 2.0));
	top += 240.0 * exp(-pow(length(p.xz - vec2(560.0, -1050.0)) / 220.0, 2.0));
	top += 380.0 * exp(-pow(length(p.xz - vec2(250.0, -2600.0)) / 380.0, 2.0));
	float h = (p.y - CLOUD_BOTTOM) / (top - CLOUD_BOTTOM);
	float shape = 1.0 - smoothstep(0.45, 1.0, h);
	float n = fbm3(p * vec3(0.008, 0.011, 0.008), 6);
	float billow = 1.0 - abs(fbm3(p * 0.03 + 7.0, 4) * 2.0 - 1.0);
	float d = shape * 1.3 - 0.6 + (n - 0.5) * 1.5 + billow * 0.25;
	// Fresh cloud poured out of the stacks, drifting downwind.
	for (int i = 0; i < 6; i++) {
		vec4 s = STACKS[i];
		vec3 q = p - vec3(s.x, s.w, s.y);
		float up = max(q.y, 0.0);
		vec2 off = vec2(up * 0.9, up * 0.25);
		float r = s.z * 0.9 + up * 0.45;
		float plume = 1.0 - length(vec2(q.x - off.x, q.z - off.y)) / r;
		plume *= smoothstep(-10.0, 10.0, q.y) * (1.0 - smoothstep(120.0, 260.0, q.y));
		d = max(d, plume * 1.4 - 0.45 + (n - 0.5) * 1.2 + billow * 0.2);
	}
	return clamp(d, 0.0, 1.0);
}

vec3 sky(vec3 rd) {
	vec3 sd = sun_dir();
	float mu = max(dot(rd, sd), 0.0);
	vec3 col = mix(lin(vec3(0.86, 0.89, 0.93)), lin(vec3(0.4, 0.54, 0.76)), pow(smoothstep(-0.05, 0.7, rd.y), 0.7));
	col += lin(vec3(1.0, 0.96, 0.88)) * (pow(mu, 8.0) * 0.35 + pow(mu, 120.0) * 0.8);
	col += lin(vec3(1.0, 0.98, 0.94)) * smoothstep(0.9996, 0.99968, mu) * 8.0;
	return col;
}

void fragment() {
	vec2 uv = image_uv(UV);
	vec3 rd = view_dir(uv);
	vec3 ro = CAM;
	vec3 sd = sun_dir();
	vec3 col = sky(rd);
	// Stacks first (solid), then clouds in front of them.
	float t = 1.0;
	float band = 0.0;
	bool hit = false;
	for (int i = 0; i < 300; i++) {
		vec3 p = ro + rd * t;
		float d = stacks(p, band);
		if (d < 0.001 * t) {
			hit = true;
			break;
		}
		t += d;
		if (t > 4000.0) {
			break;
		}
	}
	float tmax = hit ? t : 6000.0;
	if (hit) {
		vec3 p = ro + rd * t;
		vec2 e = vec2(0.05, 0.0);
		float b;
		vec3 n = normalize(vec3(
			stacks(p + e.xyy, b) - stacks(p - e.xyy, b), stacks(p + e.yxy, b) - stacks(p - e.yxy, b),
			stacks(p + e.yyx, b) - stacks(p - e.yyx, b)
		));
		float dif = max(dot(n, sd), 0.0);
		vec3 alb = mix(lin(vec3(0.3, 0.32, 0.36)), lin(vec3(0.85, 0.86, 0.88)), band);
		alb *= 0.85 + 0.15 * noise2(vec2(atan(n.x, n.z) * 20.0, p.y * 0.1));
		vec3 c = alb * (dif * lin(vec3(1.0, 0.96, 0.9)) * 2.0 + lin(vec3(0.55, 0.62, 0.75)) * (0.5 + 0.3 * n.y));
		float fog = 1.0 - exp(-t * 0.00025);
		col = mix(c, sky(normalize(vec3(rd.x, max(rd.y, 0.0), rd.z))), fog);
	}
	// Clouds: march the deck slab with a short shadow march toward the sun.
	float t_in = 0.0;
	float t_out = 0.0;
	if (rd.y < 0.0) {
		t_in = max((CLOUD_TOP - ro.y) / rd.y, 0.0);
		t_out = (CLOUD_BOTTOM - ro.y) / rd.y;
	} else {
		t_in = 0.0;
		t_out = (CLOUD_TOP - ro.y) / max(rd.y, 1e-3);
	}
	t_out = min(t_out, min(tmax, 7000.0));
	vec4 acc = vec4(0.0);
	float dt = clamp((t_out - t_in) / 160.0, 4.0, 40.0);
	float s = t_in + dt * hash12(uv * 913.0);
	for (int i = 0; i < 260; i++) {
		if (s > t_out || acc.a > 0.985) {
			break;
		}
		vec3 p = ro + rd * s;
		float den = cloud_density(p);
		if (den > 0.01) {
			float shadow = 0.0;
			for (int k = 1; k <= 4; k++) {
				shadow += cloud_density(p + sd * float(k) * 18.0);
			}
			float trans = exp(-shadow * 1.7);
			float powder = 1.0 - exp(-den * 4.0);
			float height = clamp((p.y - CLOUD_BOTTOM) / 260.0, 0.0, 1.0);
			vec3 lit = lin(vec3(1.0, 0.97, 0.92)) * 2.6 * trans * powder + lin(vec3(0.46, 0.54, 0.72)) * (0.22 + 0.45 * height);
			float fog = 1.0 - exp(-s * 0.00045);
			lit = mix(lit, sky(normalize(vec3(rd.x, 0.02, rd.z))), fog);
			float a = 1.0 - exp(-den * dt * 0.035);
			acc.rgb += (1.0 - acc.a) * a * lit;
			acc.a += (1.0 - acc.a) * a;
		}
		s += dt;
	}
	col = col * (1.0 - acc.a) + acc.rgb;
	COLOR = vec4(finish(col * 0.8, uv), 1.0);
}
