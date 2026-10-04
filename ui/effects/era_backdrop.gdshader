shader_type canvas_item;
// Dashboard background for each hardware era. Era I: flat black. Era II: a
// faint cyan graticule. Era III: two slow bioluminescent glows.

uniform int era = 1;
uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.9, 1.0, 0.045);
uniform vec4 glow_a : source_color = vec4(0.31, 0.94, 0.78, 0.09);
uniform vec4 glow_b : source_color = vec4(1.0, 0.37, 0.82, 0.09);
uniform float grid_size = 26.0;
uniform vec2 canvas_size = vec2(1600.0, 900.0);
// 0 freezes the Era III glows (reduced motion).
uniform float motion = 1.0;

float glow(vec2 px, vec2 center, float radius) {
	vec2 d = (px - center) / radius;
	return exp(-dot(d, d) * 1.6);
}

void fragment() {
	vec2 px = UV * canvas_size;
	vec3 col = base_color.rgb;
	if (era == 2) {
		vec2 cell = mod(px, grid_size);
		float line = clamp(step(cell.x, 1.0) + step(cell.y, 1.0), 0.0, 1.0);
		col = mix(col, line_color.rgb, line * line_color.a);
		// A little light falls from the top edge, like a projector.
		col += line_color.rgb * 0.035 * smoothstep(0.55, 0.0, UV.y);
	} else if (era == 3) {
		float t = TIME * 0.06 * motion;
		float radius = 0.55 * min(canvas_size.x, canvas_size.y);
		vec2 a = vec2(0.08 + 0.05 * sin(t), 0.32 + 0.05 * cos(t * 1.3)) * canvas_size;
		vec2 b = vec2(0.9 + 0.04 * cos(t * 0.8), 0.74 + 0.05 * sin(t * 1.1)) * canvas_size;
		col += glow_a.rgb * glow_a.a * glow(px, a, radius);
		col += glow_b.rgb * glow_b.a * glow(px, b, radius);
	}
	COLOR = vec4(col, 1.0);
}
