extends Control
## Draws the journey path between level nodes on the story map select screen.

const COLOR_PATH: Color = Color(0.643, 0.263, 0.133, 0.8)  # Burnt Copper
const PATH_WIDTH: float = 3.0


func _draw() -> void:
	var points: Variant = get_meta("path_points") if has_meta("path_points") else null
	if points == null or not (points is PackedVector2Array):
		return
	var pts: PackedVector2Array = points as PackedVector2Array
	if pts.size() < 2:
		return
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], COLOR_PATH)
		draw_circle(pts[i], PATH_WIDTH, COLOR_PATH)
	draw_circle(pts[pts.size() - 1], PATH_WIDTH, COLOR_PATH)
