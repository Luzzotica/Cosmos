shader_type sky;

// SAFEKEEPING: Full nebula + stars sky shader. Use starfield_sky.gdshader for stars-only.

// --- NEBULA UNIFORMS ---
uniform vec3 space_color : source_color = vec3(0.02, 0.02, 0.05); // Deep background
uniform vec3 nebula_color1 : source_color = vec3(0.8, 0.2, 0.5); // Pink/Magenta
uniform vec3 nebula_color2 : source_color = vec3(0.1, 0.5, 0.9); // Cyan/Blue
uniform float nebula_time_scale : hint_range(0.0, 1.0) = 0.03;
uniform float nebula_uv_scale : hint_range(0.1, 20.0) = 4.0;
uniform float nebula_brightness : hint_range(0.0, 5.0) = 1.5;
uniform float nebula_swirl_strength : hint_range(0.0, 2.0) = 0.6;  // curl advection
uniform float nebula_grouping : hint_range(0.3, 3.0) = 1.8;  // higher = more distinct color blobs

// --- STAR UNIFORMS ---
uniform float star_twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform float star_oscillation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float star_oscillation_strength : hint_range(0.0, 0.3) = 0.08;
uniform float sky_seed : hint_range(0.0, 10000.0) = 0.0;
uniform vec3 parallax_offset = vec3(0.0, 0.0, 0.0);

// Rotate sky to move pole/seams out of view. X = tilt (radians), Y = spin (radians).
uniform float sky_rotation_x : hint_range(-1.57, 1.57) = 0.35;  // tilt pole away from center (~20°)
uniform float sky_rotation_y : hint_range(0.0, 6.28318530718) = 0.0;

// --- HASH & NOISE FUNCTIONS ---
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

// 4-Octave Fractional Brownian Motion
float fbm(vec2 uv) {
	float sum = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.87758, 0.47942), vec2(-0.47942, 0.87758));
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(uv);
		uv = rot * uv * 2.0;
		amp *= 0.5;
	}
	return sum;
}

// Curl of FBM: divergence-free flow for fluid-like swirling
vec2 curl_noise(vec2 uv) {
	float eps = 0.08;
	float n_l = fbm(uv - vec2(eps, 0.0));
	float n_r = fbm(uv + vec2(eps, 0.0));
	float n_d = fbm(uv - vec2(0.0, eps));
	float n_u = fbm(uv + vec2(0.0, eps));
	float gx = (n_r - n_l) / (2.0 * eps);
	float gy = (n_u - n_d) / (2.0 * eps);
	return vec2(gy, -gx);  // curl = (df/dy, -df/dx)
}

// Multi-octave curl for richer, larger-scale swirling
vec2 curl_fbm(vec2 uv) {
	vec2 curl = vec2(0.0);
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.87758, 0.47942), vec2(-0.47942, 0.87758));
	for (int i = 0; i < 3; i++) {
		curl += amp * curl_noise(uv);
		uv = rot * uv * 2.0;
		amp *= 0.5;
	}
	return curl;
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
vec3 stars_3d(vec3 dir, float cell_count, float threshold, float brightness, float seed_offset) {
	vec3 abs_dir = abs(dir);
	vec2 face_uv;
	float face_id;

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

	float star_size = mix(0.012, 0.04, hash3(seed3 + vec3(3.1, 9.7, 41.3)));
	float d = length(local);
	float core = smoothstep(star_size, 0.0, d);
	float glow = smoothstep(star_size * 2.5, 0.0, d) * 0.15;
	float twinkle = 0.8 + 0.2 * sin(TIME * (star_twinkle_speed + pick * 2.0) + pick * 97.0);
	float oscillation = 1.0 + star_oscillation_strength * sin(
		TIME * (star_oscillation_speed + pick * 0.5) + dot(dir, vec3(8.0, 11.0, 13.0))
	);

	float color_hash = hash3(seed3 + vec3(77.0, 33.0, 11.0));
	vec3 star_color = mix(vec3(0.5, 0.7, 1.0), vec3(1.0, 0.95, 0.9), smoothstep(0.0, 0.5, color_hash));
	star_color = mix(star_color, vec3(1.0, 0.4, 0.15), smoothstep(0.5, 1.0, color_hash));

	float intensity = has_star * (core + glow) * twinkle * oscillation * brightness * edge_fade;
	return star_color * intensity;
}

// --- MAIN SKY RENDER ---
void sky() {
	vec3 dir = rotate_sky_direction(normalize(EYEDIR));
	vec3 col = space_color;

	// --- 1. FLUID NEBULA BACKGROUND ---
	float lon = atan(dir.z, dir.x) / (2.0 * PI) + 0.5;
	float lat = asin(clamp(dir.y, -1.0, 1.0)) / PI + 0.5;
	vec2 uv = vec2(lon, lat) * nebula_uv_scale;

	float t = TIME * nebula_time_scale + sky_seed * 0.01;

	vec2 uv_swirl = uv;
	float dt = 0.4 * nebula_swirl_strength;
	for (int i = 0; i < 3; i++) {
		uv_swirl += curl_fbm(uv_swirl + vec2(t * 0.3, t * 0.17)) * dt;
	}

	vec2 q = vec2(0.0);
	q.x = fbm(uv_swirl + vec2(t, t));
	q.y = fbm(uv_swirl + vec2(-t, t * 0.5));

	vec2 r = vec2(0.0);
	r.x = fbm(uv_swirl + 1.0 * q + vec2(1.7, 9.2) + 0.15 * t);
	r.y = fbm(uv_swirl + 1.0 * q + vec2(8.3, 2.8) + 0.126 * t);

	float f = fbm(uv_swirl + r);

	float px = pow(clamp(r.x, 0.0, 1.0), nebula_grouping);
	float py = pow(clamp(q.y, 0.0, 1.0), nebula_grouping);
	float pf = pow(clamp(f, 0.0, 1.0), nebula_grouping);

	vec3 neb_mix = mix(space_color, nebula_color1, px);
	neb_mix = mix(neb_mix, nebula_color2, py);

	col = mix(col, neb_mix, pf * nebula_brightness);

	// --- 2. FOREGROUND STARS ---
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
