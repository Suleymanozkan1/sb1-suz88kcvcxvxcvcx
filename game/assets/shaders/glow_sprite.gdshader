// Additive camera-facing energy sprite (core halo, ring pulses).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.27, 0.9, 0.94, 1.0);
uniform float intensity = 1.0;
uniform float size = 1.0;
uniform float falloff = 2.6;
uniform float ring = 0.0;
instance uniform float progress = 0.0;
instance uniform float fade = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float g = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	if (ring > 0.0) {
		float rr = mix(ring * 0.3, ring, progress);
		g = exp(-pow((r - rr) * 22.0, 2.0));
	}
	ALBEDO = glow_color.rgb * g * intensity * fade;
}
