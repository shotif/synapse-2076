// Tensor loss landscape under the neural lattice: a wireframe surface whose
// ruggedness and heat grow with alignment drift (smooth basin when aligned,
// chaotic ridges under deceptive misalignment).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

uniform vec4 low_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform vec4 high_color : source_color = vec4(1.0, 0.09, 0.267, 1.0);
uniform float drift_level : hint_range(0.0, 1.0) = 0.15;
uniform float amplitude = 0.55;
uniform float grid_density = 28.0;

varying float height;

float surface(vec2 p, float rough) {
	float basin = 0.35 * dot(p, p) * 0.08;
	float waves = sin(p.x * 1.3 + TIME * 0.3) * cos(p.y * 1.1 - TIME * 0.2);
	float ridges = sin(p.x * 3.7 + p.y * 2.9 + TIME * 0.9) * sin(p.y * 4.3 - TIME * 0.7);
	float shards = sin(p.x * 9.0 + TIME * 2.3) * cos(p.y * 8.0 - TIME * 1.9);
	return basin + waves * (0.25 + 0.5 * rough) + ridges * 0.6 * rough * rough + shards * 0.25 * rough * rough * rough;
}

void vertex() {
	float rough = clamp(drift_level, 0.0, 1.0);
	height = surface(VERTEX.xz, rough);
	VERTEX.y += height * amplitude;
}

void fragment() {
	vec2 cell = UV * grid_density;
	vec2 dist = abs(fract(cell - 0.5) - 0.5);
	vec2 px = max(fwidth(cell), vec2(0.0001));
	float line = 1.0 - smoothstep(0.0, 1.2, min(dist.x / px.x, dist.y / px.y));
	float heat = clamp(height * 0.5 + 0.5, 0.0, 1.0);
	vec3 color = mix(low_color.rgb, high_color.rgb, clamp(drift_level * 1.2 + heat * drift_level, 0.0, 1.0));
	float edge_fade = smoothstep(0.0, 0.18, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	float alpha = (line * 0.55 + 0.03) * edge_fade;
	ALBEDO = color * alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
