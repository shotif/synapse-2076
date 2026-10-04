// Rings that spread over the globe surface: shift-change pulses around
// cities and impact flashes where launch arcs land. Each instance is a quad
// lying on the surface (basis Y along the normal, instance scale = quad
// size); the ring grows from start_radius during each period and fades out.
// INSTANCE_CUSTOM: x = phase offset (0-1), y = size factor, z = index
// (instances with index >= active_count stay hidden).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.702, 0.0, 1.0);
// Layer focus multiplier.
uniform float intensity = 1.0;
// Overall alpha (metric driven).
uniform float strength = 1.0;
uniform float period = 4.0;
// The ring shows during the last (1 - window_start) of each period.
uniform float window_start = 0.0;
// Radii in globe units: start_radius + progress * (growth + growth_spread * size).
uniform float start_radius = 0.012;
uniform float growth = 0.06;
uniform float growth_spread = 0.048;
uniform float line_pixels = 1.2;
uniform float active_count = 1000.0;
uniform float limb_fade = 2.2;

varying float v_phase;
varying float v_size;
varying float v_index;
varying float v_half;
varying float v_fade;

void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
	v_size = INSTANCE_CUSTOM.y;
	v_index = INSTANCE_CUSTOM.z;
	v_half = length(MODEL_MATRIX[0].xyz) * 0.5;
	vec3 position = MODEL_MATRIX[3].xyz;
	vec3 normal = normalize(MODEL_MATRIX[1].xyz);
	v_fade = clamp(dot(normal, normalize(CAMERA_POSITION_WORLD - position)) * limb_fade, 0.0, 1.0);
}

void fragment() {
	float progress = fract(TIME / period + v_phase);
	progress = (progress - window_start) / max(1.0 - window_start, 0.001);
	float visible = step(0.0, progress) * (1.0 - step(active_count - 0.5, v_index));
	float ring_radius = (start_radius + max(progress, 0.0) * (growth + growth_spread * v_size)) / max(v_half, 0.0001);
	float d = length(UV * 2.0 - 1.0);
	float aa = max(fwidth(d), 0.0001);
	float ring = 1.0 - smoothstep(aa * 0.5 * line_pixels, aa * (0.5 * line_pixels + 1.0), abs(d - ring_radius));
	float alpha = ring * strength * (1.0 - clamp(progress, 0.0, 1.0)) * v_fade * visible * intensity;
	ALBEDO = color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
