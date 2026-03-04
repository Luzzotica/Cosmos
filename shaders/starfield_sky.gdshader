shader_type sky;

// --- STAR UNIFORMS ---
uniform vec3 space_color : source_color = vec3(0.02, 0.02, 0.05); // Deep background
uniform float star_twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform float star_oscillation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float star_oscillation_strength : hint_range(0.0, 0.3) = 0.08;
uniform float sky_seed : hint_range(0.0, 10000.0) = 0.0;
uniform vec3 parallax_offset = vec3(0.0, 0.0, 0.0);

// Rotate sky to move pole/seams out of view. X = tilt (radians), Y = spin (radians).
uniform float sky_rotation_x : hint_range(-1.57, 1.57) = 0.35;
uniform float sky_rotation_y : hint_range(0.0, 6.28318530718) = 0.0;

// --- HASH ---
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

// --- STAR GENERATION ---
// Uses spherical (equirectangular) coords to avoid cube-face seams and hexagonal gaps.
vec3 stars_3d(vec3 dir, float cell_count, float threshold, float brightness, float seed_offset) {
	float lon = atan(dir.z, dir.x) / (2.0 * PI) + 0.5;
	float lat = asin(clamp(dir.y, -1.0, 1.0)) / PI + 0.5;
	vec2 uv = vec2(fract(lon), lat);  // fract ensures seamless wrap at lon boundary
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

	float star_size = mix(0.012, 0.04, hash3(seed3 + vec3(3.1, 9.7, 41.3)));
	float d = length(local);
	float core = smoothstep(star_size, 0.0, d);
	float glow = smoothstep(star_size * 2.5, 0.0, d) * 0.15;
	float twinkle = 0.8 + 0.2 * sin(TIME * (star_twinkle_speed + pick * 2.0) + pick * 97.0);
	float oscillation = 1.0 + star_oscillation_strength * sin(
		TIME * (star_oscillation_speed + pick * 0.5) + dot(dir, vec3(8.0, 11.0, 13.0))
	);

	// Color temperatures
	float color_hash = hash3(seed3 + vec3(77.0, 33.0, 11.0));
	vec3 star_color = mix(vec3(0.5, 0.7, 1.0), vec3(1.0, 0.95, 0.9), smoothstep(0.0, 0.5, color_hash));
	star_color = mix(star_color, vec3(1.0, 0.4, 0.15), smoothstep(0.5, 1.0, color_hash));

	float intensity = has_star * (core + glow) * twinkle * oscillation * brightness;
	return star_color * intensity;
}

// --- MAIN SKY RENDER ---
void sky() {
	vec3 dir = rotate_sky_direction(normalize(EYEDIR));
	vec3 col = space_color;

	vec3 dir_ultra_far = normalize(dir + parallax_offset * 0.08);
	vec3 dir_far = normalize(dir + parallax_offset * 0.35);
	vec3 dir_mid = normalize(dir + parallax_offset * 0.65);
	vec3 dir_near = normalize(dir + parallax_offset * 1.0);

	vec3 s1 = stars_3d(dir_ultra_far, 130.0, 0.55, 0.5, 0.0);
	vec3 s2 = stars_3d(dir_far, 90.0, 0.65, 0.9, 100.0);
	vec3 s3 = stars_3d(dir_mid, 50.0, 0.75, 1.25, 200.0);
	vec3 s4 = stars_3d(dir_near, 25.0, 0.85, 1.9, 300.0);

	col += (s1 + s2 + s3 + s4) * 1.1;

	COLOR = col;
}
