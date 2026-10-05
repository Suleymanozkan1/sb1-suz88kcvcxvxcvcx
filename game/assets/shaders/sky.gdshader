// FLUX DROP sky: the world's backdrop (ART_DIRECTION §6, §7). A low-saturation
// gradient with the flux sink the core drops towards, and in front of it each
// world's own far scenery: a skyline on the horizon (city, crystal spires,
// volcanoes, chimneys, reef, giant fungi, ice peaks, dunes, floating rocks,
// candy hills), and above it nebula, clouds, aurora, a sun, moon or ringed
// planet, light rays and stars.
// Nothing here uses TIME: a time-driven sky re-bakes its radiance every frame.
// The soft additive layers (nebula, aurora, rays) are drawn in the
// half-resolution pass; clouds (they need a smooth coverage the half-resolution
// buffer cannot hold) and the sharp layers (skyline, body, stars) at full
// resolution. The radiance pass gets the gradient only (cheap on mobile).
// The gradient and sink are laid out in the camera's rest frame from the eye
// direction, so lean, shake and lane follow turn the view across them; the
// scenery is placed by azimuth and elevation (it sits at infinity).
shader_type sky;
render_mode use_half_res_pass;

uniform vec4 sky_top : source_color = vec4(0.055, 0.075, 0.125, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.105, 0.14, 0.21, 1.0);
uniform vec4 sink_color : source_color = vec4(0.27, 0.9, 0.94, 1.0);
uniform float sink_height = 0.6;
uniform float sink_strength = 1.0;
uniform float star_density = 0.0;
// World -> rest camera frame (CameraRig.rest_basis() inverted) and the tangents
// of the half field of view; tan_half 0 falls back to screen-locked layout.
uniform mat3 rest_view = mat3(1.0);
uniform vec2 tan_half = vec2(0.0);
// Far scenery (WorldTheme.SKYLINES order; 0 none). Skyline colours are dark
// silhouettes; the light colour marks windows, lava, glints, beacons.
uniform int skyline = 0;
uniform vec4 skyline_color : source_color = vec4(0.04, 0.05, 0.08, 1.0);
uniform vec4 skyline_light : source_color = vec4(0.6, 0.8, 0.9, 1.0);
uniform vec4 haze_color : source_color = vec4(0.08, 0.11, 0.16, 1.0);
uniform float nebula = 0.0;
uniform vec4 nebula_a : source_color = vec4(0.2, 0.15, 0.4, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.1, 0.25, 0.35, 1.0);
uniform float clouds = 0.0;
uniform vec4 cloud_color : source_color = vec4(0.9, 0.92, 0.95, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.5, 0.55, 0.62, 1.0);
uniform float aurora = 0.0;
uniform vec4 aurora_a : source_color = vec4(0.35, 0.8, 0.65, 1.0);
uniform vec4 aurora_b : source_color = vec4(0.4, 0.45, 0.85, 1.0);
// Light rays fanning from a direction (azimuth, elevation in radians).
uniform float rays = 0.0;
uniform vec2 ray_dir = vec2(0.0, 1.0);
uniform vec4 ray_color : source_color = vec4(0.8, 0.9, 0.95, 1.0);
// Celestial body: 0 none, 1 sun, 2 moon, 3 ringed planet; (azimuth,
// elevation, angular radius) in radians.
uniform int body_kind = 0;
uniform vec3 body = vec3(0.2, 0.3, 0.06);
uniform vec4 body_color : source_color = vec4(0.9, 0.9, 0.95, 1.0);
// Low quality and battery saver drop the soft layers.
uniform bool detail = true;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise2(p);
		p = p * 2.07 + vec2(5.2, 1.3);
		amp *= 0.5;
	}
	return v;
}

// Triangle wave 0..1 with peaks at integer + 0.5.
float tri(float x) {
	return 1.0 - abs(fract(x) - 0.5) * 2.0;
}

// Soft step across one pixel of elevation (aa: pixel size).
float below(float el, float h, float aa) {
	return 1.0 - smoothstep(h - aa, h + aa, el);
}

// --- Skylines: rgb colour and coverage (a) ---------------------------------------

vec4 sky_city(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		float x = az * mix(70.0, 46.0, fl) + fl * 31.0;
		float id = floor(x);
		float fx = fract(x);
		float h = mix(0.03, 0.04, fl) + mix(0.05, 0.08, fl) * pow(hash12(vec2(id, 3.1 + fl)), 2.0);
		if (hash12(vec2(id, 7.7 + fl)) > 0.85) {
			h += mix(0.04, 0.07, fl);
		}
		float w = 0.55 + 0.4 * hash12(vec2(id, 5.3 + fl));
		float inside = step(abs(fx - 0.5), w * 0.5) * below(el, h, aa);
		// A mast on the tallest towers.
		inside = max(inside, step(abs(fx - 0.5), 0.04) * below(el, h + 0.02, aa) * step(0.9, hash12(vec2(id, 9.1 + fl))));
		vec2 win = vec2(fx * 4.0, el * 130.0);
		float lit = step(0.78, hash12(floor(win) + vec2(id * 13.0, fl * 7.0)));
		lit *= step(0.3, fract(win.x)) * step(0.4, fract(win.y)) * step(el, h - 0.01);
		vec3 c = mix(skyline_color.rgb, haze_color.rgb, mix(0.55, 0.0, fl));
		c += skyline_light.rgb * lit * mix(0.25, 0.6, fl);
		o = mix(o, vec4(c, 1.0), inside);
	}
	return o;
}

// Crystal spires (pointed) or ice peaks (snow-capped), two layers.
vec4 sky_spires(float az, float el, float aa, bool ice) {
	vec4 o = vec4(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		float x = az * mix(16.0, 9.0, fl) + fl * 3.7;
		float id = floor(x);
		float fx = fract(x);
		float h = mix(0.05, 0.07, fl) + mix(0.06, 0.12, fl) * hash12(vec2(id, 1.9 + fl));
		float slope = ice ? mix(0.11, 0.16, fl) : mix(0.3, 0.42, fl);
		float top = h - abs(fx - 0.5) * slope * 2.0;
		float base = 0.02 + 0.015 * noise2(vec2(az * 30.0, fl));
		float hh = max(top, base);
		float inside = below(el, hh, aa);
		// Faceted light: the face turned to the key light is lighter.
		float face = fx < 0.5 ? 1.0 : 0.0;
		vec3 c = mix(skyline_color.rgb, haze_color.rgb, mix(0.5, 0.0, fl));
		c *= mix(0.8, 1.25, face);
		if (ice) {
			c = mix(c, skyline_light.rgb * 0.75, smoothstep(hh - 0.03, hh - 0.012, el) * step(base + 0.004, hh));
		} else {
			float edge = smoothstep(0.035, 0.0, abs(fx - 0.5)) * step(base + 0.004, hh);
			c += skyline_light.rgb * edge * 0.35 * smoothstep(hh - 0.08, hh, el);
		}
		o = mix(o, vec4(c, 1.0), inside);
	}
	return o;
}

vec4 sky_volcano(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	float hills = 0.025 + 0.02 * fbm2(vec2(az * 8.0, 2.0));
	o = mix(o, vec4(mix(skyline_color.rgb, haze_color.rgb, 0.45), 1.0), below(el, hills + 0.03, aa));
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float p = -0.42 + fi * 0.41 + (hash12(vec2(fi, 4.0)) - 0.5) * 0.12;
		float top = 0.1 + 0.07 * hash12(vec2(fi, 8.0));
		float crater = top - 0.012;
		float h = min(top - abs(az - p) * 0.55, crater);
		float inside = below(el, h, aa);
		// Lava runs down from the crater.
		float run = smoothstep(0.72, 0.95, noise2(vec2((az - p) * 140.0, el * 9.0 + fi * 11.0)));
		run *= smoothstep(crater - 0.09, crater - 0.01, el);
		vec3 c = skyline_color.rgb + skyline_light.rgb * run * 0.85;
		o = mix(o, vec4(c, 1.0), inside);
		// The crater glows into its own smoke.
		float d = (az - p) * 9.0;
		float plume = exp(-d * d) * smoothstep(crater - 0.004, crater + 0.03, el) * exp(-(el - crater) * 18.0);
		o.rgb += skyline_light.rgb * plume * 0.45 * (1.0 - inside);
		o.a = max(o.a, plume * 0.6);
	}
	return o;
}

vec4 sky_stacks(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	float plant = 0.03 + 0.012 * step(0.5, hash12(vec2(floor(az * 20.0), 2.0)));
	o = mix(o, vec4(skyline_color.rgb * 0.92, 1.0), below(el, plant, aa));
	float x = az * 14.0;
	float id = floor(x);
	float fx = fract(x);
	if (hash12(vec2(id, 1.0)) > 0.4) {
		float h = 0.08 + 0.1 * hash12(vec2(id, 2.0));
		float w = 0.08 + 0.05 * hash12(vec2(id, 3.0));
		float inside = step(abs(fx - 0.5), w) * below(el, h, aa);
		float band = step(0.5, fract(el * 55.0)) * step(h - 0.03, el);
		vec3 c = mix(skyline_color.rgb, skyline_light.rgb, band * 0.25);
		o = mix(o, vec4(c, 1.0), inside);
		// Steam rises from the stack and drifts.
		float rise = max(el - h, 0.0);
		float spread = 0.08 + rise * 6.0;
		float dx = (fx - 0.5 - rise * 3.0) / spread;
		float puff = fbm2(vec2(dx * 2.0 + id, rise * 40.0)) * exp(-dx * dx * 2.0) * exp(-rise * 14.0);
		puff = smoothstep(0.18, 0.5, puff) * step(h, el);
		o = mix(o, vec4(skyline_light.rgb, 1.0), puff * 0.85);
	}
	return o;
}

vec4 sky_reef(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	float rock = 0.03 + 0.04 * fbm2(vec2(az * 7.0, 1.0));
	float inside = below(el, rock, aa);
	float dots = step(0.985, hash12(floor(vec2(az * 260.0, el * 260.0))));
	o = mix(o, vec4(skyline_color.rgb + skyline_light.rgb * dots * 0.7, 1.0), inside);
	float x = az * 34.0;
	float id = floor(x);
	if (hash12(vec2(id, 6.0)) > 0.35) {
		float h = 0.08 + 0.16 * hash12(vec2(id, 7.0));
		float sway = sin(el * 40.0 + id * 2.3) * 0.12 * smoothstep(0.0, h, el);
		float strand = step(abs(fract(x) - 0.5 - sway), 0.07) * below(el, h, aa);
		float leaf = step(0.6, fract(el * 22.0 + id)) * step(abs(fract(x) - 0.5 - sway), 0.16) * below(el, h, aa);
		vec3 c = mix(skyline_color.rgb, haze_color.rgb, 0.3);
		float glow = step(0.93, hash12(vec2(id, floor(el * 30.0))));
		o = mix(o, vec4(c + skyline_light.rgb * glow * 0.5, 1.0), max(strand, leaf * 0.8));
	}
	return o;
}

vec4 sky_canopy(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	float bush = 0.035 + 0.025 * fbm2(vec2(az * 14.0, 3.0));
	o = mix(o, vec4(mix(skyline_color.rgb, haze_color.rgb, 0.25), 1.0), below(el, bush, aa));
	float x = az * 7.0;
	float id = floor(x);
	float fx = fract(x) - 0.5;
	if (hash12(vec2(id, 2.0)) > 0.3) {
		float h = 0.1 + 0.12 * hash12(vec2(id, 3.0));
		float lean = (hash12(vec2(id, 4.0)) - 0.5) * 0.6;
		float trunk = step(abs(fx - lean * (el / h)), 0.035 + 0.02 * (1.0 - el / h)) * below(el, h, aa);
		float cw = 0.3 + 0.15 * hash12(vec2(id, 5.0));
		vec2 q = vec2((fx - lean) / cw, (el - h) / 0.035);
		float cap = step(dot(q, q), 1.0) * step(-0.35, q.y);
		float spots = step(0.82, hash12(floor(vec2(fx * 40.0, el * 300.0) + id))) * cap;
		float rim = smoothstep(-0.35, -0.1, q.y) * (1.0 - smoothstep(-0.1, 0.1, q.y)) * cap;
		vec3 c = skyline_color.rgb + skyline_light.rgb * (spots * 0.6 + rim * 0.35);
		o = mix(o, vec4(c, 1.0), max(trunk, cap));
	}
	return o;
}

vec4 sky_dunes(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		float h = 0.025 + mix(0.02, 0.035, fl) * (0.5 + 0.5 * sin(az * mix(6.0, 4.0, fl) + fl * 2.0));
		h += 0.008 * sin(az * 23.0 + fl);
		float inside = below(el, h, aa);
		// Lit crests: the dune's top is lighter.
		float crest = smoothstep(h - 0.012, h, el);
		vec3 c = mix(skyline_color.rgb, haze_color.rgb, mix(0.45, 0.0, fl));
		c = mix(c, c * 1.6, crest * 0.6);
		o = mix(o, vec4(c, 1.0), inside);
	}
	// Reactor pylons with a beacon on top.
	float x = az * 9.0;
	float id = floor(x);
	if (hash12(vec2(id, 1.5)) > 0.55) {
		float h = 0.09 + 0.06 * hash12(vec2(id, 2.5));
		float fx = fract(x) - 0.5;
		float mast = step(abs(fx), 0.03) * below(el, h, aa);
		float arm = step(abs(fx), 0.14) * step(abs(el - h * 0.78), 0.003);
		float beacon = exp(-(fx * fx * 900.0 + (el - h) * (el - h) * 40000.0));
		o = mix(o, vec4(skyline_color.rgb, 1.0), max(mast, arm));
		o.rgb += skyline_light.rgb * beacon * 0.9;
		o.a = max(o.a, beacon);
	}
	return o;
}

vec4 sky_rocks(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	vec2 g = vec2(az * 7.0, el * 7.0);
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	if (hash12(id + 3.0) > 0.62 && el > 0.03) {
		vec2 c0 = (vec2(hash12(id + 5.0), hash12(id + 9.0)) - 0.5) * 0.4;
		vec2 q = f - c0;
		float ang = atan(q.y, q.x);
		float r = (0.12 + 0.12 * hash12(id + 1.0)) * (0.85 + 0.15 * noise2(vec2(ang * 3.0, id.x)));
		float inside = 1.0 - smoothstep(r - aa * 7.0, r + aa * 7.0, length(q));
		// Lit from the sink side (below and ahead).
		float lit = smoothstep(r * 0.5, r, length(q - vec2(0.0, r * 0.5)));
		vec3 c = skyline_color.rgb + skyline_light.rgb * lit * 0.4;
		o = mix(o, vec4(c, 1.0), inside);
	}
	return o;
}

vec4 sky_candy(float az, float el, float aa) {
	vec4 o = vec4(0.0);
	float h = 0.03 + 0.018 * (0.5 + 0.5 * sin(az * 9.0)) + 0.008 * sin(az * 27.0 + 1.0);
	o = mix(o, vec4(skyline_color.rgb, 1.0), below(el, h, aa));
	float x = az * 11.0;
	float id = floor(x);
	if (hash12(vec2(id, 2.2)) > 0.45) {
		float top = 0.07 + 0.08 * hash12(vec2(id, 3.3));
		float fx = fract(x) - 0.5;
		float stick = step(abs(fx), 0.025) * below(el, top, aa);
		vec2 q = vec2(fx / 0.28, (el - top) / 0.028);
		float rr = length(q);
		float disc = 1.0 - smoothstep(1.0 - aa * 30.0, 1.0 + aa * 30.0, rr);
		float swirl = step(0.5, fract(atan(q.y, q.x) / 6.2831 * 2.0 + rr * 1.6));
		vec3 c = mix(skyline_color.rgb, skyline_light.rgb, swirl * 0.7);
		o = mix(o, vec4(skyline_color.rgb, 1.0), stick);
		o = mix(o, vec4(c, 1.0), disc);
	}
	return o;
}

vec4 skyline_layer(float az, float el, float aa) {
	if (skyline == 1) {
		return sky_city(az, el, aa);
	} else if (skyline == 2) {
		return sky_spires(az, el, aa, false);
	} else if (skyline == 3) {
		return sky_volcano(az, el, aa);
	} else if (skyline == 4) {
		return sky_stacks(az, el, aa);
	} else if (skyline == 5) {
		return sky_reef(az, el, aa);
	} else if (skyline == 6) {
		return sky_canopy(az, el, aa);
	} else if (skyline == 7) {
		return sky_spires(az, el, aa, true);
	} else if (skyline == 8) {
		return sky_dunes(az, el, aa);
	} else if (skyline == 9) {
		return sky_rocks(az, el, aa);
	} else if (skyline == 10) {
		return sky_candy(az, el, aa);
	}
	return vec4(0.0);
}

// --- Soft layers (half resolution) -------------------------------------------------

vec3 soft_layers(float az, float el) {
	vec3 col = vec3(0.0);
	if (nebula > 0.0) {
		vec2 p = vec2(az, el) * 3.2;
		vec2 warp = vec2(fbm2(p + 3.1), fbm2(p + 8.7));
		float n = fbm2(p + warp * 1.8);
		// A broad band across the sky, like a galaxy seen edge-on.
		float band = exp(-pow((el - 0.28 + az * 0.35) * 3.2, 2.0));
		float m = smoothstep(0.35, 0.85, n) * (0.35 + 0.65 * band);
		col += mix(nebula_a.rgb, nebula_b.rgb, smoothstep(0.3, 0.7, warp.x)) * m * nebula;
	}
	if (aurora > 0.0) {
		float wave = az * 5.0 + fbm2(vec2(az * 2.0, 0.5)) * 3.0;
		float curtain = pow(0.5 + 0.5 * sin(wave * 3.0), 3.0);
		float streak = 0.6 + 0.4 * noise2(vec2(az * 60.0, el * 1.5));
		float height = smoothstep(0.06, 0.16, el) * (1.0 - smoothstep(0.3, 0.55, el));
		vec3 c = mix(aurora_a.rgb, aurora_b.rgb, smoothstep(0.12, 0.4, el));
		col += c * curtain * streak * height * aurora * 0.55;
	}
	if (rays > 0.0) {
		vec2 dv = vec2(az - ray_dir.x, el - ray_dir.y);
		float ang = atan(dv.x, dv.y);
		float streak = smoothstep(0.5, 0.9, noise2(vec2(ang * 14.0, 0.5)));
		col += ray_color.rgb * streak * rays * 0.18 * exp(-length(dv) * 1.6);
	}
	return col;
}

// Clouds: a band of soft heaps above the horizon (rgb, coverage).
vec4 cloud_layer(float az, float el) {
	if (clouds <= 0.0) {
		return vec4(0.0);
	}
	vec2 p = vec2(az * 4.0, el * 11.0);
	float n = fbm2(p + vec2(0.0, noise2(p * 0.5) * 1.2));
	float shape = n + (0.12 - el) * 2.2 - 0.15;
	float a = smoothstep(0.36, 0.7, shape) * smoothstep(-0.02, 0.04, el) * clouds;
	// Lit tops, shaded bellies: mostly by height within the heap, a little noise.
	float lit = clamp((shape - 0.36) * 1.6 + (el - 0.04) * 4.0, 0.0, 1.0);
	lit = mix(lit, noise2(p * 2.3), 0.2);
	vec3 c = mix(cloud_shade.rgb, cloud_color.rgb, smoothstep(0.0, 0.9, lit));
	return vec4(c, a);
}

// --- Celestial body ------------------------------------------------------------

vec4 body_layer(float az, float el, float aa) {
	if (body_kind == 0) {
		return vec4(0.0);
	}
	vec2 q = vec2(az - body.x, el - body.y) / body.z;
	float r = length(q);
	float soft = aa * 2.0 / body.z;
	float disc = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, r);
	vec4 o = vec4(0.0);
	if (body_kind == 1) {
		// Sun: a calm disc with a wide warm glow (stays below the bloom threshold).
		float glow = exp(-r * 0.9) * 0.35 + exp(-r * 0.25) * 0.08;
		o = vec4(body_color.rgb * (disc * 0.95 + glow * (1.0 - disc)), max(disc, glow));
	} else {
		vec3 nrm = vec3(q, sqrt(max(1.0 - r * r, 0.0)));
		float lambert = clamp(dot(nrm, normalize(vec3(-0.5, 0.35, 0.8))), 0.0, 1.0);
		vec3 c = body_color.rgb;
		if (body_kind == 2) {
			float crater = smoothstep(0.55, 0.75, noise2(q * 5.0 + 3.0)) * 0.35;
			c *= 1.0 - crater;
		} else {
			c *= 0.75 + 0.25 * sin(q.y * 14.0 + noise2(q * 3.0) * 2.0);
		}
		o = vec4(c * (0.12 + 0.88 * lambert), disc);
		if (body_kind == 3) {
			// Tilted ring: hidden behind the planet's upper half.
			vec2 rq = mat2(vec2(0.94, -0.34), vec2(0.34, 0.94)) * q;
			float rr = length(rq * vec2(1.0, 3.6));
			float ring = smoothstep(1.35, 1.42, rr) * (1.0 - smoothstep(2.1, 2.2, rr));
			ring *= 0.55 + 0.45 * step(0.5, fract(rr * 6.0));
			float behind = step(0.0, rq.y) * disc;
			o.rgb = mix(o.rgb, body_color.rgb * 0.8, ring * (1.0 - behind));
			o.a = max(o.a, ring * (1.0 - behind));
		}
	}
	return o;
}

float star_layer(float az, float el) {
	vec2 g = vec2(az, el) * 160.0;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash12(id);
	if (h < 1.0 - 0.07 * star_density) {
		return 0.0;
	}
	vec2 c = (vec2(hash12(id + 7.0), hash12(id + 3.0)) - 0.5) * 0.6;
	float size = 0.06 + 0.12 * pow(hash12(id + 11.0), 3.0);
	float s = 1.0 - smoothstep(0.0, size, length(f - c));
	return s * (0.25 + 0.55 * hash12(id + 13.0));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = mix(sky_bottom.rgb, sky_top.rgb, clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0));
	} else {
		vec3 dir = normalize(EYEDIR);
		float el = asin(clamp(dir.y, -1.0, 1.0));
		float az = atan(dir.x, -dir.z);
		if (AT_HALF_RES_PASS) {
			COLOR = detail ? soft_layers(az, el) : vec3(0.0);
		} else {
			vec2 uv = SCREEN_UV;
			vec3 v = rest_view * EYEDIR;
			if (tan_half.x > 0.0 && v.z < -0.01) {
				// Pinhole projection in the rest frame: equals SCREEN_UV when the camera rests.
				uv = vec2(0.5 + v.x / (-v.z * 2.0 * tan_half.x), 0.5 - v.y / (-v.z * 2.0 * tan_half.y));
			}
			vec3 col = mix(sky_bottom.rgb, sky_top.rgb, smoothstep(0.15, 0.95, 1.0 - uv.y));
			vec2 c = vec2(0.5, 1.0 - sink_height);
			float r = length((uv - c) * vec2(1.0, 1.9));
			// Broad soft falloff plus a small bright core (only the core exceeds 1.0).
			vec3 sink = sink_color.rgb * (exp(-r * 5.5) * 0.35 + exp(-r * 40.0) * 1.2) * sink_strength;
			if (star_density > 0.0) {
				col += vec3(star_layer(az, el)) * (1.0 - smoothstep(0.0, 0.3, exp(-r * 3.0)));
			}
			float aa = max(fwidth(el), 0.0005);
			vec4 b = body_layer(az, el, aa);
			col = mix(col, b.rgb, b.a);
			// Soft layers glow over the stars and body; clouds cover them all.
			col += HALF_RES_COLOR.rgb;
			if (detail) {
				vec4 cl = cloud_layer(az, el);
				col = mix(col, cl.rgb, cl.a);
			}
			col += sink;
			vec4 s = skyline_layer(az, el, aa);
			col = mix(col, s.rgb, clamp(s.a, 0.0, 1.0));
			COLOR = col;
		}
	}
}
