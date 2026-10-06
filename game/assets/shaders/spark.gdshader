// FLUX DROP spark shard (MultiMesh). Energy: bright, small, steady — a slow spin
// shows it is a 3D object; no twinkle noise.
shader_type spatial;
render_mode unshaded, cull_back;

uniform float intensity = 1.6;
uniform float spin_speed = 0.9;

varying vec4 inst_color;

void vertex() {
	float a = TIME * spin_speed + float(INSTANCE_ID) * 0.9;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xz = rot * VERTEX.xz;
	VERTEX.y += sin(TIME * 2.2 + float(INSTANCE_ID) * 1.3) * 0.06;
	inst_color = COLOR;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// Facets read through a value step, not a glow halo.
	ALBEDO = inst_color.rgb * mix(intensity * 0.55, intensity, facing);
}
