// Opaque sea under every globe layer: a dark ocean with a soft highlight
// toward the upper left, like a night-side photograph lit by the atmosphere.
// It writes depth, so layers on the far hemisphere stay hidden.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

uniform vec4 sea_color : source_color = vec4(0.024, 0.039, 0.071, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.047, 0.086, 0.149, 1.0);
// View-space direction of the highlight.
uniform vec3 highlight_dir = vec3(-0.3, 0.35, 0.89);

void fragment() {
	float lit = smoothstep(-0.15, 1.0, dot(NORMAL, normalize(highlight_dir)));
	ALBEDO = mix(sea_color.rgb, highlight_color.rgb, lit * lit);
}
