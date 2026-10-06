// FLUX DROP craft canopy glass (ART_DIRECTION §4, §5): a tinted, glossy
// bubble over the energy core. Face-on it is mostly clear, so the core glows
// through it; towards the edges it turns reflective (Fresnel) and catches the
// key light as a sharp highlight, with a soft band of sheen across its top
// like a reflected horizon. The sheen stays far below the bloom threshold:
// glass is matter, only the core under it glows.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.08, 0.13, 0.17, 1.0);
uniform vec4 sheen : source_color = vec4(0.72, 0.86, 0.95, 1.0);
// Face-on transparency (1 = fully clear).
uniform float clarity = 0.8;
// 0 on Low quality: no sheen band, a plain tinted shell.
uniform float detail = 1.0;

varying vec3 obj_n;

void vertex() {
	obj_n = NORMAL;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	float band = smoothstep(0.5, 0.66, obj_n.y) * (1.0 - smoothstep(0.78, 0.9, obj_n.y)) * detail;
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = sheen.rgb * (fres * 0.3 + band * 0.22);
	ALPHA = clamp(1.0 - clarity + fres * 0.75 + band * 0.3, 0.0, 0.95);
}
