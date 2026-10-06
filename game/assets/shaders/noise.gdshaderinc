// FLUX DROP shared procedural noise (original implementation, no textures).
float fd_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float fd_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = fd_hash13(i);
	float b = fd_hash13(i + vec3(1.0, 0.0, 0.0));
	float c = fd_hash13(i + vec3(0.0, 1.0, 0.0));
	float d = fd_hash13(i + vec3(1.0, 1.0, 0.0));
	float e = fd_hash13(i + vec3(0.0, 0.0, 1.0));
	float f2 = fd_hash13(i + vec3(1.0, 0.0, 1.0));
	float g = fd_hash13(i + vec3(0.0, 1.0, 1.0));
	float h = fd_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, f2, u.x), mix(g, h, u.x), u.y), u.z);
}

float fd_fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * fd_noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return v;
}

// Cheap cellular pattern: distance to nearest jittered cell point.
float fd_cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float best = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec3 o = vec3(float(x), float(y), 0.0);
			vec3 h = vec3(fd_hash13(i + o), fd_hash13(i + o + 17.0), 0.5);
			best = min(best, length(o + h - f));
		}
	}
	return best;
}
