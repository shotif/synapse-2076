// Emissive hologram points (landmass dots, datacenter heat signatures, beams).
// Per-instance color comes from the MultiMesh; INSTANCE_CUSTOM.x adds a
// flicker phase. Additive glow with a soft fresnel falloff.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, specular_disabled, shadows_disabled;

uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float flicker_speed = 3.0;

varying float phase;

void vertex() {
	phase = INSTANCE_CUSTOM.x;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = mix(0.45, 1.0, facing);
	float wobble = 1.0 - flicker * 0.5 * (0.5 + 0.5 * sin(TIME * flicker_speed + phase * 6.2831));
	vec3 rgb = COLOR.rgb * core * intensity * wobble;
	ALBEDO = rgb;
	ALPHA = clamp(COLOR.a * core * wobble, 0.0, 1.0);
}
