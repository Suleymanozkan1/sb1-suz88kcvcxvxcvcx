// FLUX DROP energy core. Each `style` is a distinct animated look (skins).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://assets/shaders/noise.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.24, 0.96, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.24, 0.8, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 1.6;
uniform float pulse = 0.0;
uniform float anim_speed = 1.0;
uniform int style = 0;
uniform float overdrive = 0.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.4);
	float t = TIME * anim_speed;
	vec3 p = obj_pos * 3.2;
	float m = 0.0;
	vec3 col;
	if (style == 1) { // Fire: rising flicker
		m = fd_fbm(p * vec3(1.0, 0.7, 1.0) - vec3(0.0, t * 2.6, 0.0));
		m = smoothstep(0.25, 0.8, m + (0.4 - obj_pos.y));
		col = mix(color_b.rgb, color_a.rgb, m);
	} else if (style == 2) { // Ice: crisp facets
		float c = fd_cells(p * 1.4 + vec3(0.0, 0.0, t * 0.15));
		m = smoothstep(0.05, 0.6, c);
		col = mix(color_a.rgb * 1.3, color_b.rgb, m) + step(0.92, 1.0 - c) * 0.6;
	} else if (style == 3) { // Void: dark heart, hungry rim
		m = fd_fbm(p * 1.5 + vec3(t * 0.3, -t * 0.2, t * 0.1));
		col = mix(vec3(0.0), color_b.rgb * 0.4, m) + rim_color.rgb * pow(1.0 - ndv, 1.2) * 2.2;
	} else if (style == 4) { // Crystal: prismatic bands
		float bands = sin(dot(p, vec3(3.0, 5.0, 2.0)) + t * 1.5) * 0.5 + 0.5;
		col = mix(color_a.rgb, color_b.rgb, bands) + vec3(bands, 1.0 - bands, 0.5) * 0.25;
	} else if (style == 5) { // Electric: thin arcs
		float arc = abs(fd_noise3(p * 2.2 + vec3(t * 3.0)) - 0.5);
		m = 1.0 - smoothstep(0.0, 0.06, arc);
		col = mix(color_a.rgb * 0.35, rim_color.rgb * 2.0, m);
	} else if (style == 6) { // Molten: cracks with glowing seams
		float c = fd_cells(p * 1.8 + vec3(0.0, t * 0.4, 0.0));
		m = 1.0 - smoothstep(0.0, 0.12, c);
		col = mix(color_b.rgb * 0.25, color_a.rgb * 2.0, m);
	} else if (style == 7) { // Aurora: flowing curtains
		float a = sin(p.y * 4.0 + fd_fbm(p + vec3(t * 0.5)) * 6.0 + t);
		col = mix(color_a.rgb, color_b.rgb, a * 0.5 + 0.5);
	} else if (style == 8) { // Candy: spinning stripes
		float s = sin(atan(p.x, p.z) * 4.0 + p.y * 3.0 - t * 3.0);
		col = mix(color_a.rgb, color_b.rgb, step(0.0, s));
	} else if (style == 9) { // Nebula: stars inside clouds
		m = fd_fbm(p * 0.9 + vec3(t * 0.2));
		float stars = step(0.985, fd_hash13(floor(p * 9.0)));
		col = mix(color_b.rgb * 0.4, color_a.rgb, m) + stars * 2.0;
	} else { // Plasma (default)
		m = fd_fbm(p + vec3(0.0, t * 1.4, t * 0.6));
		m = smoothstep(0.2, 0.85, m);
		col = mix(color_a.rgb, color_b.rgb, m * 0.65);
	}
	col += rim_color.rgb * fres * 1.6;
	col = mix(col, vec3(1.0, 0.95, 0.7), overdrive * 0.35 * (0.5 + 0.5 * sin(t * 20.0)));
	ALBEDO = col * (intensity + pulse);
}
