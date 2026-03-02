shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float build_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 final_color : source_color = vec4(0.45, 0.48, 0.52, 1.0);
uniform vec4 steel_color : source_color = vec4(0.62, 0.67, 0.75, 1.0);
uniform vec4 char_color : source_color = vec4(0.06, 0.08, 0.12, 1.0);
uniform vec4 burn_glow_color : source_color = vec4(0.12, 0.66, 1.0, 1.0);
uniform float min_local_y = -0.5;
uniform float local_height = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	float safe_height = max(local_height, 0.001);
	float local_t = clamp((VERTEX.y - min_local_y) / safe_height, 0.0, 1.0);
	float grain = hash13(VERTEX * 7.0);
	float noisy_t = clamp(local_t + (grain - 0.5) * 0.14, 0.0, 1.0);

	// Bottom-up completion: completed area becomes final material.
	float built_mask = 1.0 - smoothstep(build_progress - 0.045, build_progress + 0.035, noisy_t);

	// Blue/black burn band around the transition front.
	float edge_distance = abs(noisy_t - build_progress);
	float burn_band = 1.0 - smoothstep(0.0, 0.08, edge_distance);

	// Near completion, let remaining shell warp/disintegrate from top downward.
	float warp_phase = smoothstep(0.72, 1.0, build_progress);
	float top_cut = 1.0 - warp_phase;
	float top_dissolve = smoothstep(top_cut - 0.1, top_cut + 0.08, noisy_t);

	vec3 shell_col = mix(steel_color.rgb, char_color.rgb, burn_band * 0.75);
	vec3 lit_final = final_color.rgb;
	vec3 albedo = mix(shell_col, lit_final, built_mask);

	float shell_alpha = (1.0 - built_mask) * (1.0 - top_dissolve);
	float alpha = clamp(shell_alpha * 0.88 + built_mask, 0.0, 1.0);

	ALBEDO = albedo;
	ALPHA = alpha;
	METALLIC = mix(0.82, 0.45, built_mask);
	ROUGHNESS = mix(0.22, 0.45, built_mask);
	EMISSION = burn_glow_color.rgb * (burn_band * (1.0 - built_mask) * 2.8);
}
