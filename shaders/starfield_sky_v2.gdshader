shader_type sky;

// SAFEKEEPING: Full nebula + stars sky shader. Use starfield_sky.gdshader for stars-only.

// --- NEBULA UNIFORMS ---
uniform vec3 space_color : source_color = vec3(0.02, 0.02, 0.05); // Deep background

// --- STAR UNIFORMS ---
uniform float star_twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform float star_oscillation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float star_oscillation_strength : hint_range(0.0, 0.3) = 0.08;
uniform float sky_seed : hint_range(0.0, 10000.0) = 0.0;
uniform vec3 parallax_offset = vec3(0.0, 0.0, 0.0);
uniform float star_zoom_scale : hint_range(1.0, 1.25) = 1.0;  // denser grid when zoomed out = more stars
uniform float parallax_drift_strength : hint_range(0.0, 0.1) = 0.016;  // time-based drift for twinkle when stationary

// Per-layer tunables (exposed for inspector / debugging)
uniform float star_layer1_cells : hint_range(1.0, 500.0) = 100.0;
uniform float star_layer1_threshold : hint_range(0.0, 1.0) = 0.12;
uniform float star_layer1_brightness : hint_range(0.0, 5.0) = 0.55;
uniform float star_layer2_cells : hint_range(1.0, 500.0) = 55.0;
uniform float star_layer2_threshold : hint_range(0.0, 1.0) = 0.15;
uniform float star_layer2_brightness : hint_range(0.0, 5.0) = 1.0;
uniform float star_layer3_cells : hint_range(1.0, 500.0) = 28.0;
uniform float star_layer3_threshold : hint_range(0.0, 1.0) = 0.18;
uniform float star_layer3_brightness : hint_range(0.0, 5.0) = 1.6;

uniform float star_size_min : hint_range(0.001, 0.5) = 0.06;
uniform float star_size_max : hint_range(0.01, 0.8) = 0.18;
uniform float star_glow_mult : hint_range(1.0, 6.0) = 3.0;  // glow radius = star_size * this

// Debug: 0 = off, >0 = show cell grid overlay (value = line intensity)
uniform float star_debug_cells : hint_range(0.0, 1.0) = 0.0;

// Grid mode: 0 = EYEDIR/spherical, 1 = SCREEN_UV, 2 = SKY_COORDS
uniform int star_grid_mode : hint_range(0, 2) = 1;

// Rotate sky to move pole/seams out of view. X = tilt (radians), Y = spin (radians).
uniform float sky_rotation_x : hint_range(-1.57, 1.57) = 0.35;  // tilt pole away from center (~20°)
uniform float sky_rotation_y : hint_range(0.0, 6.28318530718) = 0.0;

// --- HASH & NOISE FUNCTIONS ---
float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

// Rotate direction: first pitch (X), then yaw (Y).
vec3 rotate_sky_direction(vec3 d) {
	float cx = cos(sky_rotation_x);
	float sx = sin(sky_rotation_x);
	float cy = cos(sky_rotation_y);
	float sy = sin(sky_rotation_y);
	float y1 = d.y * cx - d.z * sx;
	float z1 = d.y * sx + d.z * cx;
	vec3 d1 = vec3(d.x, y1, z1);
	float x2 = d1.x * cy + d1.z * sy;
	float z2 = -d1.x * sy + d1.z * cy;
	return normalize(vec3(x2, d1.y, z2));
}

// Map direction to 2D spherical coords for grid (avoids Cartesian concentric-circle artifact)
vec3 dir_to_sphere_grid(vec3 dir) {
	float theta = atan(dir.z, dir.x);
	float phi = asin(clamp(dir.y, -1.0, 1.0));
	float u = (theta * 0.15915494309189535) + 0.5;
	float v = (phi * 0.3183098861837907) + 0.5;
	return vec3(u, v, 0.0);
}

// --- STAR GENERATION (grid_uv = 2D UV for cell lookup, osc_phase = for twinkle variation) ---
vec3 stars_from_grid(vec2 grid_uv, float osc_phase, float cell_count, float threshold, float brightness, float seed_offset, float zoom_scale) {
	float scale = cell_count;
	vec2 grid = grid_uv * scale;
	vec2 cell = floor(grid);
	vec2 sub = fract(grid) - 0.5;

	vec3 seed3 = vec3(cell.x, cell.y, seed_offset + sky_seed * 0.1);
	float pick = hash3(seed3);
	float has_star = step(threshold, pick);

	vec2 jitter = vec2(
		hash3(seed3 + vec3(11.7, 17.3, 3.1)),
		hash3(seed3 + vec3(27.1, 5.9, 13.7))
	) - 0.5;
	sub -= jitter * 0.6;
	float d = length(sub);

	float star_size = mix(star_size_min, star_size_max, hash3(seed3 + vec3(3.1, 9.7, 41.3)));
	float core = smoothstep(star_size, 0.0, d);
	float glow = smoothstep(star_size * star_glow_mult, 0.0, d) * 0.15;
	float twinkle = 0.8 + 0.2 * sin(TIME * (star_twinkle_speed + pick * 2.0) + pick * 97.0);
	float oscillation = 1.0 + star_oscillation_strength * sin(
		TIME * (star_oscillation_speed + pick * 0.5) + osc_phase
	);

	float color_hash = hash3(seed3 + vec3(77.0, 33.0, 11.0));
	vec3 star_color = mix(vec3(0.5, 0.7, 1.0), vec3(1.0, 0.95, 0.9), smoothstep(0.0, 0.5, color_hash));
	star_color = mix(star_color, vec3(1.0, 0.4, 0.15), smoothstep(0.5, 1.0, color_hash));

	float intensity = has_star * (core + glow) * twinkle * oscillation * brightness;
	return star_color * intensity;
}

// --- MAIN SKY RENDER ---
void sky() {
	vec3 col = space_color;

	// Time-based drift mimics panning parallax for twinkle effect when camera is still
	vec3 drift = vec3(sin(TIME * 0.18) * parallax_drift_strength, 0.0, cos(TIME * 0.14) * parallax_drift_strength);
	vec3 effective_parallax = parallax_offset + drift;

	vec3 s1;
	vec3 s2;
	vec3 s3;
	vec2 debug_grid_uv;

	if (star_grid_mode == 1) {
		// Option A: SCREEN_UV - rectangular grid, no concentric circles
		vec2 base_uv = SCREEN_UV;
		// Apply sky rotation: rotate around (0.5, 0.5)
		vec2 c = base_uv - 0.5;
		float cr = cos(sky_rotation_y);
		float sr = sin(sky_rotation_y);
		base_uv = vec2(c.x * cr - c.y * sr, c.x * sr + c.y * cr) + 0.5;
		debug_grid_uv = base_uv;

		// Parallax (camera) + drift (time) scaled for UV space - visible layer offset & twinkle
		vec2 uv1 = base_uv + effective_parallax.xz * 1.5;
		vec2 uv2 = base_uv + effective_parallax.xz * 3.0;
		vec2 uv3 = base_uv + effective_parallax.xz * 4.5;

		s1 = stars_from_grid(uv1, dot(uv1, vec2(8.0, 11.0)), star_layer1_cells, star_layer1_threshold, star_layer1_brightness, 0.0, star_zoom_scale);
		s2 = stars_from_grid(uv2, dot(uv2, vec2(8.0, 11.0)), star_layer2_cells, star_layer2_threshold, star_layer2_brightness, 100.0, star_zoom_scale);
		s3 = stars_from_grid(uv3, dot(uv3, vec2(8.0, 11.0)), star_layer3_cells, star_layer3_threshold, star_layer3_brightness, 200.0, star_zoom_scale);
	} else if (star_grid_mode == 2) {
		// Option B: SKY_COORDS - Godot panorama UV (equirectangular-style)
		vec2 base_uv = SKY_COORDS;
		base_uv.x += sky_rotation_y * 0.15915494309189535;
		base_uv = fract(base_uv);
		debug_grid_uv = base_uv;

		// Parallax (camera) + drift (time) scaled for UV space
		vec2 uv1 = base_uv + effective_parallax.xz * 1.5;
		vec2 uv2 = base_uv + effective_parallax.xz * 3.0;
		vec2 uv3 = base_uv + effective_parallax.xz * 4.5;
		uv1 = fract(uv1);
		uv2 = fract(uv2);
		uv3 = fract(uv3);

		s1 = stars_from_grid(uv1, dot(uv1, vec2(8.0, 11.0)), star_layer1_cells, star_layer1_threshold, star_layer1_brightness, 0.0, star_zoom_scale);
		s2 = stars_from_grid(uv2, dot(uv2, vec2(8.0, 11.0)), star_layer2_cells, star_layer2_threshold, star_layer2_brightness, 100.0, star_zoom_scale);
		s3 = stars_from_grid(uv3, dot(uv3, vec2(8.0, 11.0)), star_layer3_cells, star_layer3_threshold, star_layer3_brightness, 200.0, star_zoom_scale);
	} else {
		// Mode 0: EYEDIR + spherical grid (legacy, may show concentric circles)
		vec3 dir = rotate_sky_direction(normalize(EYEDIR));
		vec3 dir_far = normalize(dir + effective_parallax * 0.15);
		vec3 dir_mid = normalize(dir + effective_parallax * 0.5);
		vec3 dir_near = normalize(dir + effective_parallax * 0.9);

		debug_grid_uv = dir_to_sphere_grid(dir).xy;
		s1 = stars_from_grid(dir_to_sphere_grid(dir_far).xy, dot(dir_far, vec3(8.0, 11.0, 13.0)), star_layer1_cells, star_layer1_threshold, star_layer1_brightness, 0.0, star_zoom_scale);
		s2 = stars_from_grid(dir_to_sphere_grid(dir_mid).xy, dot(dir_mid, vec3(8.0, 11.0, 13.0)), star_layer2_cells, star_layer2_threshold, star_layer2_brightness, 100.0, star_zoom_scale);
		s3 = stars_from_grid(dir_to_sphere_grid(dir_near).xy, dot(dir_near, vec3(8.0, 11.0, 13.0)), star_layer3_cells, star_layer3_threshold, star_layer3_brightness, 200.0, star_zoom_scale);
	}

	col += (s1 + s2 + s3) * 1.1;

	// Debug: draw cell grid overlay (lines at cell boundaries)
	if (star_debug_cells > 0.0) {
		float debug_scale = star_layer1_cells;
		vec2 grid = debug_grid_uv * debug_scale;
		vec2 f = fract(grid);
		float edge_u = (1.0 - smoothstep(0.0, 0.04, f.x)) + smoothstep(0.96, 1.0, f.x);
		float edge_v = (1.0 - smoothstep(0.0, 0.04, f.y)) + smoothstep(0.96, 1.0, f.y);
		float edge = min(1.0, edge_u + edge_v);
		vec2 cell_floor = floor(grid);
		vec3 cell_color = vec3(
			hash3(vec3(cell_floor.x, cell_floor.y, 0.0) + vec3(0.0, 0.1, 0.2)),
			hash3(vec3(cell_floor.x, cell_floor.y, 0.0) + vec3(1.0, 1.1, 1.2)),
			hash3(vec3(cell_floor.x, cell_floor.y, 0.0) + vec3(2.0, 2.1, 2.2))
		) * 0.3 + 0.1;
		col = mix(col, mix(col, cell_color, 0.7), edge * star_debug_cells);
	}

	COLOR = col;
}
