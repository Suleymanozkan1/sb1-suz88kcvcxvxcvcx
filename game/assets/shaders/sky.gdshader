// FLUX DROP sky: gradient, flux sink glow, nebula and stars. Screen-space so the
// composition stays fixed while the camera follows the core. The radiance
// (cubemap) pass gets a static gradient only, keeping it cheap on mobile.
shader_type sky;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 sky_top : source_color = vec4(0.02, 0.03, 0.1, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.05, 0.1, 0.29, 1.0);
uniform vec4 sink_color : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.24, 0.8, 1.0);
uniform float sink_height = 0.62;
uniform float star_density = 0.5;
uniform float drift = 0.0;
uniform float pulse = 0.0;

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = mix(sky_bottom.rgb, sky_top.rgb, clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0));
	} else {
		vec2 uv = SCREEN_UV;
		vec3 col = mix(sky_bottom.rgb, sky_top.rgb, smoothstep(0.0, 1.0, 1.0 - uv.y));
		vec2 c = vec2(0.5, 1.0 - sink_height);
		float r = length((uv - c) * vec2(1.0, 1.6));
		col += sink_color.rgb * (exp(-r * 6.0) * (0.9 + pulse) + exp(-r * 18.0) * 0.8);
		float neb = fd_fbm(vec3(uv * 3.0, drift * 0.05 + TIME * 0.02));
		col += accent_color.rgb * smoothstep(0.55, 0.85, neb) * 0.18;
		vec2 sp = uv * vec2(90.0, 160.0) + vec2(0.0, drift * 0.4);
		float star = step(1.0 - 0.012 * star_density, fd_hash13(vec3(floor(sp), 3.0)));
		float tw = 0.6 + 0.4 * sin(TIME * 3.0 + fd_hash13(vec3(floor(sp), 9.0)) * 40.0);
		col += vec3(star * tw) * (1.0 - smoothstep(0.0, 0.25, exp(-r * 4.0)));
		COLOR = col;
	}
}
