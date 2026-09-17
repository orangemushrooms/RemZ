shader_type sky;

// Fixed studio reflection for the weapon viewport. In particular, do not use
// LIGHT*_ properties: changing the key light at dusk must not rebake this sky.
uniform vec3 top_color : source_color = vec3(0.26, 0.32, 0.42);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.66, 0.69);
uniform vec3 ground_color : source_color = vec3(0.12, 0.14, 0.11);
uniform vec3 ground_horizon : source_color = vec3(0.46, 0.47, 0.44);

void sky() {
	if (EYEDIR.y >= 0.0) {
		COLOR = mix(horizon_color, top_color, pow(EYEDIR.y, 0.15));
	} else {
		COLOR = mix(ground_horizon, ground_color, pow(-EYEDIR.y, 0.02));
	}
}
