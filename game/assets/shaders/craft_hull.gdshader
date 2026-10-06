// FLUX DROP craft hull paint (ART_DIRECTION §4, §5): glossy ceramic paint over
// a lightly metallic base, with the details that make it read as a built
// machine at a glance: recessed panel seams (real relief: they catch the light,
// bump-mapped from screen-space derivatives) across the fuselage and in chord
// lines over the wings, a seam round the waist, panels each a hair lighter or
// darker than the next, a racing stripe down the spine and a band near each
// wingtip in the accent colour (the skin in HOP, the form colour otherwise),
// and a faint flake in the clearcoat. Object space, no textures; the layout
// (fuselage half width, half span) comes per craft from CraftShapes.
// `detail` 0 (Low quality) paints it flat.
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
// Fuselage half width and half span of the craft (object units).
uniform float body_width = 0.16;
uniform float span = 0.44;
// Panel seams: spacing along the hull and line half-width (object units).
uniform float seam_spacing = 0.12;
uniform float seam_width = 0.0016;
uniform float seam_depth = 0.0025;

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
		float ax = abs(obj.x);
		float body = 1.0 - smoothstep(body_width - 0.02, body_width + 0.01, ax);
		float wing = 1.0 - body;
		// Seams: across the fuselage every seam_spacing, round its waist, and
		// chord lines across the wings.
		float across = aa_line(fract(obj.z / seam_spacing + 0.5) - 0.5, seam_width / seam_spacing) * body;
		float waist = aa_line(obj.y + 0.01, seam_width) * body;
		float chord = aa_line(fract(ax / 0.07) - 0.5, seam_width / 0.07) * wing;
		float seams = max(max(across, waist), chord);
		// Each panel a hair lighter or darker.
		float panel = fd_hash13(vec3(floor(obj.z / seam_spacing), floor(ax / 0.07) * wing, step(0.0, obj.y)));
		col *= 0.96 + 0.08 * panel;
		// Racing stripe on top of the spine, and a band near each wing tip.
		float top = smoothstep(0.25, 0.6, obj_n.y);
		float spine = aa_line(obj.x, 0.02) * top * body;
		float band = (1.0 - smoothstep(0.0, 0.004, abs(ax / span - 0.76) * span - 0.02)) * wing;
		float stripe = max(spine, band * smoothstep(0.0, 0.3, abs(obj_n.y)));
		col = mix(col, accent.rgb, stripe * 0.9);
		col = mix(col, seam.rgb, seams * 0.55);
		// Faint flake: a little roughness noise under the clearcoat.
		rough += (fd_noise3(obj * 140.0) - 0.5) * 0.08;
		// Recessed seams: bump the normal down into the lines (Mikkelsen 2010).
		float h = -seams * seam_depth;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 n = normalize(NORMAL);
		vec3 r1 = cross(dpdy, n);
		vec3 r2 = cross(n, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * n - grad);
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
