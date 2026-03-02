shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 hill_color : source_color = vec3(0.48, 0.49, 0.52);
uniform vec3 valley_color : source_color = vec3(0.07, 0.23, 0.12);
uniform vec3 glow_color : source_color = vec3(0.15, 1.0, 0.35);

uniform float roughness : hint_range(0.0, 1.0) = 0.86;
uniform float metallic : hint_range(0.0, 1.0) = 0.02;

uniform float deform_strength : hint_range(0.0, 1.5) = 0.34;
uniform float ridge_scale : hint_range(0.3, 12.0) = 2.9;
uniform float warp_scale : hint_range(0.3, 12.0) = 1.4;
uniform float warp_strength : hint_range(0.0, 1.5) = 0.34;
uniform float valley_sharpness : hint_range(0.5, 4.0) = 1.6;
uniform float line_frequency : hint_range(1.0, 64.0) = 22.0;
uniform float line_width : hint_range(0.005, 0.3) = 0.07;
uniform float line_scale : hint_range(0.2, 24.0) = 3.8;
uniform float line_contrast : hint_range(0.0, 2.0) = 0.48;

uniform float seed = 0.0;
uniform float resource_level : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_speed : hint_range(0.1, 8.0) = 1.2;
uniform float pulse_strength : hint_range(0.0, 4.0) = 0.28;
uniform float emission_base : hint_range(0.0, 4.0) = 0.55;

varying float v_valley_mask;
varying float v_rock_mix;
varying vec3 v_surface_seed_pos;


float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


vec3 hash33(vec3 p) {
	return vec3(
		hash31(p + vec3(1.0, 0.0, 0.0)),
		hash31(p + vec3(0.0, 1.0, 0.0)),
		hash31(p + vec3(0.0, 0.0, 1.0))
	);
}


float value_noise_3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	return mix(nxy0, nxy1, u.z);
}


float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		sum += value_noise_3d(p * freq) * amp;
		freq *= 2.02;
		amp *= 0.5;
	}
	return sum;
}


float ridged_fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.6;
	float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		float n = value_noise_3d(p * freq);
		float ridge = 1.0 - abs(n * 2.0 - 1.0);
		sum += ridge * ridge * amp;
		freq *= 2.1;
		amp *= 0.55;
	}
	return clamp(sum, 0.0, 1.0);
}


void vertex() {
	vec3 unit_pos = normalize(VERTEX);
	vec3 seed_shift = vec3(seed * 0.11, seed * 0.17, seed * 0.07);

	vec3 warp = vec3(
		fbm(unit_pos * warp_scale + seed_shift),
		fbm(unit_pos.yzx * warp_scale + seed_shift * 1.7),
		fbm(unit_pos.zxy * warp_scale + seed_shift * 2.1)
	) * 2.0 - 1.0;

	vec3 warped_pos = unit_pos + warp * warp_strength;
	float ridges = ridged_fbm(warped_pos * ridge_scale + seed_shift * 1.3);
	float broad = fbm(warped_pos * (ridge_scale * 0.65) + seed_shift * 0.9);

	float valley_mask = clamp(pow(ridges, valley_sharpness) * 0.78 + (1.0 - broad) * 0.22, 0.0, 1.0);
	float hill_mask = smoothstep(0.36, 0.86, broad);
	float displacement = (hill_mask * 0.66 - valley_mask * 0.58) * deform_strength;

	VERTEX += NORMAL * displacement;
	v_valley_mask = valley_mask;
	v_rock_mix = clamp(broad, 0.0, 1.0);
	v_surface_seed_pos = warped_pos;
}


void fragment() {
	float rock_variation = smoothstep(0.24, 0.9, v_rock_mix);
	vec3 rock_base = mix(hill_color * 0.82, hill_color * 1.08, rock_variation);

	float line_noise = fbm(v_surface_seed_pos * line_scale + vec3(seed * 0.23, seed * 0.37, seed * 0.19));
	float line_coord = dot(normalize(v_surface_seed_pos), normalize(vec3(0.71, 0.38, 0.59))) * line_frequency + line_noise * 4.0 + seed * 6.7;
	float wave = abs(sin(line_coord));
	float aa = max(fwidth(line_coord) * 0.9, 0.001);
	float line_mask = 1.0 - smoothstep(line_width, line_width + aa, wave);

	float structured_valley = clamp(v_valley_mask * 0.62 + line_mask * line_contrast, 0.0, 1.0);
	ALBEDO = mix(rock_base, valley_color, clamp(structured_valley * 0.72, 0.0, 1.0));

	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed + seed * 12.73);
	float emission_strength = (emission_base + pulse * pulse_strength) * structured_valley * resource_level;
	EMISSION = glow_color * emission_strength;

	ROUGHNESS = clamp(roughness + (1.0 - rock_variation) * 0.08, 0.0, 1.0);
	METALLIC = metallic;
}
