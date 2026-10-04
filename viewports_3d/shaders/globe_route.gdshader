// Particles riding great circles between two points on the globe: the agent
// swarm on the trade routes and the pulses on the undersea cables. All motion
// runs on the GPU. The instance basis carries the route instead of a pose:
// X = start, Y = end, Z = route plane normal (unit vectors), origin = globe
// center, so the node's spin still applies and no CPU work happens per frame.
//
// INSTANCE_CUSTOM: x = start position (0-1), y = speed (route lengths per
// second, signed), z = side offset (globe units), w = wander threshold (the
// particle leaves its route once free_share passes it).
// COLOR (raw data): x = phase, y = wobble, z / w = seeds for jitter / dropout.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, skip_vertex_transform;

uniform vec4 tint : source_color = vec4(1.0);
// Layer focus multiplier.
uniform float intensity = 1.0;
uniform float strength = 1.0;
// Route radius in globe units (1 = on the surface).
uniform float lift = 1.01;
uniform float dot_radius = 0.006;
uniform float min_pixels = 1.0;
// Trail length as a share of the route; 0 draws round dots.
uniform float trail = 0.0;
uniform float trail_alpha = 0.35;
// Swarm: share of particles that have left their routes (0-1).
uniform float free_share = 0.0;
// Cables: 0 = even, steady pulses; 1 = pulses jitter and drop out.
uniform float incoherence = 0.0;

varying float v_alpha;
varying float v_along;
varying float v_across;
varying float v_length;
varying float v_radius;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

vec3 slerp3(vec3 a, vec3 b, float t) {
	float angle = acos(clamp(dot(a, b), -1.0, 1.0));
	if (angle < 0.0001) {
		return a;
	}
	float s = sin(angle);
	return a * (sin((1.0 - t) * angle) / s) + b * (sin(t * angle) / s);
}

vec3 route_point(vec3 a, vec3 b, vec3 n, float u, float side, float wander, float phase, float wobble, float t) {
	vec3 v = slerp3(a, b, u);
	float amp = side + wander * (0.06 + 0.32 * free_share) * sin(t * 0.4 * wobble + phase);
	vec3 o = v + n * amp;
	o += normalize(cross(n, v)) * wander * 0.12 * free_share * cos(t * 0.3 * wobble + phase * 2.0);
	return normalize(o);
}

void vertex() {
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 a = MODEL_MATRIX[0].xyz / max(scale, 0.000001);
	vec3 b = normalize(MODEL_MATRIX[1].xyz);
	vec3 n = normalize(MODEL_MATRIX[2].xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	float t = TIME;
	float phase = COLOR.x * 6.2831853;
	float wobble = 0.6 + COLOR.y * 1.4;
	float speed = INSTANCE_CUSTOM.y;
	float u = fract(INSTANCE_CUSTOM.x + t * speed);
	float alpha = strength;
	if (incoherence > 0.0) {
		alpha *= 1.0 - step(hash11(COLOR.w * 97.0 + floor(t * 1.5)), incoherence * 0.55);
		u = fract(u + (hash11(COLOR.z * 89.0 + floor(t * 4.0)) - 0.5) * incoherence * 0.25 + 1.0);
	}
	// Fade in and out at the route ends instead of jumping back to the start.
	alpha *= smoothstep(0.0, 0.05, u) * (1.0 - smoothstep(0.95, 1.0, u));
	float wander = smoothstep(INSTANCE_CUSTOM.w - 0.04, INSTANCE_CUSTOM.w + 0.04, free_share);
	vec3 head = center + route_point(a, b, n, u, INSTANCE_CUSTOM.z, wander, phase, wobble, t) * lift * scale;
	vec3 head_view = (VIEW_MATRIX * vec4(head, 1.0)).xyz;
	vec3 tail_view = head_view;
	if (trail > 0.0) {
		float back = clamp(u - trail * sign(speed), 0.0, 1.0);
		vec3 tail = center + route_point(a, b, n, back, INSTANCE_CUSTOM.z, wander, phase, wobble, t - 0.05) * lift * scale;
		tail_view = (VIEW_MATRIX * vec4(tail, 1.0)).xyz;
	}
	float pixel = 2.0 * -head_view.z / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float r = max(dot_radius, min_pixels * pixel);
	vec2 axis = head_view.xy - tail_view.xy;
	float len = length(axis);
	vec2 along = len > 0.000001 ? axis / len : vec2(1.0, 0.0);
	vec2 across = vec2(-along.y, along.x);
	// QuadMesh corners are +-0.5: x = -0.5 at the tail, +0.5 at the head.
	vec2 corner = VERTEX.xy;
	float head_end = step(0.0, corner.x);
	vec3 base = mix(tail_view, head_view, head_end);
	base.xy += along * sign(corner.x) * r + across * corner.y * 2.0 * r;
	// Hidden particles collapse to a point (no fragments).
	VERTEX = alpha > 0.0001 ? base : head_view;
	v_alpha = alpha;
	v_along = mix(-r, len + r, head_end);
	v_across = corner.y * 2.0 * r;
	v_length = len;
	v_radius = r;
}

void fragment() {
	float r = max(v_radius, 0.000001);
	float to_head = length(vec2(v_along - v_length, v_across)) / r;
	float dot_alpha = 1.0 - smoothstep(0.45, 1.0, to_head);
	float body = 0.0;
	if (v_length > 0.0) {
		float along = clamp(v_along / v_length, 0.0, 1.0);
		body = (1.0 - smoothstep(0.25, 0.7, abs(v_across) / r)) * trail_alpha * along * step(0.0, v_along) * step(v_along, v_length);
	}
	ALBEDO = tint.rgb;
	ALPHA = clamp(max(dot_alpha, body) * v_alpha * intensity, 0.0, 1.0);
}
