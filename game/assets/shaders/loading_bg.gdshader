// FLUX DROP loading screen backdrop (ART_DIRECTION §10). At reveal 0 it is the
// boot splash exactly: the splash colour with one soft glow behind the emblem
// (the splash image is rendered from this same screen). As reveal rises, thin
// speed streaks fall past (the drop down the shaft) and the flux sink glows
// at the bottom edge. Layout is in "square space": the centred square of side
// min(width, height) that the boot splash image fills.
shader_type canvas_item;

uniform vec4 base : source_color = vec4(0.016, 0.02, 0.047, 1.0);
uniform vec4 glow : source_color = vec4(0.27, 0.9, 0.94, 1.0);
// Emblem glow centre and radius in square space (0..1).
uniform vec2 glow_center = vec2(0.5, 0.42);
uniform float glow_radius = 0.24;
uniform float glow_strength = 0.16;
uniform float reveal = 0.0;
// Control size in pixels (set by LoadingScreen).
uniform vec2 size = vec2(720.0, 1280.0);

float hash(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void fragment() {
	vec2 px = UV * size;
	float side = min(size.x, size.y);
	vec2 sq = (px - vec2((size.x - side) * 0.5, (size.y - side) * 0.5)) / side;
	vec3 col = base.rgb;
	float d = length(sq - glow_center) / glow_radius;
	col += glow.rgb * glow_strength * exp(-d * d * 2.2);
	if (reveal > 0.0) {
		// Speed streaks: sparse thin lines falling at different speeds.
		float columns = 46.0;
		float x = UV.x * columns;
		float id = floor(x);
		float h = hash(id);
		float line = 1.0 - smoothstep(0.0, 0.08, abs(fract(x) - 0.5));
		float y0 = fract(h * 7.3 + TIME * (0.25 + h * 0.6)) * 1.4 - 0.2;
		float tail = 0.08 + 0.12 * hash(id + 3.0);
		float streak = smoothstep(y0 - tail, y0, UV.y) * step(UV.y, y0) * step(0.55, h);
		col += mix(glow.rgb, vec3(1.0), 0.4) * streak * line * 0.22 * reveal;
		// The flux sink: a wide glow rising from the bottom edge.
		float sink = exp(-pow((1.0 - UV.y) * 4.5, 2.0)) * (1.0 - smoothstep(0.0, 0.7, abs(UV.x - 0.5)));
		col += glow.rgb * sink * 0.18 * reveal;
	}
	// Soft vignette keeps the edges calm.
	float v = smoothstep(1.25, 0.45, length((UV - 0.5) * vec2(1.0, 0.8)) * 1.6);
	col *= mix(1.0, mix(0.75, 1.0, v), reveal);
	COLOR = vec4(col, 1.0);
}
