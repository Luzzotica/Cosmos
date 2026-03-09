shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 3D print style hull: layer lines in print direction with glowing red flecks in the lining

uniform vec4 base_color : source_color = vec4(0.45, 0.48, 0.52, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.75;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;

// Print direction and bounds (same as structure_build_shell - wired from BaseStructure)
uniform vec3 print_direction = vec3(0.0, 1.0, 0.0);
uniform float axis_center = 0.0;
uniform float axis_extent = 1.0;
uniform float build_radius = 1.0;

uniform float line_density : hint_range(4.0, 48.0) = 22.0;
uniform float line_sharpness : hint_range(4.0, 20.0) = 10.0;
uniform vec4 line_color : source_color = vec4(0.5, 0.5, 0.55, 1.0);
uniform vec4 fleck_color : source_color = vec4(1.0, 0.25, 0.12, 1.0);
uniform float fleck_strength : hint_range(0.0, 1.0) = 0.6;
uniform float fleck_emission : hint_range(0.0, 4.0) = 2.2;
uniform float fleck_scale : hint_range(2.0, 24.0) = 10.0;

varying vec3 local_pos;

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
	local_pos = VERTEX;
}

void fragment() {
	vec3 dir = normalize(print_direction);
	float safe_extent = max(max(axis_extent, build_radius * 0.55), 0.001);
	float axis_value = dot(local_pos, dir);
	float axis_t = clamp((axis_value - (axis_center - safe_extent)) / (safe_extent * 2.0), 0.0, 1.0);

	// Layer lines: perpendicular to print direction (3D print layer boundaries)
	float line_phase = axis_value * line_density;
	float line_wave = sin(line_phase);
	float line_mask = pow(abs(line_wave), line_sharpness);

	// Slight darkening at layer boundaries for depth
	float line_dark = line_mask * 0.12;

	// Red flecks: sparse noise, only in the lining (where line_mask is high)
	float fleck_n = value_noise(local_pos * fleck_scale + vec3(31.7, 13.1, 47.3));
	float fleck_mask = smoothstep(0.82, 0.94, fleck_n) * line_mask;
	vec3 fleck_tint = fleck_color.rgb * fleck_mask * fleck_strength;

	vec3 albedo = base_color.rgb * (1.0 - line_dark) + fleck_tint;
	albedo += line_color.rgb * line_mask * 0.15;
	albedo = clamp(albedo, 0.0, 1.0);

	// Emission: glowing red flecks in the layer lines
	vec3 emission = fleck_color.rgb * fleck_mask * fleck_emission;
	emission += line_color.rgb * line_mask * 0.4;

	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	ALPHA = base_color.a;
	EMISSION = emission;
}
