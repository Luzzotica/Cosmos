shader_type sky;

uniform vec3 space_color : source_color = vec3(0.02, 0.02, 0.05);

void sky() {
	COLOR = space_color;
}
