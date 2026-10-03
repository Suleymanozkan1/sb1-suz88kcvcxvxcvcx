// FLUX DROP shaft floor: matte panels, recessed lane grooves, seams for speed.
// Matter never glows (ART_DIRECTION §1): all detail is albedo/roughness only.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 floor_color : source_color = vec4(0.07, 0.09, 0.14, 1.0);
uniform vec4 lane_color : source_color = vec4(0.10, 0.125, 0.18, 1.0);
uniform vec4 fog_color : source_color = vec4(0.08, 0.11, 0.16, 1.0);
uniform float scroll = 0.0;
uniform float lane_width = 1.6;
uniform int lane_count = 2;
uniform float seam_spacing = 4.0;
uniform float caustics = 0.0;
uniform vec4 caustic_color : source_color = vec4(0.6, 0.95, 0.9, 1.0);
// Music beat (0..1, decaying): the lane lips catch a little more light on the
// beat, so the track breathes with the music without any glow.
uniform float beat = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

// Smooth 1-pixel-ish line using screen-space derivatives (no aliasing, no glow).
float aa_line(float coord, float half_width) {
	float d = abs(coord);
	float w = fwidth(coord);
	return 1.0 - smoothstep(half_width - w, half_width + w, d);
}

void fragment() {
	float dist = scroll - local_pos.z;
	float x = local_pos.x;
	float half_span = float(lane_count) * lane_width * 0.5;
	// Lane surfaces are slightly lighter than the outer floor.
	float on_track = 1.0 - smoothstep(half_span - 0.02, half_span + 0.02, abs(x));
	vec3 col = mix(floor_color.rgb, lane_color.rgb, on_track);
	// Recessed grooves at every lane boundary (darker), with a thin lit lip.
	float groove = 0.0;
	float lip = 0.0;
	for (int i = 0; i <= 3; i++) {
		if (i > lane_count) {
			break;
		}
		float bx = -half_span + float(i) * lane_width;
		groove = max(groove, aa_line(x - bx, 0.035));
		lip = max(lip, aa_line(x - bx - 0.06, 0.012));
	}
	col *= 1.0 - groove * 0.38;
	col += lip * (0.035 + beat * 0.05);
	// Panel seams across the track every seam_spacing units (speed cue).
	float seam = aa_line(fract(dist / seam_spacing) - 0.5, 0.004 * seam_spacing) * on_track;
	col *= 1.0 - seam * 0.16;
	// Underwater worlds: drifting caustic light on the panels. It is painted
	// into the albedo, so it is lit by the scene and never glows.
	if (caustics > 0.0) {
		vec2 p = vec2(x * 1.3, dist * 0.9);
		float c1 = sin(p.x * 2.1 + TIME * 1.1 + sin(p.y * 1.7 + TIME * 0.7));
		float c2 = sin(p.y * 2.3 - TIME * 0.9 + sin(p.x * 1.9 - TIME * 0.6));
		float caustic = pow(max(0.0, c1 * c2), 3.0);
		col = mix(col, caustic_color.rgb, caustic * caustics);
	}
	ALBEDO = col;
	ROUGHNESS = 0.82 - groove * 0.2;
	METALLIC = 0.18;
	SPECULAR = 0.4;
}
