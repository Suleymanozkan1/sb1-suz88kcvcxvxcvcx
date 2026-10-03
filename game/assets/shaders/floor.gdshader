// FLUX DROP shaft floor: scrolling energy grid with glowing lane rails.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 floor_color : source_color = vec4(0.03, 0.05, 0.14, 1.0);
uniform vec4 grid_color : source_color = vec4(0.16, 0.36, 1.0, 1.0);
uniform vec4 rail_color : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 fog_color : source_color = vec4(0.04, 0.07, 0.21, 1.0);
uniform float scroll = 0.0;
uniform float lane_width = 1.6;
uniform int lane_count = 2;
uniform float grid_spacing = 2.0;
uniform float fade_distance = 70.0;
uniform float pulse = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float line(float coord, float width) {
	float d = abs(fract(coord) - 0.5);
	return 1.0 - smoothstep(0.5 - width, 0.5, d);
}

void fragment() {
	// local_pos.z runs towards the camera (+) and away (-); world distance = scroll - z.
	float dist = scroll - local_pos.z;
	float across = local_pos.x;
	float g = line(dist / grid_spacing, 0.04) * 0.55 + line(across / (lane_width * 0.5), 0.02) * 0.25;
	float rails = 0.0;
	float half_span = float(lane_count) * lane_width * 0.5;
	for (int i = 0; i <= 3; i++) {
		if (i > lane_count) {
			break;
		}
		float x = -half_span + float(i) * lane_width;
		rails += exp(-abs(across - x) * 22.0);
	}
	float edge_glow = exp(-abs(abs(across) - half_span) * 4.0) * 0.4;
	float depth = clamp(-local_pos.z / fade_distance, 0.0, 1.0);
	vec3 col = floor_color.rgb + grid_color.rgb * g * (1.0 + pulse) + rail_color.rgb * rails * 1.6 + rail_color.rgb * edge_glow;
	col = mix(col, fog_color.rgb, smoothstep(0.35, 1.0, depth));
	ALBEDO = col;
}
