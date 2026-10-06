// FLUX DROP engine flame: an additive cone from each nozzle of the player's
// craft (CraftShapes.flames). White-hot at the nozzle, the form / skin colour
// towards the tip, flickering, with shock diamonds down a long plume; `length`
// stretches it with speed and in DASH.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 flame_color : source_color = vec4(0.27, 0.9, 0.94, 1.0);
uniform float intensity = 2.2;
uniform float length = 0.3;
uniform float flicker = 1.0;

varying float along;

void vertex() {
	along = UV.y;
	// The cone is built one unit long: scale only its length.
	VERTEX.z = mix(VERTEX.z, VERTEX.z - 1.0 + length, UV.y);
}

void fragment() {
	float t = clamp(along, 0.0, 1.0);
	float wave = 0.5 + 0.5 * sin(TIME * 47.0 + t * 18.0);
	float flick = mix(1.0, 0.75 + 0.25 * wave, flicker);
	vec3 c = mix(vec3(1.0, 1.0, 1.0), flame_color.rgb, smoothstep(0.0, 0.45, t));
	float fade = pow(1.0 - t, 1.8);
	// Shock diamonds: a few bright bands down the plume, strongest near the
	// nozzle and when the flame is long (dash, overdrive).
	float diamonds = pow(abs(sin(t * 3.1416 * 5.0)), 6.0) * (1.0 - t) * smoothstep(0.25, 0.6, length);
	ALBEDO = c * fade * intensity * flick * (1.0 + diamonds * 0.8);
}
