shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float build_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 final_color : source_color = vec4(0.45, 0.48, 0.52, 1.0);
uniform vec4 print_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);
uniform vec4 edge_glow_color : source_color = vec4(1.0, 0.35, 0.2, 1.0);
uniform vec3 print_direction = vec3(0.0, 1.0, 0.0);
uniform float axis_center = 0.0;
uniform float axis_extent = 1.0;
uniform float build_radius = 1.0;
uniform float line_density = 26.0;
uniform float finalize_blend : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	// Cache object-local position for camera-independent construction effects.
	local_pos = VERTEX;
}

void fragment() {
	vec3 dir = normalize(print_direction);
	float safe_extent = max(max(axis_extent, build_radius * 0.55), 0.001);
	float axis_value = dot(local_pos, dir);
	float axis_t = clamp((axis_value - (axis_center - safe_extent)) / (safe_extent * 2.0), 0.0, 1.0);

	float grain = hash13(local_pos * 8.0);
	float axis_noisy = clamp(axis_t + (grain - 0.5) * 0.08, 0.0, 1.0);

	// Reveal from power-line direction into full material.
	float reveal_mask = 1.0 - smoothstep(build_progress - 0.035, build_progress + 0.03, axis_noisy);

	// Red "printed" energy lines.
	float line_wave = sin((local_pos.y + local_pos.x * 0.45 + local_pos.z * 0.25 + TIME * 1.6) * line_density);
	float line_mask = pow(abs(line_wave), 10.0);

	// Bright hot front where matter becomes permanent.
	float front = 1.0 - smoothstep(0.0, 0.08, abs(axis_noisy - build_progress));
	vec3 energy_base = mix(print_color.rgb * 0.4, print_color.rgb * 1.3, line_mask);
	vec3 energy_col = mix(energy_base, edge_glow_color.rgb, front * 0.9);

	vec3 staged_albedo = mix(energy_col, final_color.rgb, reveal_mask);
	vec3 albedo = mix(staged_albedo, final_color.rgb, finalize_blend);
	float alpha = mix(0.78, 1.0, reveal_mask);

	ALBEDO = albedo;
	ALPHA = alpha;
	METALLIC = mix(0.08, 0.42, reveal_mask);
	ROUGHNESS = mix(0.28, 0.45, reveal_mask);
	EMISSION = energy_col * (1.25 + front * 2.8) * (1.0 - reveal_mask * 0.5) * (1.0 - finalize_blend);
}
