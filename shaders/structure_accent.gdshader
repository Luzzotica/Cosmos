shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Structure accent: panels, orbs, cores - emissive energy with hull-consistent base
// Matches audio-visual-style-guide: "emissive energy strips or nodes"

uniform vec4 base_color : source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform vec3 emission_color : source_color = vec3(0.12, 0.68, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.0;
uniform float fresnel_power : hint_range(1.0, 8.0) = 2.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.7;
uniform float roughness : hint_range(0.0, 1.0) = 0.2;
uniform float crackle_strength : hint_range(0.0, 0.4) = 0.08;
uniform float pulse_amount : hint_range(0.0, 0.3) = 0.05;

varying vec3 v_world_pos;
varying vec3 v_normal;
varying vec3 v_local_pos;

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

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	sum += value_noise(p * freq) * amp;
	freq *= 2.0;
	amp *= 0.5;
	sum += value_noise(p * freq) * amp;
	freq *= 2.0;
	amp *= 0.5;
	sum += value_noise(p * freq) * amp;
	freq *= 2.0;
	amp *= 0.5;
	sum += value_noise(p * freq) * amp;
	return sum;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_local_pos = VERTEX;
}

void fragment() {
	// Subtle crackle for energy texture (tuned down from enemy crackle)
	vec3 crackle_uv = v_world_pos * 8.0 + vec3(TIME * 0.5, TIME * 0.7, TIME * 0.3);
	float crackle = fbm(crackle_uv);
	float arc = pow(abs(sin(crackle * 6.28)), 4.0);
	float crackle_mask = arc * crackle_strength;

	// Fresnel - edges glow brighter
	vec3 view_dir = normalize(VIEW - v_world_pos);
	float fresnel = pow(1.0 - max(dot(normalize(v_normal), view_dir), 0.0), fresnel_power);

	// Gentle pulse
	float pulse = 1.0 + pulse_amount * sin(TIME * 2.5);

	// Emission: base + crackle + fresnel edge boost
	vec3 emission = emission_color * emission_strength * (1.0 + crackle_mask) * (1.0 + fresnel * 0.5) * pulse;

	ALBEDO = base_color.rgb;
	EMISSION = emission;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	ALPHA = base_color.a;
}
