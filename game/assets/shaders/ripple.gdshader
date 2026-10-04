// FLUX DROP tap ripple: a thin energy ring that spreads over the floor under
// the core on every accepted tap (feedback chain: tap -> movement -> sound ->
// haptic -> this visual impact). Flat, additive, brief and below bloom.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 0.6;
uniform float thickness = 18.0;
instance uniform float progress = 0.0;
instance uniform vec4 tint : source_color = vec4(0.27, 0.9, 0.94, 1.0);

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float radius = mix(0.25, 1.0, progress);
	float ring = exp(-pow((r - radius) * thickness, 2.0));
	ALBEDO = tint.rgb * ring * intensity * (1.0 - progress);
}
