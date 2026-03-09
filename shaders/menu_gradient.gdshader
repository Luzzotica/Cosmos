shader_type canvas_item;

// 100% black on the left, fade to alpha=0 by 1/3 from left.

void fragment() {
	float alpha = 1.0 - smoothstep(0.0, 0.333, UV.x);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
