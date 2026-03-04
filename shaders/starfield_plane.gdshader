shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Plane-based starfield: no sphere projection, so no stretching. Zoom-friendly.

uniform vec3 space_color : source_color = vec3(0.02, 0.02, 0.05);
uniform float star_twinkle_speed : hint_range(0.0, 3.0) = 1.2;
uniform float star_twinkle_amount : hint_range(0.0, 1.0) = 0.45;  // how much stars dim/brighten
uniform float star_oscillation_speed : hint_range(0.0, 2.0) = 0.5;
uniform float star_oscillation_strength : hint_range(0.0, 0.3) = 0.12;
uniform float sky_seed : hint_range(0.0, 10000.0) = 0.0;

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

vec3 stars_2d(vec2 uv, float cell_count, float threshold, float brightness, float seed_offset) {
	vec2 grid = uv * cell_count;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;

	vec3 seed3 = vec3(cell + vec2(seed_offset * 31.7, 0.0), sky_seed);
	float pick = hash3(seed3);
	float has_star = step(threshold, pick);

	vec2 jitter = vec2(
		hash3(seed3 + vec3(11.7, 17.3, 3.1)),
		hash3(seed3 + vec3(27.1, 5.9, 13.7))
	) - 0.5;
	local -= jitter * 0.6;

	// Circular stars - no projection distortion
	float star_size = mix(0.008, 0.035, hash3(seed3 + vec3(3.1, 9.7, 41.3)));
	float d = length(local);
	float core = smoothstep(star_size, 0.0, d);
	float glow = smoothstep(star_size * 2.5, 0.0, d) * 0.2;

	// Stronger twinkle
	float twinkle = 1.0 - star_twinkle_amount + star_twinkle_amount * (0.5 + 0.5 * sin(TIME * (star_twinkle_speed + pick * 2.5) + pick * 97.0));
	float oscillation = 1.0 + star_oscillation_strength * sin(
		TIME * (star_oscillation_speed + pick * 0.5) + uv.x * 20.0 + uv.y * 17.0
	);

	float color_hash = hash3(seed3 + vec3(77.0, 33.0, 11.0));
	vec3 star_color = mix(vec3(0.5, 0.7, 1.0), vec3(1.0, 0.95, 0.9), smoothstep(0.0, 0.5, color_hash));
	star_color = mix(star_color, vec3(1.0, 0.4, 0.15), smoothstep(0.5, 1.0, color_hash));

	float intensity = has_star * (core + glow) * twinkle * oscillation * brightness;
	return star_color * intensity;
}

void fragment() {
	vec2 uv = UV;

	// More layers, lower thresholds = denser starfield
	vec3 s1 = stars_2d(uv, 180.0, 0.48, 0.6, 0.0);
	vec3 s2 = stars_2d(uv, 120.0, 0.58, 1.0, 100.0);
	vec3 s3 = stars_2d(uv, 70.0, 0.68, 1.4, 200.0);
	vec3 s4 = stars_2d(uv, 35.0, 0.78, 2.0, 300.0);

	vec3 col = space_color + (s1 + s2 + s3 + s4) * 1.15;

	ALBEDO = col;
	EMISSION = col * 0.5;  // subtle glow
}
