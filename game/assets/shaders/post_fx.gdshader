// FLUX DROP screen post effects: controlled chromatic split, shock distortion,
// vignette and impact flash. All strengths default to 0 (no cost when idle).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float chroma = 0.0;
uniform float shock = 0.0;
uniform vec2 shock_center = vec2(0.5, 0.7);
uniform float shock_radius = 0.0;
uniform float vignette = 0.35;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (shock > 0.0) {
		vec2 dir = uv - shock_center;
		float dist = length(dir * vec2(1.0, 1.7));
		float ring = exp(-pow((dist - shock_radius) * 18.0, 2.0));
		uv -= normalize(dir + 1e-5) * ring * shock * 0.03;
	}
	vec3 col;
	if (chroma > 0.0) {
		vec2 off = (uv - 0.5) * chroma * 0.012;
		col.r = texture(screen_tex, uv + off).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - off).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	float v = smoothstep(0.85, 0.25, length((SCREEN_UV - 0.5) * vec2(1.0, 0.8)));
	col *= mix(1.0, v, vignette);
	col = mix(col, flash_color.rgb, flash);
	COLOR = vec4(col, 1.0);
}
