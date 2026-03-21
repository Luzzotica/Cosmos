shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(0.35, 1.0, 0.45, 0.95);
uniform vec4 interior_color : source_color = vec4(0.0, 0.03, 0.0, 0.75);
uniform float border_width : hint_range(0.005, 0.06) = 0.02;
uniform float border_softness : hint_range(0.0, 0.04) = 0.012;
uniform float dot_density : hint_range(10.0, 80.0) = 40.0;
uniform float dash_aa_scale : hint_range(0.5, 4.0) = 1.5;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.5;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.08;
uniform float scanline_density : hint_range(20.0, 200.0) = 80.0;
uniform float open_progress : hint_range(0.0, 1.0) = 1.0;
uniform float corner_radius : hint_range(0.0, 0.1) = 0.042;
uniform float border_scan_speed : hint_range(0.0, 2.0) = 0.6;
uniform float border_scan_density : hint_range(10.0, 120.0) = 60.0;
uniform float border_scan_strength : hint_range(0.0, 0.4) = 0.12;
uniform float edge_fade_uv : hint_range(0.0, 0.12) = 0.045;

float rounded_rect_sdf(vec2 p, vec2 half_size, float radius) {
	vec2 d = abs(p) - half_size + vec2(radius);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - 0.5;
	vec2 half_size = vec2(0.5, 0.5);

	float sdf = rounded_rect_sdf(centered, half_size, corner_radius);
	float d = abs(sdf);

	float w = max(border_width, 0.0001);
	float s = max(border_softness, 0.0);
	float border_mask = 1.0 - smoothstep(0.0, w + s, d);

	float perimeter_t;
	if (abs(centered.x) / half_size.x > abs(centered.y) / half_size.y) {
		perimeter_t = (centered.y / half_size.y + 1.0) * 0.5 + step(0.0, centered.x) * 2.0;
	} else {
		perimeter_t = (centered.x / half_size.x + 1.0) * 0.5 + step(0.0, centered.y) * 2.0 + 1.0;
	}
	float pt_dots = perimeter_t * dot_density;
	float h = fract(pt_dots);
	float fw_dots = fwidth(pt_dots);
	float aa = max(fw_dots * dash_aa_scale, 1e-4);
	float dot_visible = 1.0 - smoothstep(0.25 - aa, 0.25 + aa, h);
	border_mask *= dot_visible;

	float scan_coord = perimeter_t * border_scan_density + TIME * border_scan_speed;
	float sc = fract(scan_coord);
	float fw_scan = fwidth(scan_coord);
	float aa_scan = max(fw_scan * dash_aa_scale, 1e-4);
	float scan_band = smoothstep(0.5 - aa_scan, 0.5 + aa_scan, sc);
	float border_scan = 1.0 - border_scan_strength * scan_band;

	float interior_mask = smoothstep(0.002, -0.002, sdf);

	float border_progress = smoothstep(0.0, 0.5, open_progress);
	float fill_progress = smoothstep(0.4, 1.0, open_progress);

	float scanline = 1.0 - scanline_strength * step(0.5, fract(uv.y * scanline_density));
	scanline = mix(1.0, scanline, fill_progress);

	float edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float edge_f = max(edge_fade_uv, 1e-4);
	float edge_soft = smoothstep(0.0, edge_f, edge_dist);

	vec3 border_col = border_color.rgb;
	vec3 interior_col = interior_color.rgb * scanline;

	float border_alpha = border_mask * border_color.a * border_progress * border_scan * edge_soft;
	float interior_alpha = interior_mask * interior_color.a * fill_progress * scanline;

	float glow_width = w * 3.0 + s * 2.0;
	float glow = (1.0 - smoothstep(0.0, glow_width, d)) * glow_strength * border_progress * border_scan * edge_soft;

	float center_dist = length(centered);
	float point_glow = smoothstep(0.25, 0.0, center_dist) * (1.0 - smoothstep(0.0, 0.2, open_progress));
	point_glow *= 2.0 * edge_soft;

	vec3 final_color = mix(interior_col, border_col, clamp(border_alpha, 0.0, 1.0));
	final_color += border_col * glow * 0.3;
	final_color += border_col * point_glow;

	float final_alpha = max(max(border_alpha, interior_alpha), point_glow * 0.95) + glow * 0.15;
	final_alpha = clamp(final_alpha, 0.0, 0.95);

	COLOR = vec4(final_color, final_alpha);
}
