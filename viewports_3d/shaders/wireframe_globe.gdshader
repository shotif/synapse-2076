// Graticule of the globe: latitude/longitude lines that warp with alignment
// drift (each pixel's lat/lon is displaced before the grid lines are
// computed) and tint toward the drift color. Optional fresnel rim, scan band
// and alert tint for the holographic looks. Line widths are measured in
// pixels from screen-space derivatives of the sphere position, so there is
// no seam at the date line. Additive and depth-read only: an opaque inner
// core hides the far hemisphere. GL Compatibility safe.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, specular_disabled, shadows_disabled;

uniform vec4 grid_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform vec4 drift_color : source_color = vec4(1.0, 0.478, 0.714, 1.0);
uniform float drift_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 alert_color : source_color = vec4(1.0, 0.09, 0.267, 1.0);
uniform float alert_mix : hint_range(0.0, 1.0) = 0.0;
// Number of bands between the poles / around the equator (6 and 12 = 30 degrees).
uniform float lat_lines = 18.0;
uniform float lon_lines = 36.0;
// Line width in pixels.
uniform float line_width : hint_range(0.2, 4.0) = 1.2;
uniform float grid_alpha : hint_range(0.0, 2.0) = 0.75;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.9;
uniform float scan_speed = 0.08;
uniform float scan_strength : hint_range(0.0, 2.0) = 0.35;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
// Alignment drift: how far the grid strays from true, in degrees.
uniform float warp = 0.0;
uniform float warp_speed = 1.0;
// Layer focus multiplier.
uniform float intensity = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

// 1 on a line, 0 off it, with a one-pixel soft edge; [param distance] and
// [param pixel] in degrees of arc.
float grid_line(float distance, float pixel) {
	float half_width = 0.5 * line_width * pixel;
	return 1.0 - smoothstep(half_width - 0.5 * pixel, half_width + 0.5 * pixel, distance);
}

void fragment() {
	vec3 p = normalize(local_pos);
	float lat_deg = degrees(asin(clamp(p.y, -1.0, 1.0)));
	float lon_deg = degrees(atan(p.z, p.x));
	float t = TIME * warp_speed;
	// Inverse of the warp field: where would this pixel sit on the true grid?
	float lat_w = lat_deg - warp * 0.6 * sin(radians(lon_deg) * 3.0 + t * 0.9);
	float lon_w = lon_deg - warp * sin(radians(lat_deg) * 4.0 + t * 1.3);
	// Degrees of arc covered by one pixel.
	float pixel = max(max(length(dFdx(p)), length(dFdy(p))) * 57.29578, 0.0001);
	float lat_step = 180.0 / max(lat_lines, 1.0);
	float lon_step = 360.0 / max(lon_lines, 1.0);
	float lat_dist = abs(fract(lat_w / lat_step - 0.5) - 0.5) * lat_step;
	float lon_dist = abs(fract(lon_w / lon_step - 0.5) - 0.5) * lon_step * cos(radians(lat_deg));
	// No parallels at the poles; meridians stop short of them, where they converge.
	float parallels = grid_line(lat_dist, pixel) * (1.0 - step(84.0, abs(lat_w)));
	float meridians = grid_line(lon_dist, pixel) * (1.0 - smoothstep(76.0, 84.0, abs(lat_deg)));
	float grid = max(parallels, meridians);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power) * rim_strength;
	float band = abs(fract(lat_deg / 180.0 + 0.5 - TIME * scan_speed) - 0.5);
	float scan = smoothstep(0.03, 0.0, band) * scan_strength;
	vec3 base = mix(mix(grid_color.rgb, drift_color.rgb, drift_mix), alert_color.rgb, alert_mix);
	float alpha = (grid * grid_alpha + rim + scan * 0.6) * glow_strength * (1.0 + 0.4 * pulse) * intensity;
	ALBEDO = base;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
