// FLUX DROP hazard body: each world's obstacles get their own material
// (ART_DIRECTION §5 hazard row) while one cue stays constant everywhere: a
// warm warning light (`warn`, red to orange-red) on every obstacle. The body is
// lit PBR matter; only the warning pattern emits (a functional lamp, §1).
// Patterns are procedural in object space, so no textures are needed.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 body : source_color = vec4(0.23, 0.25, 0.3, 1.0);
uniform vec4 warn : source_color = vec4(1.0, 0.3, 0.18, 1.0);
uniform float roughness = 0.45;
uniform float metallic = 0.6;
uniform float clearcoat = 0.0;
// 0 machined (warning band), 1 hazard stripes, 2 lava cracks, 3 glyph lines,
// 4 inner glow (ice, crystal), 5 candy stripes, 6 glowing veins (organic).
uniform int pattern = 0;
// Warning light strength; above 1.0 it blooms (HDR), lower in high-key worlds.
uniform float warn_energy = 2.2;
// Object-space half height of the mesh (patterns are placed relative to it).
uniform float half_height = 0.45;
// Warning-coloured fresnel outline: every obstacle, whatever its body, keeps a
// warm edge against a dark shaft (lower in high-key worlds).
uniform float warn_rim = 0.35;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

float aa_band(float coord, float half_width) {
	float w = fwidth(coord);
	return 1.0 - smoothstep(half_width - w, half_width + w, abs(coord));
}

void fragment() {
	vec3 col = body.rgb;
	float glow = 0.0;
	float rough = roughness;
	float metal = metallic;
	float y = obj.y / max(half_height, 0.001);
	float breathe = 0.85 + 0.15 * sin(TIME * 3.0);
	if (pattern == 0) {
		// Machined: a thin lit band two thirds up and a darker lower skirt.
		glow = aa_band(y - 0.38, 0.06);
		col *= mix(0.72, 1.0, smoothstep(-1.0, -0.55, y));
	} else if (pattern == 1) {
		// Diagonal hazard stripes on a band round the middle; the stripes are
		// paint (albedo), the band's top edge is the warning light.
		float band = 1.0 - smoothstep(0.42, 0.46, abs(y + 0.05));
		float stripe = step(0.5, fract((obj.x + obj.y) * 2.6));
		col = mix(col, mix(col * 0.12, warn.rgb * 0.85, stripe), band);
		glow = aa_band(y - 0.5, 0.035);
	} else if (pattern == 2) {
		// Lava rock: dark, rough, with glowing cracks from a noise field.
		float n = fd_fbm(obj * 3.2 + vec3(0.0, TIME * 0.05, 0.0));
		float crack = 1.0 - smoothstep(0.0, 0.035 + 0.015 * breathe, abs(n - 0.5));
		col *= 0.65 + 0.35 * fd_noise3(obj * 9.0);
		glow = crack * 1.15;
		rough = 0.9;
		metal = 0.0;
	} else if (pattern == 3) {
		// Monolith glyphs: short horizontal strokes in a column grid.
		float row = floor(obj.y * 7.0);
		float colm = floor(obj.x * 5.0 + 0.5);
		float on = step(0.45, fd_hash13(vec3(colm, row, 3.0)));
		float stroke = aa_band(fract(obj.y * 7.0) - 0.5, 0.11) * aa_band(fract(obj.x * 5.0 + 0.5) - 0.5, 0.32);
		glow = on * stroke;
	} else if (pattern == 4) {
		// Ice or crystal: a warm light deep inside shows through the faces
		// you look straight into; the edges stay cold and glassy.
		float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		glow = pow(ndv, 2.2) * 0.55 * (0.7 + 0.3 * fd_noise3(obj * 4.0 + TIME * 0.3));
		rough = 0.08;
		metal = 0.0;
	} else if (pattern == 5) {
		// Candy: glossy white with red diagonal stripes; a lit rim on top.
		float stripe = step(0.5, fract((obj.x - obj.y + obj.z) * 2.2));
		col = mix(col, warn.rgb * 0.8, stripe);
		glow = aa_band(y - 0.9, 0.05) * 0.6;
		rough = 0.18;
		metal = 0.0;
	} else if (pattern == 6) {
		// Organic pods: veins that pulse along the stem.
		float n = fd_noise3(vec3(obj.x * 6.0, obj.y * 2.0 - TIME * 0.6, obj.z * 6.0));
		glow = (1.0 - smoothstep(0.0, 0.06, abs(n - 0.5))) * 0.9;
		rough = 0.5;
		metal = 0.0;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = 0.2;
	RIM = 0.25;
	RIM_TINT = 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = warn.rgb * (glow * warn_energy * breathe + fres * warn_rim);
}
