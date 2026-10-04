// FLUX DROP sky: calm low-saturation gradient with one light shape — the flux
// sink the core drops towards (ART_DIRECTION §6). Sparse stars only when a world
// asks for them. The radiance pass gets the gradient only (cheap on mobile).
// The background is laid out in the camera's rest frame from the eye direction,
// so lean, shake and lane follow turn the view across it (it sits at infinity).
shader_type sky;

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

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = mix(sky_bottom.rgb, sky_top.rgb, clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0));
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
		col += sink_color.rgb * (exp(-r * 5.5) * 0.35 + exp(-r * 40.0) * 1.2) * sink_strength;
		if (star_density > 0.0) {
			vec2 cell = floor(uv * vec2(110.0, 190.0));
			float star = step(1.0 - 0.006 * star_density, hash12(cell));
			col += vec3(star) * 0.35 * (1.0 - smoothstep(0.0, 0.3, exp(-r * 3.0)));
		}
		COLOR = col;
	}
}
