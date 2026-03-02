shader_type sky;

uniform vec3 space_color : source_color = vec3(0.0196, 0.0784, 0.1529); // #051427
uniform vec3 galaxy_color : source_color = vec3(0.3255, 0.0588, 0.1176); // #530f1e
uniform vec3 galaxy_core_color : source_color = vec3(0.6431, 0.2627, 0.1333); // #a44322
uniform vec3 galaxy_highlight_color : source_color = vec3(0.9725, 0.7373, 0.0157); // #f8bc04
uniform float star_twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform float star_oscillation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float star_oscillation_strength : hint_range(0.0, 0.3) = 0.08;
uniform float galaxy_strength : hint_range(0.0, 1.0) = 0.15;
uniform float galaxy_drift_speed : hint_range(0.0, 0.2) = 0.03;
uniform float galaxy_scintillation_strength : hint_range(0.0, 0.25) = 0.08;
uniform float sky_seed : hint_range(0.0, 10000.0) = 0.0;
uniform float galaxy_rotation : hint_range(0.0, 6.28318530718) = 0.0;
uniform vec3 parallax_offset = vec3(0.0, 0.0, 0.0);

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	vec2 s = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

float fbm(vec2 uv) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(uv);
		uv *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

float stars_3d(vec3 dir, float cell_count, float threshold, float brightness, float seed_offset) {
	vec3 abs_dir = abs(dir);
	vec2 face_uv;
	float face_id;

	// Project onto the dominant cube face.
	if (abs_dir.x >= abs_dir.y && abs_dir.x >= abs_dir.z) {
		face_uv = dir.yz / abs_dir.x;
		face_id = step(0.0, dir.x);
	} else if (abs_dir.y >= abs_dir.x && abs_dir.y >= abs_dir.z) {
		face_uv = dir.xz / abs_dir.y;
		face_id = 2.0 + step(0.0, dir.y);
	} else {
		face_uv = dir.xy / abs_dir.z;
		face_id = 4.0 + step(0.0, dir.z);
	}

	// Fade out near cube-face edges to hide seam distortion.
	float edge_dist = min(1.0 - abs(face_uv.x), 1.0 - abs(face_uv.y));
	float edge_fade = smoothstep(0.0, 0.12, edge_dist);

	face_uv = face_uv * 0.5 + 0.5;
	vec2 grid = face_uv * cell_count;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;

	vec3 seed3 = vec3(cell + vec2(face_id * 73.1, seed_offset), sky_seed);
	float pick = hash3(seed3);
	float has_star = step(threshold, pick);

	vec2 jitter = vec2(
		hash3(seed3 + vec3(11.7, 17.3, 3.1)),
		hash3(seed3 + vec3(27.1, 5.9, 13.7))
	) - 0.5;
	local -= jitter * 0.6;

	// Tiny pinprick sizes.
	float star_size = mix(0.012, 0.04, hash3(seed3 + vec3(3.1, 9.7, 41.3)));
	float d = length(local);
	float core = smoothstep(star_size, 0.0, d);
	float glow = smoothstep(star_size * 2.5, 0.0, d) * 0.15;
	float twinkle = 0.8 + 0.2 * sin(TIME * (star_twinkle_speed + pick * 2.0) + pick * 97.0);
	float oscillation = 1.0 + star_oscillation_strength * sin(
		TIME * (star_oscillation_speed + pick * 0.5) + dot(dir, vec3(8.0, 11.0, 13.0))
	);

	// Subtle warm/cool tint per star.
	float warmth = mix(0.9, 1.1, hash3(seed3 + vec3(77.0, 33.0, 11.0)));

	return has_star * (core + glow) * twinkle * oscillation * brightness * warmth * edge_fade;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = space_color * 1.0;

	vec3 dir_ultra_far = normalize(dir + parallax_offset * 0.08);
	vec3 dir_far = normalize(dir + parallax_offset * 0.35);
	vec3 dir_mid = normalize(dir + parallax_offset * 0.65);
	vec3 dir_near = normalize(dir + parallax_offset * 1.0);

	// Layer 1: ultra-distant dust.
	float s1 = stars_3d(dir_ultra_far, 82.0, 0.82, 0.5, 0.0);
	// Layer 2: distant field.
	float s2 = stars_3d(dir_far, 52.0, 0.85, 0.9, 100.0);
	// Layer 3: mid-depth stars.
	float s3 = stars_3d(dir_mid, 30.0, 0.88, 1.25, 200.0);
	// Foreground sparse bright stars.
	float s4 = stars_3d(dir_near, 18.0, 0.90, 1.9, 300.0);

	col += vec3(s1 + s2 + s3 + s4) * 1.1;

	// Subtle galaxy / nebula band.
	float cr = cos(galaxy_rotation);
	float sr = sin(galaxy_rotation);
	vec3 galaxy_axis = normalize(vec3(0.22 * cr - 0.28 * sr, 0.94, 0.22 * sr + 0.28 * cr));
	float band = 1.0 - abs(dot(dir_mid, galaxy_axis));
	float band_shape = pow(clamp(band, 0.0, 1.0), 7.0);

	float lon = atan(dir_mid.z, dir_mid.x) / (2.0 * PI) + 0.5;
	float lat = asin(clamp(dir_mid.y, -1.0, 1.0)) / PI + 0.5;
	vec2 neb_uv = vec2(lon, lat);
	vec2 drift = vec2(
		sin(TIME * galaxy_drift_speed + sky_seed * 0.013),
		cos(TIME * galaxy_drift_speed * 0.73 + sky_seed * 0.019)
	) * 0.02;
	float clouds = fbm(neb_uv * 14.0 + vec2(sky_seed * 0.01, sky_seed * 0.007));
	float clouds_drifted = fbm((neb_uv + drift) * 14.0 + vec2(sky_seed * 0.01, sky_seed * 0.007));
	float scintillation = 1.0 + galaxy_scintillation_strength * (clouds_drifted - clouds);
	float galaxy_mix = band_shape * smoothstep(0.44, 0.9, clouds) * galaxy_strength * 1.45 * scintillation;
	vec3 galaxy_tint = mix(galaxy_color, galaxy_core_color, clouds);
	galaxy_tint = mix(galaxy_tint, galaxy_highlight_color, smoothstep(0.78, 0.98, clouds) * 0.35);
	col += galaxy_tint * galaxy_mix;

	COLOR = col;
}
