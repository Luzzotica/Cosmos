shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Palette-driven nebula/aurora colors:
// #000000, #051427, #530f1e, #a44322, #f8bc04
uniform vec3 color_deep : source_color = vec3(0.0196, 0.0784, 0.1529);   // #051427
uniform vec3 color_mid : source_color = vec3(0.3255, 0.0588, 0.1176);    // #530f1e
uniform vec3 color_warm : source_color = vec3(0.6431, 0.2627, 0.1333);   // #a44322
uniform vec3 color_hot : source_color = vec3(0.9725, 0.7373, 0.0157);    // #f8bc04
uniform float intensity : hint_range(0.0, 2.5) = 1.05;
uniform float ribbon_density : hint_range(4.0, 80.0) = 28.0;
uniform float drift_speed : hint_range(0.0, 0.15) = 0.02;
uniform float swirl_strength : hint_range(0.0, 0.2) = 0.055;
uniform vec2 parallax_offset = vec2(0.0, 0.0);
uniform float seed : hint_range(0.0, 10000.0) = 0.0;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	vec2 s = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

float fbm(vec2 uv) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(uv);
		uv *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 uv = UV + parallax_offset;
	float t = TIME * drift_speed;

	float swirl_x = sin(uv.y * 10.0 + t * 1.3 + seed * 0.0007) * swirl_strength;
	float swirl_y = cos(uv.x * 8.0 - t * 1.1 + seed * 0.0009) * (swirl_strength * 0.65);
	vec2 wuv = uv + vec2(swirl_x, swirl_y);

	float flow_a = fbm(wuv * vec2(2.8, 2.2) + vec2(t * 0.18, -t * 0.14) + vec2(seed * 0.001));
	float flow_b = fbm(wuv * vec2(3.6, 2.9) + vec2(-t * 0.12, t * 0.16) + vec2(seed * 0.002, seed * 0.0016));
	vec2 flow = vec2(flow_a - 0.5, flow_b - 0.5);
	wuv += flow * 0.24;

	float noise_a = fbm(wuv * vec2(5.2, 2.9) + vec2(t * 0.25, -t * 0.12));
	float noise_b = fbm((wuv + vec2(0.037, -0.029)) * vec2(5.2, 2.9) + vec2(t * 0.23, -t * 0.11));
	float noise = mix(noise_a, noise_b, 0.5);

	float bands_a = sin((wuv.x + flow.y * 0.35) * ribbon_density + noise * 8.2 + t * 1.1);
	float bands_b = sin((wuv.x * 1.05 - wuv.y * 0.22 + flow.x * 0.45) * (ribbon_density * 0.9) - t * 0.95);
	float interleave = 0.5 + 0.5 * sin(t * 0.75 + noise * 3.0);
	float bands = mix(bands_a, bands_b, interleave);
	float ribbons = pow(smoothstep(0.0, 1.0, abs(bands)), 1.06);

	float top_fade = smoothstep(-0.25, 0.55, uv.y);
	float side_fade = smoothstep(-0.15, 0.06, uv.x) * smoothstep(-0.15, 0.06, 1.0 - uv.x);

	float area_base = fbm(uv * vec2(1.3, 1.0) + vec2(seed * 0.0008, seed * 0.0011));
	float area_drift = fbm(uv * vec2(0.95, 0.8) + vec2(t * 0.045, -t * 0.03) + vec2(seed * 0.0005, seed * 0.0007));
	float area_mix = mix(area_base, area_drift, 0.55);
	float area_breath = 0.08 * sin(t * 0.55 + uv.x * 3.2 + uv.y * 2.3);
	float area_mask = smoothstep(0.44, 0.78, area_mix + area_breath);

	float dissolve_a = fbm(uv * vec2(2.4, 1.7) + vec2(-t * 0.075, t * 0.05) + vec2(seed * 0.0017, seed * 0.0013));
	float dissolve_b = fbm((uv + vec2(0.052, 0.041)) * vec2(2.4, 1.7) + vec2(-t * 0.071, t * 0.047) + vec2(seed * 0.0019, seed * 0.0015));
	float dissolve = smoothstep(0.36, 0.86, mix(dissolve_a, dissolve_b, 0.5));

	float region_mask = area_mask * dissolve;
	float backbone = smoothstep(0.34, 0.74, area_base);
	float presence_floor = 0.18 + 0.06 * sin(t * 0.3 + seed * 0.0004);
	region_mask = max(region_mask, backbone * presence_floor);

	float mask = ribbons * top_fade * side_fade * region_mask;

	float color_time = t * 2.0 + noise * 6.0;
	float w_deep = 0.5 + 0.5 * sin(color_time + 0.0);
	float w_mid = 0.5 + 0.5 * sin(color_time + 2.09439510239);
	float w_warm = 0.5 + 0.5 * sin(color_time + 4.18879020479);
	float hot_spots = smoothstep(0.72, 0.95, noise + 0.2 * interleave);
	float sum_w = w_deep * 0.85 + w_mid * 1.0 + w_warm * 1.18 + hot_spots * 0.65;
	vec3 aurora_col = (
		color_deep * (w_deep * 0.85)
		+ color_mid * (w_mid * 1.0)
		+ color_warm * (w_warm * 1.18)
		+ color_hot * (hot_spots * 0.65)
	) / max(sum_w, 0.0001);

	float pulse = 0.9 + 0.1 * sin(t * 2.2 + noise * 4.0);
	vec3 final_col = aurora_col * intensity * pulse * mask;
	float alpha = clamp(mask * (0.39 + 0.14 * noise), 0.0, 1.0);

	ALBEDO = final_col;
	ALPHA = alpha;
}
