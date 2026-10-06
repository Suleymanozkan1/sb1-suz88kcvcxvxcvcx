// FLUX DROP craft hull paint (ART_DIRECTION §4, §5): glossy ceramic paint over
// a lightly metallic base, with the details that make it read as a built
// machine at a glance: recessed panel seams along the hull, a seam round its
// waist, a racing stripe down the spine and on each wing in the accent colour
// (the skin in HOP, the form colour otherwise), and a faint flake in the
// clearcoat. Object space, no textures; `detail` 0 (Low quality) paints it flat.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 paint : source_color = vec4(0.9, 0.92, 0.95, 1.0);
uniform vec4 accent : source_color = vec4(0.27, 0.9, 0.94, 1.0);
uniform vec4 seam : source_color = vec4(0.16, 0.18, 0.23, 1.0);
uniform float roughness = 0.28;
uniform float metallic = 0.12;
uniform float clearcoat = 0.8;
uniform float detail = 1.0;
// Panel seams: spacing along the hull and line half-width (object units).
uniform float seam_spacing = 0.14;
uniform float seam_width = 0.0018;

varying vec3 obj;
varying vec3 obj_n;

float aa_line(float coord, float half_width) {
	float w = max(fwidth(coord), 0.0004);
	return 1.0 - smoothstep(half_width - w, half_width + w, abs(coord));
}

void fragment() {
	vec3 col = paint.rgb;
	float rough = roughness;
	if (detail > 0.0) {
		// Seams across the hull every seam_spacing, only on the curved body
		// (|x| inside the fuselage), and one round the waist.
		float body = 1.0 - smoothstep(0.17, 0.2, abs(obj.x));
		float across = aa_line(fract(obj.z / seam_spacing + 0.5) - 0.5, seam_width / seam_spacing) * body;
		float waist = aa_line(obj.y + 0.012, seam_width) * body;
		float seams = max(across, waist);
		// Racing stripe on top of the spine, and a band near each wing tip.
		float top = smoothstep(0.25, 0.6, obj_n.y);
		float spine = aa_line(obj.x, 0.024) * top * body;
		float wing = (1.0 - smoothstep(0.0, 0.004, abs(abs(obj.x) - 0.3) - 0.022)) * (1.0 - body);
		float stripe = max(spine, wing * smoothstep(0.0, 0.3, obj_n.y + 0.5));
		col = mix(col, accent.rgb, stripe * 0.9);
		col = mix(col, seam.rgb, seams * 0.5);
		// Faint flake: a little roughness noise under the clearcoat.
		rough += (fd_noise3(obj * 140.0) - 0.5) * 0.08;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metallic;
	SPECULAR = 0.6;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = 0.12;
	RIM = 0.3;
	RIM_TINT = 0.6;
}

void vertex() {
	obj = VERTEX;
	obj_n = NORMAL;
}
