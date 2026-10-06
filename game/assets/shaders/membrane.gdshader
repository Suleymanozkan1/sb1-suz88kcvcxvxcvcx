// FLUX DROP energy membrane (phase gates, portals, form gates). Energy may glow
// (ART_DIRECTION §1) but stays thin and translucent so the shaft reads through.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 energy : source_color = vec4(0.27, 0.9, 0.94, 1.0);
uniform float intensity = 1.15;
uniform float density = 0.22;
uniform float scan_speed = 0.6;
uniform bool radial = false;
instance uniform float ripple = 0.0;
instance uniform float visibility = 1.0;

void fragment() {
	vec2 uv = UV;
	float edge;
	float scan;
	if (radial) {
		float r = length(uv - 0.5) * 2.0;
		edge = smoothstep(0.75, 1.0, r) * (1.0 - smoothstep(0.98, 1.0, r));
		scan = 0.5 + 0.5 * sin(r * 22.0 - TIME * scan_speed * 6.0);
		scan *= 1.0 - smoothstep(0.95, 1.0, r);
	} else {
		edge = max(smoothstep(0.9, 1.0, abs(uv.x - 0.5) * 2.0), smoothstep(0.86, 1.0, abs(uv.y - 0.5) * 2.0));
		scan = 0.75 + 0.25 * sin(uv.y * 40.0 - TIME * scan_speed * 4.0);
	}
	float body = density * (0.6 + 0.4 * scan) + edge * 0.6 + ripple * 0.6;
	ALBEDO = energy.rgb * body * intensity * visibility;
}
