// Shared parts of the offline backdrop bakes (tools/bake_backdrop.gd): the
// view mapping (the same one the sky shader samples with), noise, and the
// output grade. Everything here runs once on the build machine, never on a
// phone, so it can afford hundreds of raymarch steps per pixel.

uniform vec2 full_size = vec2(2048.0);
uniform vec2 tile_origin = vec2(0.0);
uniform vec2 tile_size = vec2(256.0);
// az_half, el_bottom, el_top in radians (art.sky.backdrop).
uniform vec3 view_rect = vec3(0.5498, -0.2443, 0.8552);


// Pixel position in the full image (0..1, y down) for this tile's UV.
vec2 image_uv(vec2 tile_uv) {
	return (tile_origin + tile_uv * tile_size) / full_size;
}

// The view direction of an image position: the sky shader maps az = atan(x, -z)
// across and el = asin(y) down the image.
vec3 view_dir(vec2 uv) {
	float az = (uv.x - 0.5) * 2.0 * view_rect.x;
	float el = view_rect.z - uv.y * (view_rect.z - view_rect.y);
	return vec3(sin(az) * cos(el), sin(el), -cos(az) * cos(el));
}

vec3 dir_from(float az_deg, float el_deg) {
	float az = radians(az_deg);
	float el = radians(el_deg);
	return vec3(sin(az) * cos(el), sin(el), -cos(az) * cos(el));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise with its derivatives (quintic fade).
vec3 noised(vec2 x) {
	vec2 p = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash12(p);
	float b = hash12(p + vec2(1.0, 0.0));
	float c = hash12(p + vec2(0.0, 1.0));
	float d = hash12(p + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;
	return vec3(a + k1 * u.x + k2 * u.y + k4 * u.x * u.y, du * (vec2(k1, k2) + k4 * u.yx));
}

float noise2(vec2 x) {
	return noised(x).x;
}

float noise3(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(p), hash13(p + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(p + vec3(0.0, 1.0, 0.0)), hash13(p + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(p + vec3(0.0, 0.0, 1.0)), hash13(p + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(p + vec3(0.0, 1.0, 1.0)), hash13(p + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

const mat2 ROT2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));

float fbm2(vec2 p, int octaves) {
	float a = 0.0;
	float b = 0.5;
	for (int i = 0; i < octaves; i++) {
		a += b * noise2(p);
		b *= 0.5;
		p = ROT2 * p * 2.02;
	}
	return a;
}

float fbm3(vec3 p, int octaves) {
	float a = 0.0;
	float b = 0.5;
	for (int i = 0; i < octaves; i++) {
		a += b * noise3(p);
		b *= 0.5;
		p = p * 2.03 + vec3(1.7, -3.1, 2.3);
	}
	return a;
}

// Eroded terrain: octaves damped where the slope of the coarser ones is steep,
// which leaves ridges and gullies instead of round lumps.
float terrain_fbm(vec2 p, int octaves) {
	float a = 0.0;
	float b = 1.0;
	vec2 d = vec2(0.0);
	for (int i = 0; i < octaves; i++) {
		vec3 n = noised(p);
		d += n.yz;
		a += b * n.x / (1.0 + dot(d, d));
		b *= 0.5;
		p = ROT2 * p * 2.0;
	}
	return a;
}

float ridged2(vec2 p, int octaves) {
	float a = 0.0;
	float b = 0.5;
	float prev = 1.0;
	for (int i = 0; i < octaves; i++) {
		float n = 1.0 - abs(noise2(p) * 2.0 - 1.0);
		n *= n;
		a += n * b * prev;
		prev = n;
		b *= 0.5;
		p = ROT2 * p * 2.05;
	}
	return a;
}

// Distance to the nearest and second nearest cell point.
vec2 voronoi2(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			float d = length(g + o - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(f1, f2);
}

// Stars on the view sphere: a point per lit cell with a size and colour spread.
vec3 star_field(vec3 dir, float density, float scale) {
	vec2 sph = vec2(atan(dir.x, -dir.z), asin(clamp(dir.y, -1.0, 1.0))) * scale;
	vec2 id = floor(sph);
	vec2 f = fract(sph) - 0.5;
	float h = hash12(id);
	if (h > density) {
		return vec3(0.0);
	}
	vec2 c = (hash22(id + 3.1) - 0.5) * 0.7;
	float mag = pow(hash12(id + 7.7), 6.0);
	float r = length(f - c);
	float core = exp(-r * r * (900.0 - 700.0 * mag));
	vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), hash12(id + 1.3));
	return tint * core * (0.15 + 2.5 * mag);
}

float sdf_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdf_cylinder(vec3 p, float r, float h) {
	vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Filmic curve (ACES fit) and sRGB encode: the image is stored display-ready
// and the sky shader reads it back as a colour texture.
vec3 finish(vec3 c, vec2 uv) {
	c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
	c = clamp(c, 0.0, 1.0);
	c = pow(c, vec3(1.0 / 2.2));
	// A whisper of grain so gradients do not band after JPG.
	c += (hash12(uv * full_size + 0.5) - 0.5) / 255.0;
	return c;
}
