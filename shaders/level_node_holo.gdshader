shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 color : source_color = vec4(0.35, 1.0, 0.45, 0.95);
uniform float dot_density : hint_range(8.0, 64.0) = 24.0;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.8;
uniform float is_locked : hint_range(0.0, 1.0) = 0.0;
uniform float outline_radius : hint_range(0.2, 0.5) = 0.45;
uniform float outline_width : hint_range(0.01, 0.1) = 0.045;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);
	// Normalize angle to 0..1 for dot pattern
	float angle_norm = (angle + 3.14159265) / 6.2831853;
	float dot_phase = fract(angle_norm * dot_density);
	// Dots: first 20% of each segment is visible
	float dot_visible = step(dot_phase, 0.2);
	// Ring at outline_radius
	float ring = smoothstep(outline_width, 0.0, abs(dist - outline_radius));
	float alpha = ring * dot_visible * color.a;
	vec3 base_color = color.rgb;
	if (is_locked > 0.5) {
		base_color = mix(base_color, vec3(0.3, 0.3, 0.35), 0.7);
		alpha *= 0.6;
	}
	ALBEDO = base_color;
	EMISSION = base_color * glow_strength;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
