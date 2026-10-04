shader_type canvas_item;
// Era II holographic scanlines drawn over the whole dashboard.

uniform float strength = 0.028;
uniform float pitch = 3.0;
uniform vec2 canvas_size = vec2(1600.0, 900.0);

void fragment() {
	float y = UV.y * canvas_size.y;
	COLOR = vec4(1.0, 1.0, 1.0, step(mod(y, pitch), 1.0) * strength);
}
