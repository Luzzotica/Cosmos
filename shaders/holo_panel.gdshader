shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(0.35, 1.0, 0.45, 0.95);
uniform vec4 interior_color : source_color = vec4(0.0, 0.03, 0.0, 0.75);
uniform float border_width : hint_range(0.005, 0.06) = 0.02;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.08;
uniform float scanline_density : hint_range(20.0, 200.0) = 80.0;
uniform float open_progress : hint_range(0.0, 1.0) = 1.0;
uniform float corner_radius : hint_range(0.0, 0.1) = 0.042;
uniform float border_inset : hint_range(0.005, 0.12) = 0.035;
uniform float neon_boost : hint_range(0.0, 2.5) = 0.85;

float rounded_rect_sdf(vec2 p, vec2 half_size, float radius) {
	vec2 d = abs(p) - half_size + vec2(radius);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - 0.5;
	vec2 half_size = vec2(0.5 - border_inset, 0.5 - border_inset);

	float sdf = rounded_rect_sdf(centered, half_size, corner_radius);
	float d = abs(sdf);

	float w = max(border_width, 0.0001);
	float border_mask = smoothstep(w, 0.0, d);

	float interior_mask = smoothstep(0.002, -0.002, sdf);

	float border_progress = smoothstep(0.0, 0.5, open_progress);
	float fill_progress = smoothstep(0.4, 1.0, open_progress);

	float scanline = 1.0 - scanline_strength * step(0.5, fract(uv.y * scanline_density));
	scanline = mix(1.0, scanline, fill_progress);

	vec3 border_col = border_color.rgb;
	vec3 interior_col = interior_color.rgb * scanline;

	float stroke = border_mask * border_progress;
	float border_alpha = stroke * border_color.a;

	float interior_alpha = interior_mask * interior_color.a * fill_progress * scanline;

	float center_dist = length(centered);
	float point_glow = smoothstep(0.25, 0.0, center_dist) * (1.0 - smoothstep(0.0, 0.2, open_progress));
	point_glow *= 2.0;

	vec3 final_color = mix(interior_col, border_col, clamp(border_alpha, 0.0, 1.0));
	final_color += border_col * stroke * neon_boost;
	final_color += border_col * point_glow;

	float final_alpha = max(max(border_alpha, interior_alpha), point_glow * 0.95);
	final_alpha = clamp(final_alpha, 0.0, 0.95);

	COLOR = vec4(final_color, final_alpha);
}
