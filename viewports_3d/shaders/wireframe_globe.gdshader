// Holographic wireframe Earth (PRD section 8.2): glowing latitude/longitude
// vector lines, fresnel rim, a sweeping scan band and an alert tint driven by
// geopolitical tension. Additive and depth-read only, so an opaque inner core
// occludes the far hemisphere. Compatible with the GL Compatibility renderer.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, specular_disabled, shadows_disabled;

uniform vec4 grid_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform vec4 alert_color : source_color = vec4(1.0, 0.09, 0.267, 1.0);
uniform float alert_mix : hint_range(0.0, 1.0) = 0.0;
uniform float lat_lines = 18.0;
uniform float lon_lines = 36.0;
uniform float line_width : hint_range(0.2, 4.0) = 1.2;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float scan_speed = 0.08;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float grid_line(float coord, float count, float width) {
	float scaled = coord * count;
	float distance_to_line = abs(fract(scaled - 0.5) - 0.5);
	float pixel = max(fwidth(scaled), 0.0001);
	return 1.0 - smoothstep(0.0, pixel * width, distance_to_line);
}

void fragment() {
	vec3 p = normalize(local_pos);
	float lat = asin(clamp(p.y, -1.0, 1.0)) / PI + 0.5;
	float lon = atan(p.z, p.x) / (2.0 * PI) + 0.5;
	float grid = max(grid_line(lat, lat_lines, line_width), grid_line(lon, lon_lines, line_width));
	// Fade meridians toward the poles where they converge.
	grid *= mix(0.35, 1.0, smoothstep(0.0, 0.12, 0.5 - abs(lat - 0.5)));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float band = abs(fract(lat - TIME * scan_speed) - 0.5);
	float scan = smoothstep(0.03, 0.0, band) * 0.6;
	vec3 base = mix(grid_color.rgb, alert_color.rgb, alert_mix);
	float intensity = (grid * 0.75 + rim * 0.9 + scan * 0.35) * glow_strength * (1.0 + 0.4 * pulse);
	ALBEDO = base * intensity;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
