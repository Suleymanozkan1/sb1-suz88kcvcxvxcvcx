// FLUX DROP spark collectible (MultiMesh): spinning, twinkling energy diamonds.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float intensity = 2.2;
uniform float spin_speed = 2.5;

varying vec4 inst_color;

void vertex() {
	float a = TIME * spin_speed + float(INSTANCE_ID) * 0.7;
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xz = rot * VERTEX.xz;
	VERTEX.y += sin(TIME * 3.0 + float(INSTANCE_ID)) * 0.06;
	inst_color = COLOR;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.5);
	ALBEDO = inst_color.rgb * (intensity + fres * 1.5);
}
