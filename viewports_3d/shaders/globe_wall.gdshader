// Bloc walls: translucent curtains standing on the globe along the fault
// lines between blocs. The mesh is built once with UV.y = 0 at the foot and
// 1 at the crest; the vertex shader raises the crest to `height`, so the
// walls grow with geopolitical tension without rebuilding geometry. Vertical
// ribs every rib_spacing (UV.x is arc length) and a brighter crest; above
// the heartbeat threshold the glow pulses like a heartbeat.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.2, 0.333, 1.0);
// Layer focus multiplier.
uniform float intensity = 1.0;
// Crest height above the surface, in globe radii.
uniform float height = 0.02;
uniform float base_radius = 1.002;
// Tension 0-1: alpha of the ribs and sheet.
uniform float glow = 0.4;
// 0-1: how much of the heartbeat pulse applies.
uniform float heartbeat = 0.0;
uniform float rib_spacing = 0.018;

float beat(float t) {
	float p = mod(t, 1.15) / 1.15;
	return 1.0 + 0.6 * exp(-pow((p - 0.08) / 0.04, 2.0)) + 0.35 * exp(-pow((p - 0.26) / 0.04, 2.0));
}

void vertex() {
	VERTEX = normalize(VERTEX) * (base_radius + UV.y * height);
}

void fragment() {
	float pulse = mix(1.0, beat(TIME), heartbeat);
	float rib_coord = UV.x / rib_spacing;
	float rib_dist = abs(fract(rib_coord + 0.5) - 0.5);
	float rib = 1.0 - smoothstep(0.0, max(fwidth(rib_coord) * 1.2, 0.0001), rib_dist);
	float sheet = mix(0.12, 0.5, UV.y * UV.y);
	float crest = smoothstep(0.75, 1.0, UV.y);
	float alpha = (0.1 + glow * 0.32) * (rib * 0.8 + sheet) + crest * (0.15 + glow * 0.45);
	ALBEDO = color.rgb;
	ALPHA = clamp(alpha * pulse * intensity, 0.0, 1.0);
}
