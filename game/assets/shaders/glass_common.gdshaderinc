// FLUX DROP breakable glass surface, shared by the Voronoi variant
// (glass.gdshader, High and Ultra) and the analytic one (glass_lite.gdshader,
// Low and Medium): same tint, transparency and dark, never glowing cracks.

vec3 fd_glass_albedo(float crack, vec3 tint) {
	return mix(tint, tint * 0.35, crack);
}

float fd_glass_roughness(float crack) {
	return mix(0.08, 0.5, crack);
}

float fd_glass_alpha(float crack, float fres, float base_alpha) {
	return clamp(base_alpha + fres * 0.4 + crack * 0.3, 0.0, 0.95);
}
