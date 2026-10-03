// FLUX DROP floor current: engraved chevrons that drift in the push direction.
// A force field (energy) but kept below bloom so it informs without shouting.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 energy : source_color = vec4(0.27, 0.9, 0.94, 1.0);
uniform float direction = 1.0;
uniform float intensity = 0.55;

void fragment() {
	vec2 uv = UV;
	float u = uv.x * 4.0 * direction - TIME * 2.0;
	float chevron = abs(fract(u + abs(uv.y - 0.5) * 0.9) - 0.5);
	float mark = 1.0 - smoothstep(0.08, 0.12, chevron);
	float fade = smoothstep(0.0, 0.15, uv.y) * smoothstep(1.0, 0.85, uv.y);
	ALBEDO = energy.rgb * mark * fade * intensity;
}
