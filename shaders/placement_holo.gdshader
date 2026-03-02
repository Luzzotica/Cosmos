shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 tint_color : source_color = vec4(0.0, 1.0, 0.0, 0.5);
uniform vec3 emission_color : source_color = vec3(0.2, 0.85, 0.45);
uniform float alpha_strength : hint_range(0.0, 1.0) = 0.55;
uniform float scanline_density : hint_range(4.0, 120.0) = 44.0;
uniform float scanline_speed : hint_range(0.0, 6.0) = 1.4;
uniform float wave_scale : hint_range(0.2, 12.0) = 3.8;
uniform float wave_speed : hint_range(0.0, 8.0) = 2.2;
uniform float wave_strength : hint_range(0.0, 0.6) = 0.12;
uniform float fuzz_strength : hint_range(0.0, 0.8) = 0.18;
uniform float edge_boost : hint_range(0.0, 2.0) = 0.45;
uniform float is_valid : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave_time = TIME * wave_speed;
	float wave = sin((world_pos.x + world_pos.z) * wave_scale + wave_time);
	float ripple = sin(world_pos.y * (wave_scale * 1.6) - wave_time * 0.7);
	VERTEX.xyz += NORMAL * ((wave + ripple) * 0.5 * wave_strength);
}

void fragment() {
	float scan = sin((world_pos.y * scanline_density) - (TIME * scanline_speed));
	scan = 0.58 + scan * 0.42;

	float fuzz = hash31(vec3(world_pos.xz * 6.3, floor((world_pos.y + TIME * 0.8) * 8.0)));
	fuzz = mix(1.0 - fuzz_strength, 1.0 + fuzz_strength, fuzz);

	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float edge = 1.0 + fresnel * edge_boost;

	vec3 base_tint = tint_color.rgb * scan * fuzz;
	vec3 final_emission = emission_color * edge * mix(0.65, 1.0, is_valid);

	ALBEDO = base_tint;
	EMISSION = final_emission;
	ALPHA = clamp(tint_color.a * alpha_strength * scan, 0.08, 0.95);
}
