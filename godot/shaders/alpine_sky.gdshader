shader_type sky;
render_mode use_debanding;

// One panorama lookup in the existing sky pass. The clock supplies uniforms
// at a bounded rate; no TIME/POSITION dependency or extra rendering pass.
uniform sampler2D alpine_panorama : filter_linear_mipmap, repeat_enable;
// Fixed geographic rotation of the Alpine horizon; the live sun moves separately.
uniform float panorama_rotation = -0.01;
uniform float elevation_scale = 3.0;
uniform float exposure = 0.8;
uniform vec3 horizon_color : source_color = vec3(0.69, 0.74, 0.77);
uniform vec3 zenith_color : source_color = vec3(0.37, 0.51, 0.68);
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float twilight : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(-0.6, 0.4, 0.69);

void sky() {
	vec2 uv = SKY_COORDS;
	uv.x = fract(uv.x + panorama_rotation);
	// Compress the photographed valley into distant, low horizon ranges.
	float compression = mix(elevation_scale, 2.0, smoothstep(0.1, 0.3, EYEDIR.y));
	uv.y = clamp((uv.y - 0.5) * compression + 0.5, 0.015, 0.985);
	vec3 panorama = min(texture(alpine_panorama, uv).rgb * exposure, vec3(1.2));
	panorama *= vec3(1.04, 1.0, 0.94);
	float haze = 1.0 - smoothstep(-0.025, 0.19, EYEDIR.y);
	vec3 distant = mix(panorama, horizon_color, 0.14 + haze * 0.36);
	// A calm upper sky avoids stretching the zenith of the compressed photo.
	float up = clamp(EYEDIR.y, 0.0, 1.0);
	// Keep the mountain silhouette fixed. Replace the photographed upper sky
	// (including its baked sun) so it cannot remain visible during the night.
	vec3 sunset = vec3(0.85, 0.32, 0.13);
	float sun_facing = pow(max(dot(normalize(vec3(EYEDIR.x, 0.001, EYEDIR.z)), normalize(vec3(sun_direction.x, 0.001, sun_direction.z))), 0.0), 3.0);
	vec3 horizon = mix(horizon_color, sunset, twilight * (0.25 + sun_facing * 0.55));
	vec3 upper_sky = mix(horizon, zenith_color, sqrt(up));
	vec3 night_sky = mix(vec3(0.045, 0.067, 0.11), vec3(0.007, 0.014, 0.033), sqrt(up));
	upper_sky = mix(night_sky, upper_sky, daylight);
	vec3 night_ranges = distant * vec3(0.045, 0.067, 0.11);
	distant = mix(night_ranges, distant * mix(vec3(1.0), vec3(1.07, 0.76, 0.61), twilight * 0.55), daylight);
	float photographic_brightness = dot(panorama, vec3(0.2126, 0.7152, 0.0722));
	float blue_sky = smoothstep(0.025, 0.065, panorama.b - max(panorama.r, panorama.g));
	float bright_sky = max(blue_sky, smoothstep(0.5, 0.85, photographic_brightness)) * smoothstep(0.13, 0.25, up);
	float sky_mask = max(smoothstep(0.28, 0.40, up), bright_sky);
	distant = mix(distant, upper_sky, sky_mask);
	// Keep the photographic foreground out of the scenery beyond the map edge.
	float below_horizon = 1.0 - smoothstep(-0.16, -0.015, EYEDIR.y);
	vec3 ground_haze = mix(vec3(0.024, 0.038, 0.066), horizon * vec3(0.72, 0.77, 0.76), daylight);
	COLOR = mix(distant, ground_haze, below_horizon);
	if (!AT_CUBEMAP_PASS) {
		// Tiny analytic discs and fixed stars; no textures, particles or lights.
		float sun_distance = distance(EYEDIR, sun_direction);
		float sun_disc = 1.0 - smoothstep(0.004, 0.006, sun_distance);
		float sun_glow = exp(-sun_distance * 35.0) * 0.3;
		COLOR += vec3(1.0, 0.76, 0.44) * (sun_disc * 5.0 + sun_glow) * smoothstep(0.0, 0.08, sun_direction.y) * sky_mask;
		float night = 1.0 - smoothstep(0.0, 0.35, daylight);
		float moon_distance = distance(EYEDIR, -sun_direction);
		float moon = 1.0 - smoothstep(0.004, 0.0065, moon_distance);
		COLOR += vec3(0.55, 0.66, 0.86) * (moon * 0.65 + exp(-moon_distance * 55.0) * 0.015) * night * sky_mask;
		vec2 star_uv = SKY_COORDS * vec2(1100.0, 550.0);
		float star_hash = fract(sin(dot(floor(star_uv), vec2(127.1, 311.7))) * 43758.5453);
		float star = step(0.996, star_hash) * (1.0 - smoothstep(0.035, 0.22, length(fract(star_uv) - 0.5)));
		COLOR += vec3(0.32, 0.4, 0.54) * star * night * sky_mask;
	}
}
