// Additive camera-facing energy sprite (core halo, ring pulses).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.27, 0.9, 0.94, 1.0);
uniform float intensity = 1.0;
uniform float size = 1.0;
uniform float falloff = 2.6;
uniform float ring = 0.0;
// Corona (core halo only): this many soft rays turning at ray_spin rad/s,
// a second set counter-turning; 0 rays draws the plain glow.
uniform float rays = 0.0;
uniform float ray_strength = 0.0;
uniform float ray_spin = 0.35;
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
		float off = (r - rr) * 22.0;
		g = exp(-off * off);
	}
	if (rays > 0.0) {
		vec2 d = UV - 0.5;
		float ang = atan(d.y, d.x);
		float a = pow(abs(cos(ang * rays * 0.5 + TIME * ray_spin)), 18.0);
		float b = pow(abs(cos(ang * rays * 0.75 - TIME * ray_spin * 0.6 + 1.3)), 30.0);
		g += (a + b * 0.6) * ray_strength * clamp(1.0 - r, 0.0, 1.0) * smoothstep(0.15, 0.35, r);
	}
	ALBEDO = glow_color.rgb * g * intensity * fade;
}
