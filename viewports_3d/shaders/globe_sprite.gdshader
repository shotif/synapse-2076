// Camera-facing sprites pinned to the globe: landmass dots, city lights,
// crowds and the glows over cities and datacenters. One MultiMesh of quads
// per layer; each instance sits on the globe with its basis Y along the
// surface normal, and the vertex shader rebuilds the quad in view space so
// it always faces the camera. Sprites fade toward the limb and vanish on the
// far side (a facing test rather than a depth test, so large blooms are not
// cut by the globe), and hidden sprites collapse to a point (no fragments).
//
// INSTANCE_CUSTOM: x = threshold (hidden while x < cutoff), y = brightness,
// z = size factor (or orbit distance factor), w = phase (0-1).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, specular_disabled, skip_vertex_transform;

uniform vec4 color : source_color = vec4(1.0);
uniform vec4 core_color : source_color = vec4(1.0);
// Layer focus multiplier.
uniform float intensity = 1.0;
// Overall alpha (metric driven).
uniform float strength = 1.0;
// Radius in globe units: radius + radius_spread * size factor, at least min_pixels.
uniform float radius = 0.006;
uniform float radius_spread = 0.0;
uniform float min_pixels = 0.8;
uniform float shrink_at_limb = 0.0;
// Alpha at the limb relative to the center of the disc, and how fast it fades.
uniform float facing_floor = 0.0;
uniform float limb_fade = 2.2;
uniform float cutoff = -1.0;
// 0 = soft dot; 1 = radial bloom from core_color to color.
uniform float bloom = 0.0;
// Dots: 0 = round, 1 = square (crisper at one or two pixels).
uniform float square = 0.0;
// Bloom profile: alpha 1 at the center, bloom_mid at bloom_stop, 0 at the edge.
uniform float bloom_stop = 0.25;
uniform float bloom_mid = 0.65;
uniform float color_stop = 0.25;
// Heat shimmer: two elliptical rings around the bloom (the quad is 1.35x the bloom).
uniform float rings = 0.0;
// Brownout: share of 1/7 s ticks during which the layer dims to 45%.
uniform float flicker_chance = 0.0;
// Crowds: circle the instance origin at orbit * (1 + 1.25 * size factor).
uniform float orbit = 0.0;

varying float v_alpha;
varying float v_phase;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	vec3 normal = normalize(MODEL_MATRIX[1].xyz);
	vec3 position = MODEL_MATRIX[3].xyz;
	if (orbit > 0.0) {
		float angle = INSTANCE_CUSTOM.w * 6.2831853 + sin(TIME * 0.7 + INSTANCE_CUSTOM.w * 37.0) * 0.3;
		float reach = orbit * (1.0 + 1.25 * INSTANCE_CUSTOM.z);
		position += (normalize(MODEL_MATRIX[0].xyz) * cos(angle) + normalize(MODEL_MATRIX[2].xyz) * sin(angle)) * reach;
	}
	float facing = dot(normal, normalize(CAMERA_POSITION_WORLD - position));
	vec3 center = (VIEW_MATRIX * vec4(position, 1.0)).xyz;
	float pixel = 2.0 * -center.z / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = (radius + radius_spread * INSTANCE_CUSTOM.z) * mix(1.0, clamp(facing, 0.0, 1.0), shrink_at_limb);
	size = max(size, min_pixels * pixel);
	if (rings > 0.0) {
		size *= 1.35;
	}
	float fade = facing <= 0.0 ? 0.0 : mix(facing_floor, 1.0, clamp(facing * limb_fade, 0.0, 1.0));
	float dim = 1.0;
	if (flicker_chance > 0.0 && hash11(floor(TIME * 7.0)) < flicker_chance) {
		dim = 0.45;
	}
	v_alpha = fade * INSTANCE_CUSTOM.y * dim * step(cutoff, INSTANCE_CUSTOM.x) * strength;
	v_phase = INSTANCE_CUSTOM.w;
	// QuadMesh corners are +-0.5; hidden sprites collapse to their center.
	VERTEX = center + vec3(VERTEX.xy * 2.0 * size * step(0.0001, v_alpha), 0.0);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	vec3 rgb = color.rgb;
	float alpha;
	if (bloom > 0.5) {
		float g = rings > 0.0 ? d * 1.35 : d;
		alpha = g < bloom_stop ? mix(1.0, bloom_mid, g / max(bloom_stop, 0.0001))
			: bloom_mid * max(0.0, 1.0 - (g - bloom_stop) / max(1.0 - bloom_stop, 0.0001));
		rgb = mix(core_color.rgb, color.rgb, smoothstep(0.0, color_stop, g));
		if (rings > 0.0) {
			for (int k = 0; k < 2; k++) {
				float fk = float(k);
				float ring_radius = 0.74 * (0.9 + 0.35 * fk) + sin(TIME * 3.0 + v_phase * 6.2831853 + fk * 2.0) * 0.035;
				float e = length(vec2(q.x, (q.y + fk * 0.06) / 0.6));
				float aa = max(fwidth(e), 0.0001);
				float line = 1.0 - smoothstep(0.0, aa * 1.5, abs(e - ring_radius));
				alpha = max(alpha, line * 0.35 * rings);
			}
		}
	} else {
		d = mix(d, max(abs(q.x), abs(q.y)), square);
		alpha = 1.0 - smoothstep(0.45, 1.0, d);
	}
	if (d > 1.0) {
		alpha = 0.0;
	}
	ALBEDO = rgb;
	ALPHA = clamp(alpha * v_alpha * intensity, 0.0, 1.0);
}
