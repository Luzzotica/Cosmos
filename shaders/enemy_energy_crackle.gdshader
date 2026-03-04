shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 emission_color : source_color = vec3(1.0, 0.0, 0.25);
uniform float emission_energy : hint_range(0.0, 8.0) = 2.5;
uniform float crackle_speed : hint_range(0.5, 8.0) = 3.0;
uniform float crackle_density : hint_range(4.0, 64.0) = 28.0;
uniform float crackle_sharpness : hint_range(2.0, 16.0) = 8.0;
uniform float core_brightness : hint_range(0.2, 1.0) = 0.6;
uniform float pulse_amount : hint_range(0.0, 0.8) = 0.2;
uniform float fresnel_power : hint_range(1.0, 8.0) = 2.5;

varying vec3 v_world_pos;
varying vec3 v_normal;
varying vec3 v_local_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i);
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

float fbm_crackle(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 5; i++) {
		sum += value_noise(p * freq) * amp;
		freq *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_local_pos = VERTEX;
}

void fragment() {
	// Animated crackle pattern - multiple octaves of noise at different speeds
	vec3 crackle_uv = v_world_pos * crackle_density * 0.08 + vec3(TIME * crackle_speed * 0.7, TIME * crackle_speed * 1.1, TIME * crackle_speed * 0.5);
	float crackle = fbm_crackle(crackle_uv);

	// Sharp arcs - high contrast between dark and bright
	float arc = pow(abs(sin(crackle * 6.28318)), crackle_sharpness);
	float arc2 = pow(abs(sin(crackle * 12.0 + TIME * 4.0)), crackle_sharpness * 0.7);
	float crackle_mask = max(arc, arc2 * 0.6);

	// Fresnel - edges glow brighter (energy shell effect)
	vec3 view_dir = normalize(VIEW - v_world_pos);
	float fresnel = pow(1.0 - max(dot(normalize(v_normal), view_dir), 0.0), fresnel_power);

	// Pulse overlay
	float pulse = 1.0 + pulse_amount * sin(TIME * 2.5);

	// Combine: solid core + crackling overlay + edge fresnel
	vec3 base_emission = emission_color * (core_brightness + crackle_mask * 0.9);
	float total_energy = emission_energy * (base_emission.r + base_emission.g + base_emission.b) / 3.0;
	total_energy *= (1.0 + fresnel * 0.6) * pulse;

	ALBEDO = emission_color * (core_brightness * 0.15 + crackle_mask * 0.1);
	EMISSION = base_emission * total_energy;
	ROUGHNESS = 0.2;
	METALLIC = 0.6;
	ALPHA = 1.0;
}
