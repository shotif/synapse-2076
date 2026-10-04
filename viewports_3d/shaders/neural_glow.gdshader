// Neural lattice nodes (PRD section 8.2): cold cyan when aligned, shifting to
// erratic crimson with vertex jitter as alignment drift accumulates.
// MultiMesh INSTANCE_CUSTOM: x = phase, y = susceptibility (0-1),
// z = emergent-capability flag, w = layer depth (0-1).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, specular_disabled, shadows_disabled;

uniform vec4 cold_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.09, 0.267, 1.0);
uniform vec4 emergent_color : source_color = vec4(1.0, 0.702, 0.0, 1.0);
uniform float drift_level : hint_range(0.0, 1.0) = 0.15;
uniform float jitter_amplitude = 0.9;
uniform float activity : hint_range(0.0, 1.0) = 0.5;

varying float instability;
varying float phase;
varying float emergent;
varying float depth;
varying flat float flicker;

void vertex() {
	phase = INSTANCE_CUSTOM.x;
	emergent = INSTANCE_CUSTOM.z;
	depth = INSTANCE_CUSTOM.w;
	instability = clamp(drift_level * (0.35 + 0.9 * INSTANCE_CUSTOM.y) + emergent * 0.25 * drift_level, 0.0, 1.0);
	float strength = jitter_amplitude * instability * instability;
	vec3 shake = vec3(
		sin(TIME * 23.0 + phase * 41.0),
		sin(TIME * 31.0 + phase * 17.0),
		sin(TIME * 19.0 + phase * 29.0));
	// Same offset for every vertex of the instance: the whole node jitters.
	VERTEX += shake * strength;
	// Per-instance stutter: unstable neurons drop out erratically.
	float glitch = step(0.7, fract(sin(floor(TIME * 12.0) * 12.9898 + phase * 78.233) * 437.585));
	flicker = 1.0 - instability * 0.6 * glitch;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0);
	float firing = 0.55 + 0.45 * sin(TIME * (1.5 + 4.0 * activity) - depth * 6.0 + phase * 3.0);
	vec3 base = mix(cold_color.rgb, hot_color.rgb, smoothstep(0.15, 0.85, instability));
	base = mix(base, emergent_color.rgb, emergent * 0.75);
	float intensity = (0.35 + 0.65 * facing + rim * 0.8) * (0.6 + 0.6 * firing) * flicker;
	ALBEDO = base * intensity * 1.3;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
