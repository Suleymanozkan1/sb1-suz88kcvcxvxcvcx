// Additive camera-facing glow (volumetric-looking halo, beams, flashes).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float size = 1.0;
uniform float falloff = 2.2;
uniform float ring = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float g = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	if (ring > 0.0) {
		g = exp(-pow((r - ring) * 14.0, 2.0)) + g * 0.2;
	}
	ALBEDO = glow_color.rgb * g * intensity;
}
