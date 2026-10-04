shader_type canvas_item;
// Screen-space glitch for the era change. mode 0: the old interface tears,
// splits into color channels, blurs and fades out. mode 1: the new interface
// settles in from a slight zoom and blur.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform int mode = 0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

vec3 sample_blurred(vec2 uv, float radius, vec2 split) {
	vec3 sum = vec3(0.0);
	vec2 offsets[5] = vec2[](vec2(0.0), vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
	for (int i = 0; i < 5; i++) {
		vec2 p = uv + offsets[i] * radius;
		sum.r += texture(screen_texture, p + split).r;
		sum.g += texture(screen_texture, p).g;
		sum.b += texture(screen_texture, p - split).b;
	}
	return sum / 5.0;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float a = clamp(amount, 0.0, 1.0);
	if (mode == 0) {
		float band = floor(uv.y * 28.0);
		float tick = floor(TIME * 24.0);
		uv.x += (hash(band * 17.0 + tick) - 0.5) * 0.05 * a * step(0.55, hash(band + tick * 3.0));
		uv.x += (uv.y - 0.5) * -0.06 * a;
	} else {
		uv = (uv - 0.5) / (1.0 + 0.04 * a) + 0.5;
	}
	vec3 col = sample_blurred(uv, 0.006 * a, vec2(0.012 * a * (mode == 0 ? 1.0 : 0.3), 0.0));
	float fade = mode == 0 ? a * 0.85 : a;
	COLOR = vec4(mix(col, fade_color.rgb, fade), 1.0);
}
