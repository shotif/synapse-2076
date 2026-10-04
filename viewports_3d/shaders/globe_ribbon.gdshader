// Glowing lines over the globe that keep their width from every angle: the
// crests of the bloc walls and the launch arcs. GL lines are one pixel wide
// on WebGL, so each line point is two vertices (the line tangent in NORMAL,
// the side -1/+1 in UV.y) that the vertex shader pushes apart across the
// view direction. UV.x runs 0-1 along the line; UV2 = (line index, phase).
// With `animate`, a line draws itself from its start to a moving head (the
// arcs are launched in turn) and lines with index >= active_count stay hidden.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, skip_vertex_transform;

uniform vec4 color : source_color = vec4(1.0, 0.353, 0.431, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.82, 0.85, 1.0);
// Layer focus multiplier.
uniform float intensity = 1.0;
// Overall alpha (metric driven).
uniform float glow = 1.0;
// Half width in globe units, at least min_pixels.
uniform float width = 0.005;
uniform float min_pixels = 0.9;
// Added to every point's radius (the wall crest follows the wall height).
uniform float lift = 0.0;
uniform float heartbeat = 0.0;
uniform bool animate = false;
uniform float speed = 0.35;
uniform float active_count = 0.0;

varying float v_t;
varying float v_side;
varying float v_index;
varying float v_phase;

float beat(float t) {
	float p = mod(t, 1.15) / 1.15;
	return 1.0 + 0.6 * exp(-pow((p - 0.08) / 0.04, 2.0)) + 0.35 * exp(-pow((p - 0.26) / 0.04, 2.0));
}

void vertex() {
	vec3 point = normalize(VERTEX) * (length(VERTEX) + lift);
	vec3 p = (MODELVIEW_MATRIX * vec4(point, 1.0)).xyz;
	vec3 tangent = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 side = cross(tangent, p);
	float side_length = length(side);
	side = side_length > 0.000001 ? side / side_length : vec3(1.0, 0.0, 0.0);
	float pixel = 2.0 * -p.z / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	VERTEX = p + side * UV.y * max(width, min_pixels * pixel);
	v_t = UV.x;
	v_side = UV.y;
	v_index = UV2.x;
	v_phase = UV2.y;
}

void fragment() {
	float across = abs(v_side);
	float alpha = (1.0 - smoothstep(0.15, 1.0, across)) * glow;
	if (animate) {
		float launch = fract(TIME * speed + v_phase);
		float head = min(1.0, launch * 1.4);
		float shown = (1.0 - step(head, v_t)) * (1.0 - step(active_count - 0.5, v_index));
		alpha *= shown * mix(0.45, 1.0, smoothstep(head - 0.35, head, v_t));
	}
	alpha *= mix(1.0, beat(TIME), heartbeat);
	ALBEDO = mix(color.rgb, core_color.rgb, (1.0 - smoothstep(0.0, 0.5, across)) * 0.6);
	ALPHA = clamp(alpha * intensity, 0.0, 1.0);
}
