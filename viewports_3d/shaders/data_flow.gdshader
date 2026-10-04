// Animated throughput along line meshes (undersea cables, lattice synapses).
// UV.x runs 0..1 along each line; pulses travel at flow_speed. Additive glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

uniform vec4 line_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.25;
uniform float pulse_alpha : hint_range(0.0, 2.0) = 0.9;
uniform float flow_speed = 0.35;
uniform float pulse_count = 3.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	float phase = fract(UV.x * pulse_count - TIME * flow_speed + UV.y);
	float pulse = smoothstep(0.82, 1.0, phase) * pulse_alpha;
	vec3 rgb = line_color.rgb * COLOR.rgb;
	float alpha = (base_alpha + pulse) * COLOR.a * intensity;
	ALBEDO = rgb * alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
