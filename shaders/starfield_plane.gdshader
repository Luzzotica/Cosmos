shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Starfield plane using same star logic as nebula_sky.gdshader (cube-face style, color spectrum, parallax layers).

uniform vec3 space_color : source_color = vec3(0.02, 0.02, 0.05);
uniform float star_twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform float star_oscillation_speed : hint_range(0.0, 2.0) = 0.35;
uniform float star_oscillation_strength : hint_range(0.0, 0.3) = 0.08;
uniform float sky_seed : hint_range(0.0, 10000.0) = 0.0;
uniform vec2 parallax_offset = vec2(0.0, 0.0);

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

// 2D adaptation of stars_3d from nebula_sky - same grid, jitter, colors, twinkle
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

	float star_size = mix(0.012, 0.04, hash3(seed3 + vec3(3.1, 9.7, 41.3)));
	float d = length(local);
	float core = smoothstep(star_size, 0.0, d);
	float glow = smoothstep(star_size * 2.5, 0.0, d) * 0.15;
	float twinkle = 0.8 + 0.2 * sin(TIME * (star_twinkle_speed + pick * 2.0) + pick * 97.0);
	float oscillation = 1.0 + star_oscillation_strength * sin(
		TIME * (star_oscillation_speed + pick * 0.5) + uv.x * 8.0 + uv.y * 11.0
	);

	// Star color spectrum: blue -> white -> orange
	float color_hash = hash3(seed3 + vec3(77.0, 33.0, 11.0));
	vec3 star_color = mix(vec3(0.5, 0.7, 1.0), vec3(1.0, 0.95, 0.9), smoothstep(0.0, 0.5, color_hash));
	star_color = mix(star_color, vec3(1.0, 0.4, 0.15), smoothstep(0.5, 1.0, color_hash));

	float intensity = has_star * (core + glow) * twinkle * oscillation * brightness;
	return star_color * intensity;
}

void fragment() {
	// 2-3 parallax layers (same offsets as nebula_sky stars)
	vec2 uv1 = UV + parallax_offset * 0.08;
	vec2 uv2 = UV + parallax_offset * 0.35;
	vec2 uv3 = UV + parallax_offset * 0.65;
	vec2 uv4 = UV + parallax_offset * 1.0;

	vec3 s1 = stars_2d(uv1, 130.0, 0.55, 0.5, 0.0);
	vec3 s2 = stars_2d(uv2, 90.0, 0.65, 0.9, 100.0);
	vec3 s3 = stars_2d(uv3, 50.0, 0.75, 1.25, 200.0);
	vec3 s4 = stars_2d(uv4, 25.0, 0.85, 1.9, 300.0);

	vec3 col = space_color + (s1 + s2 + s3 + s4) * 1.1;

	ALBEDO = col;
	EMISSION = col * 0.5;
}
