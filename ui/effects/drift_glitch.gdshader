// Interface glitch driven by alignment drift: chromatic aberration (red and
// blue split sideways), bursts of horizontal tear bands and a short jitter at
// the end of each cycle. It samples the screen behind it, so it must be drawn
// on top of what it distorts. intensity 0 = no effect, 1 = drift 100.
// Offsets are in interface pixels (rect_size = the rect's canvas size).
// GL Compatibility / WebGL2 safe.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform float aberration_px = 3.2;
uniform float tear_px = 40.0;
uniform float jitter_px = 3.0;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
	vec2 px = 1.0 / max(rect_size, vec2(1.0));
	vec2 uv = SCREEN_UV;
	float g = intensity;
	vec2 shift = vec2(0.0);
	// Jitter: a three-step twitch near the end of every cycle; cycles shorten
	// as drift grows and the twitch starts around drift 62.
	float cycle = fract(TIME / (3.4 - 1.8 * g));
	vec2 twitch = vec2(0.0);
	if (cycle > 0.91 && cycle < 0.93) {
		twitch = vec2(-3.0, 1.0);
	} else if (cycle >= 0.93 && cycle < 0.95) {
		twitch = vec2(2.0, -1.0);
	} else if (cycle >= 0.95 && cycle < 0.97) {
		twitch = vec2(-1.0, 0.0);
	}
	shift += twitch * smoothstep(0.33, 0.4, g) * jitter_px / 3.0;
	// Tear bands: five ticks a second; a tick tears with probability 0.45 * g
	// into one to three bands, 3-17 px tall, shifted sideways.
	float tick = floor(TIME * 5.0);
	float torn = 0.0;
	if (hash11(tick) < g * 0.45) {
		float bands = 1.0 + floor(hash11(tick + 3.0) * 3.0);
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			float top = hash11(tick * 7.0 + fk) * (1.0 - 20.0 * px.y);
			float height = (3.0 + floor(hash11(tick * 11.0 + fk) * 14.0)) * px.y;
			float inside = step(fk + 0.5, bands) * step(top, uv.y) * (1.0 - step(top + height, uv.y));
			shift.x += inside * (hash11(tick * 13.0 + fk) - 0.5) * tear_px * g;
			torn = max(torn, inside);
		}
	}
	vec2 base = uv - shift * px;
	// A steady split keeps text legible; the tear bands split fully.
	float split = aberration_px * g * mix(0.4, 1.0, torn) * px.x;
	float red = texture(screen_texture, base + vec2(split, 0.0)).r;
	float green = texture(screen_texture, base).g;
	float blue = texture(screen_texture, base - vec2(split, 0.0)).b;
	COLOR = vec4(red, green, blue, 1.0);
}
