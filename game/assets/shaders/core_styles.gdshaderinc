// FLUX DROP core skin styles, shared by the in-run core (core.gdshader) and
// the shop swatch (core_swatch.gdshader), so a skin looks the same before it
// is bought. obj: point on the core in object units; ndv: facing (1 at the
// centre, 0 at the limb); t: animated time; lock: 1 while the form colour
// carries meaning. Include noise.gdshaderinc first.

vec3 fd_core_style(int style, vec3 obj, float ndv, float t, vec3 ca, vec3 cb, vec3 rim, float lock) {
	vec3 p = obj * 3.2;
	float m = 0.0;
	vec3 col;
	if (style == 1) { // Fire: rising flicker
		m = fd_fbm(p * vec3(1.0, 0.7, 1.0) - vec3(0.0, t * 2.6, 0.0));
		m = smoothstep(0.25, 0.8, m + (0.4 - obj.y));
		col = mix(cb, ca, m);
	} else if (style == 2) { // Ice: crisp facets
		float c = fd_cells(p * 1.4 + vec3(0.0, 0.0, t * 0.15));
		m = smoothstep(0.05, 0.6, c);
		col = mix(ca * 1.3, cb, m) + step(0.92, 1.0 - c) * 0.6;
	} else if (style == 3) { // Void: dark heart, hungry rim
		m = fd_fbm(p * 1.5 + vec3(t * 0.3, -t * 0.2, t * 0.1));
		vec3 rim_v = mix(rim, ca, lock);
		col = mix(vec3(0.0), mix(cb * 0.4, ca * 0.5, lock), m) + rim_v * pow(1.0 - ndv, 1.2) * 2.2;
	} else if (style == 4) { // Crystal: prismatic bands
		float bands = sin(dot(p, vec3(3.0, 5.0, 2.0)) + t * 1.5) * 0.5 + 0.5;
		col = mix(ca, cb, bands) + vec3(bands, 1.0 - bands, 0.5) * 0.25;
	} else if (style == 5) { // Electric: thin arcs
		float arc = abs(fd_noise3(p * 2.2 + vec3(t * 3.0)) - 0.5);
		m = 1.0 - smoothstep(0.0, 0.06, arc);
		col = mix(ca * 0.35, rim * 2.0, m);
	} else if (style == 6) { // Molten: cracks with glowing seams
		float c = fd_cells(p * 1.8 + vec3(0.0, t * 0.4, 0.0));
		m = 1.0 - smoothstep(0.0, 0.12, c);
		col = mix(cb * 0.25, ca * 2.0, m);
	} else if (style == 7) { // Aurora: flowing curtains
		float a = sin(p.y * 4.0 + fd_fbm(p + vec3(t * 0.5)) * 6.0 + t);
		col = mix(ca, cb, a * 0.5 + 0.5);
	} else if (style == 8) { // Candy: spinning stripes
		float s = sin(atan(p.x, p.z) * 4.0 + p.y * 3.0 - t * 3.0);
		col = mix(ca, cb, step(0.0, s));
	} else if (style == 9) { // Nebula: stars inside clouds
		m = fd_fbm(p * 0.9 + vec3(t * 0.2));
		float stars = step(0.985, fd_hash13(floor(p * 9.0)));
		col = mix(cb * 0.4, ca, m) + stars * 2.0;
	} else if (style == 10) { // Toxic: bubbles rise through the core and pop
		float c = fd_cells(p * 1.6 - vec3(0.0, t * 0.9, 0.0));
		float bubble = 1.0 - smoothstep(0.0, 0.18, c);
		float rim_b = smoothstep(0.14, 0.2, c) * (1.0 - smoothstep(0.2, 0.26, c));
		col = mix(cb * 0.5, ca, bubble) + ca * rim_b * 0.8;
	} else if (style == 11) { // Solar: granulated surface, flares licking the limb
		float gran = fd_cells(p * 3.4 + vec3(t * 0.25));
		float flare = fd_fbm(vec3(atan(obj.x, obj.z) * 2.0, obj.y * 3.0, t * 1.6));
		col = mix(cb, ca, smoothstep(0.1, 0.5, gran));
		col += ca * smoothstep(0.55, 0.9, flare) * pow(1.0 - ndv, 1.5) * 1.6;
	} else if (style == 12) { // Frostbite: frost creeps inward from the rim
		float frost = fd_fbm(p * 2.4 + vec3(0.0, 0.0, t * 0.1));
		float reach = 1.0 - ndv + 0.25 * sin(t * 0.8);
		m = smoothstep(0.35, 0.36, frost * reach * 1.4);
		col = mix(cb * 0.6, ca * 1.4, m) + step(0.97, fd_hash13(floor(p * 14.0))) * 0.8;
	} else if (style == 13) { // Shadow: dark smoke swirls and swallows the light
		float swirl = fd_fbm(p * 1.3 + vec3(sin(t * 0.7), t * 0.5, cos(t * 0.6)));
		m = smoothstep(0.35, 0.75, swirl);
		col = mix(cb, ca * 0.35, m) + ca * pow(1.0 - ndv, 3.0) * 1.8;
	} else if (style == 14) { // Prism: hard facets, each splitting light into its own hue
		vec3 facet = floor(normalize(obj) * 3.0);
		float hue = fd_hash13(facet) + t * 0.15;
		vec3 spectrum = 0.5 + 0.5 * cos(6.2831 * (hue + vec3(0.0, 0.33, 0.67)));
		col = mix(ca, spectrum, 0.65 * (1.0 - 0.7 * lock)) * (0.75 + 0.35 * fd_hash13(facet + 5.0));
	} else if (style == 15) { // Neon pulse: rings pulse outward from the centre
		float r = length(obj.xz) * 6.0;
		float ring_m = smoothstep(0.75, 0.95, sin(r * 3.0 - t * 6.0) * 0.5 + 0.5);
		col = mix(cb * 0.3, ca * 1.6, ring_m);
	} else if (style == 16) { // Inferno: heat bands rise and shimmer
		float y = obj.y * 7.0 - t * 3.0 + fd_noise3(p * 2.0 + vec3(0.0, -t, 0.0)) * 1.5;
		m = smoothstep(0.2, 0.8, sin(y) * 0.5 + 0.5);
		col = mix(ca, cb * 1.3, m);
	} else if (style == 17) { // Deep space: a slow spiral galaxy
		float ang = atan(obj.x, obj.y);
		float rad = length(obj.xy) * 5.0;
		float arms = sin(ang * 2.0 + log(rad + 0.2) * 4.0 - t * 0.8) * 0.5 + 0.5;
		m = smoothstep(0.35, 0.85, arms) * (1.0 - smoothstep(0.9, 2.4, rad));
		col = mix(cb * 0.12, ca * 1.5, m) + step(0.99, fd_hash13(floor(p * 11.0))) * 1.5;
	} else if (style == 18) { // Starlight: points of light twinkle one by one
		vec3 cell = floor(p * 5.0);
		float star = step(0.7, fd_hash13(cell));
		float twinkle = 0.5 + 0.5 * sin(t * 4.0 + fd_hash13(cell + 3.0) * 6.2831);
		float point_m = 1.0 - smoothstep(0.0, 0.42, length(fract(p * 5.0) - 0.5));
		col = mix(cb * 0.3, ca * 0.55, 0.5 + 0.5 * obj.y) + star * point_m * twinkle * 2.4;
	} else { // Plasma (default): warped plasma with bright filaments running through it
		vec3 q = p + vec3(0.0, t * 1.4, t * 0.6);
		m = fd_fbm(q + vec3(fd_fbm(q * 0.7 + vec3(t * 0.3)) * 1.6));
		m = smoothstep(0.2, 0.85, m);
		float fil = 1.0 - smoothstep(0.0, 0.05, abs(fd_noise3(q * 1.6) - 0.5));
		col = mix(ca, cb, m * 0.8) + mix(ca, rim, 0.5) * fil * 0.9;
	}
	return col;
}
