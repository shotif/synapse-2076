// Animated throughput along line meshes (undersea cables, lattice synapses).
// UV.x runs 0..1 along each line; pulses travel at flow_speed. Additive glow.
// UV.y carries the line's phase offset in its fractional part; lines that
// want dashes also pack their length (hundredths of a globe radius) into its
// integer part, which leaves the pulse phase unchanged.
//
// Coherence (epistemic trust on the cables): 1 keeps the pulses even and
// steady. Lower values jitter the pulses, drop some of them out and, with
// dash_gap > 0, break the line into dashes. The defaults keep the original
// look, so the neural lattice is unaffected.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

uniform vec4 line_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.25;
uniform float pulse_alpha : hint_range(0.0, 2.0) = 0.9;
uniform float flow_speed = 0.35;
uniform float pulse_count = 3.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float coherence : hint_range(0.0, 1.0) = 1.0;
// Dash and gap lengths along the line, in globe radii (needs the packed length).
uniform float dash_length = 0.03;
uniform float dash_gap = 0.0;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
	float offset = fract(UV.y);
	float line_length = floor(UV.y) * 0.01;
	float incoherence = 1.0 - coherence;
	float wave = UV.x * pulse_count - TIME * flow_speed + offset;
	float pulse_id = floor(wave);
	// Each pulse jumps around its slot and sometimes misses its beat.
	float jitter = (hash11(pulse_id * 7.0 + offset * 131.0 + floor(TIME * 4.0)) - 0.5) * incoherence * 0.5;
	float phase = fract(wave + jitter);
	float dropped = step(hash11(pulse_id * 31.0 + offset * 57.0 + floor(TIME * 1.5)), incoherence * 0.55);
	float pulse = smoothstep(0.82, 1.0, phase) * pulse_alpha * (1.0 - dropped);
	float dash = 1.0;
	if (dash_gap > 0.0 && line_length > 0.0) {
		float period = dash_length + dash_gap;
		dash = step(fract(UV.x * line_length / period), dash_length / period);
	}
	vec3 rgb = line_color.rgb * COLOR.rgb;
	float alpha = (base_alpha * dash + pulse) * COLOR.a * intensity;
	ALBEDO = rgb * alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
