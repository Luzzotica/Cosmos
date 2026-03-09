shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Structure hull: procedural brushed metal / painted alloy
// Matches audio-visual-style-guide: "brushed metal or painted alloy", neutral base tones

uniform vec4 base_color : source_color = vec4(0.72, 0.75, 0.8, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.75;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float noise_scale : hint_range(1.0, 64.0) = 12.0;
uniform float brushed_strength : hint_range(0.0, 0.4) = 0.12;
uniform float panel_line_strength : hint_range(0.0, 0.3) = 0.06;

varying vec3 v_local_pos;
varying vec3 v_world_pos;

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

void vertex() {
	v_local_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Brushed metal: directional streaks along Y (vertical) - common for cylindrical structures
	vec3 uv = v_local_pos * noise_scale;
	float grain = value_noise(uv);
	float grain2 = value_noise(uv + vec3(0.0, 17.3, 0.0));
	// Elongate along Y for brushed look
	float brushed = value_noise(uv * vec3(0.15, 1.0, 0.15) + vec3(0.0, grain * 6.28, 0.0));
	brushed = smoothstep(0.4, 0.6, brushed);
	float variation = (grain - 0.5) * brushed_strength + (brushed - 0.5) * brushed_strength;

	// Panel lines: subtle dark bands at regular intervals (simulate plating seams)
	float panel_u = v_local_pos.y * noise_scale * 0.8;
	float panel_line = fract(panel_u);
	panel_line = min(smoothstep(0.0, 0.04, panel_line), smoothstep(1.0, 0.96, panel_line));
	float panel_v = length(v_local_pos.xz) * noise_scale * 0.5;
	float panel_line2 = fract(panel_v);
	panel_line2 = min(smoothstep(0.0, 0.03, panel_line2), smoothstep(1.0, 0.97, panel_line2));
	float panel_dark = (panel_line + panel_line2) * panel_line_strength;

	vec3 albedo = base_color.rgb * (1.0 + variation - panel_dark);
	albedo = clamp(albedo, 0.0, 1.0);

	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	ALPHA = base_color.a;
}
