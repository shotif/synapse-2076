// Atmosphere halo: a glow that starts at the limb and fades out by
// outer_radius. Each pixel measures how far its view ray passes from the
// globe center (the impact parameter), so the halo reads as an even radial
// gradient from every camera angle. A thin rim just inside the limb lifts
// the sea's edge off the background.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, specular_disabled;

uniform vec4 glow_color : source_color = vec4(0.27, 0.55, 1.0, 1.0);
uniform float strength = 0.22;
uniform float rim_strength = 0.12;
uniform float globe_radius = 1.0;
uniform float inner_radius = 0.97;
uniform float outer_radius = 1.2;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ray = normalize(world_position - CAMERA_POSITION_WORLD);
	vec3 to_center = NODE_POSITION_WORLD - CAMERA_POSITION_WORLD;
	float b = length(cross(ray, to_center)) / globe_radius;
	// Outside the sea: a linear fade like a radial gradient.
	float halo = clamp(1.0 - (b - inner_radius) / (outer_radius - inner_radius), 0.0, 1.0) * step(0.997, b);
	// Inside the sea: a thin rim along the limb.
	float rim = smoothstep(0.9, 0.997, b) * (1.0 - step(0.997, b));
	float alpha = halo * strength + rim * rim * rim_strength;
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
