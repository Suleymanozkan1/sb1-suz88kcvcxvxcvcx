// FLUX DROP event post effects (only active during an event; idle cost zero):
// a coloured edge tint (fail = FAILURE, perfect = ACCENT), a short distortion
// ring for state changes, and a chromatic split reserved for fail / overdrive.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float chroma = 0.0;
uniform float shock = 0.0;
uniform vec2 shock_center = vec2(0.5, 0.72);
uniform float shock_radius = 0.0;
uniform float tint = 0.0;
uniform vec4 tint_color : source_color = vec4(0.9, 0.28, 0.3, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	if (shock > 0.0) {
		vec2 dir = uv - shock_center;
		float dist = length(dir * vec2(1.0, 1.7));
		float ring = exp(-pow((dist - shock_radius) * 16.0, 2.0));
		uv -= normalize(dir + 1e-5) * ring * shock * 0.018;
	}
	vec3 col;
	if (chroma > 0.0) {
		vec2 off = (uv - 0.5) * chroma * 0.008;
		col.r = texture(screen_tex, uv + off).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - off).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	float edge = smoothstep(0.35, 0.95, length((SCREEN_UV - 0.5) * vec2(1.0, 0.75)) * 1.4);
	col = mix(col, tint_color.rgb, edge * tint * 0.6);
	COLOR = vec4(col, 1.0);
}
