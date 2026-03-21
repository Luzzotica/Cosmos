shader_type sky;

// starfield_sky_v3: Flat-plane starfield (EYEDIR.xz / EYEDIR.y projection)
// Adapted from v1 - no cuboid, no rotation, no edge_fade

uniform vec3 space_color : source_color = vec3(0.02, 0.02, 0.05);

uniform float star_height : hint_range(0.1, 50.0) = 5.0;
uniform float star_blend : hint_range(0.0, 1.0) = 0.1;
uniform float star_twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform float star_oscillation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float star_oscillation_strength : hint_range(0.0, 0.3) = 0.08;
uniform float sky_seed : hint_range(0.0, 10000.0) = 0.0;
uniform vec3 parallax_offset = vec3(0.0, 0.0, 0.0);
uniform float star_zoom_scale : hint_range(1.0, 1.25) = 1.0;
uniform float parallax_drift_strength : hint_range(0.0, 0.1) = 0.016;
uniform float parallax_strength : hint_range(0.0, 10.0) = 1.0;
uniform float parallax_drift_speed_x : hint_range(0.0, 2.0) = 0.18;
uniform float parallax_drift_speed_z : hint_range(0.0, 2.0) = 0.14;

uniform float star_grid_density : hint_range(0.01, 1.0) = 0.1;
uniform float star_jitter_amount : hint_range(0.0, 1.0) = 0.6;
uniform float star_size_min : hint_range(0.001, 0.2) = 0.012;
uniform float star_size_max : hint_range(0.01, 0.2) = 0.04;
uniform float star_glow_radius_mult : hint_range(1.0, 6.0) = 2.5;
uniform float star_glow_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float star_twinkle_min : hint_range(0.0, 1.0) = 0.8;
uniform float star_twinkle_amount : hint_range(0.0, 1.0) = 0.2;
uniform float star_twinkle_freq_scale : hint_range(0.0, 5.0) = 2.0;
uniform float star_twinkle_phase : hint_range(0.0, 200.0) = 97.0;
uniform float star_oscillation_phase_scale : hint_range(0.0, 2.0) = 0.5;
uniform vec2 star_oscillation_cell_scale = vec2(8.0, 11.0);
uniform vec3 star_color_blue : source_color = vec3(0.5, 0.7, 1.0);
uniform vec3 star_color_white : source_color = vec3(1.0, 0.95, 0.9);
uniform vec3 star_color_orange : source_color = vec3(1.0, 0.4, 0.15);
uniform float star_color_mid : hint_range(0.0, 1.0) = 0.5;
uniform float star_output_scale : hint_range(0.0, 5.0) = 1.1;

uniform float star_layer1_cells : hint_range(1.0, 500.0) = 130.0;
uniform float star_layer1_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float star_layer1_brightness : hint_range(0.0, 5.0) = 0.5;
uniform float star_layer1_seed : hint_range(0.0, 500.0) = 0.0;
uniform float star_layer1_parallax : hint_range(0.0, 5.0) = 0.5;
uniform float star_layer2_cells : hint_range(1.0, 500.0) = 90.0;
uniform float star_layer2_threshold : hint_range(0.0, 1.0) = 0.65;
uniform float star_layer2_brightness : hint_range(0.0, 5.0) = 0.9;
uniform float star_layer2_seed : hint_range(0.0, 500.0) = 100.0;
uniform float star_layer2_parallax : hint_range(0.0, 5.0) = 1.0;
uniform float star_layer3_cells : hint_range(1.0, 500.0) = 50.0;
uniform float star_layer3_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float star_layer3_brightness : hint_range(0.0, 5.0) = 1.25;
uniform float star_layer3_seed : hint_range(0.0, 500.0) = 200.0;
uniform float star_layer3_parallax : hint_range(0.0, 5.0) = 1.5;
uniform float star_layer4_cells : hint_range(1.0, 500.0) = 25.0;
uniform float star_layer4_threshold : hint_range(0.0, 1.0) = 0.85;
uniform float star_layer4_brightness : hint_range(0.0, 5.0) = 1.9;
uniform float star_layer4_seed : hint_range(0.0, 500.0) = 300.0;
uniform float star_layer4_parallax : hint_range(0.0, 5.0) = 2.0;

// --- HASH ---
float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

// --- STAR GENERATION (flat plane: uv = plane coords, no cuboid/edge_fade) ---
// TIME passed as param: compatibility renderer doesn't expose built-ins inside custom functions.
vec3 stars_plane(vec2 uv, float cell_count, float threshold, float brightness, float seed_offset, float zoom_scale, float shader_time) {
	vec2 grid = uv * cell_count * star_grid_density * zoom_scale;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;

	vec3 seed3 = vec3(cell.x, cell.y, seed_offset + sky_seed * 0.1);
	float pick = hash3(seed3);
	float has_star = step(threshold, pick);

	vec2 jitter = vec2(
		hash3(seed3 + vec3(11.7, 17.3, 3.1)),
		hash3(seed3 + vec3(27.1, 5.9, 13.7))
	) - 0.5;
	local -= jitter * star_jitter_amount;

	float star_size = mix(star_size_min, star_size_max, hash3(seed3 + vec3(3.1, 9.7, 41.3)));
	float d = length(local);
	float core = smoothstep(star_size, 0.0, d);
	float glow = smoothstep(star_size * star_glow_radius_mult, 0.0, d) * star_glow_intensity;
	float twinkle = star_twinkle_min + star_twinkle_amount * sin(shader_time * (star_twinkle_speed + pick * star_twinkle_freq_scale) + pick * star_twinkle_phase);
	float oscillation = 1.0 + star_oscillation_strength * sin(
		shader_time * (star_oscillation_speed + pick * star_oscillation_phase_scale) + dot(cell, star_oscillation_cell_scale)
	);

	float color_hash = hash3(seed3 + vec3(77.0, 33.0, 11.0));
	vec3 star_color = mix(star_color_blue, star_color_white, smoothstep(0.0, star_color_mid, color_hash));
	star_color = mix(star_color, star_color_orange, smoothstep(star_color_mid, 1.0, color_hash));

	float intensity = has_star * (core + glow) * twinkle * oscillation * brightness;
	return star_color * intensity;
}

void sky() {
	vec3 col = space_color;

	// Fade plane near horizon (EYEDIR.y near 0 => division blows up)
	float abs_y = abs(EYEDIR.y);
	float blend = smoothstep(star_blend, 1.0, abs_y);

	// Flat plane: project 3D direction onto 2D plane above/below viewer.
	// Use safe divisor to avoid inf/nan on WebGL when EYEDIR.y is near zero.
	float safe_y = max(abs_y, 0.001);
	vec2 uv = EYEDIR.xz / safe_y * star_height;

	// Parallax + drift for twinkle when stationary
	float shader_time = TIME;
	vec3 drift = vec3(sin(shader_time * parallax_drift_speed_x) * parallax_drift_strength, 0.0, cos(shader_time * parallax_drift_speed_z) * parallax_drift_strength);
	vec3 effective_parallax = parallax_offset + drift;
	vec2 parallax_2d = -effective_parallax.xz * parallax_strength;

	// Parallax offset per layer (2D shift on the plane)
	vec2 uv1 = uv + parallax_2d * star_layer1_parallax;
	vec2 uv2 = uv + parallax_2d * star_layer2_parallax;
	vec2 uv3 = uv + parallax_2d * star_layer3_parallax;
	vec2 uv4 = uv + parallax_2d * star_layer4_parallax;

	vec3 s1 = stars_plane(uv1, star_layer1_cells, star_layer1_threshold, star_layer1_brightness, star_layer1_seed, star_zoom_scale, shader_time);
	vec3 s2 = stars_plane(uv2, star_layer2_cells, star_layer2_threshold, star_layer2_brightness, star_layer2_seed, star_zoom_scale, shader_time);
	vec3 s3 = stars_plane(uv3, star_layer3_cells, star_layer3_threshold, star_layer3_brightness, star_layer3_seed, star_zoom_scale, shader_time);
	vec3 s4 = stars_plane(uv4, star_layer4_cells, star_layer4_threshold, star_layer4_brightness, star_layer4_seed, star_zoom_scale, shader_time);

	col += (s1 + s2 + s3 + s4) * star_output_scale * blend;

	COLOR = col;
}
