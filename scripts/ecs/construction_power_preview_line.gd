extends Node3D
class_name ConstructionPowerPreviewLine
## Visual-only line for construction preview connections. No collision. Dim appearance.
const POWER_LINE_RENDER_RADIUS: float = 0.12
const POWER_LINE_MIN_SEGMENT_LENGTH: float = 0.02
const POWER_LINE_TAPER_LENGTH: float = 0.8


func setup(pos_a: Vector3, pos_b: Vector3, struct_a: Node3D, struct_b: Node3D) -> void:
	_build_line_mesh(pos_a, pos_b, struct_a, struct_b)


func _build_line_mesh(pos_a: Vector3, pos_b: Vector3, struct_a: Node3D, struct_b: Node3D) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.3, 0.5, 0.4)
	material.emission_enabled = true
	material.emission = Color(0.1, 0.25, 0.45)
	material.emission_energy_multiplier = 0.8
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_receive_shadows = true

	var start_radius: float = _get_taper_radius(struct_a)
	var end_radius: float = _get_taper_radius(struct_b)

	var delta: Vector3 = pos_b - pos_a
	var distance: float = delta.length()
	if distance < POWER_LINE_MIN_SEGMENT_LENGTH:
		delta = Vector3.FORWARD * POWER_LINE_MIN_SEGMENT_LENGTH
		distance = POWER_LINE_MIN_SEGMENT_LENGTH
		pos_b = pos_a + delta
	var direction: Vector3 = delta / distance

	var max_stop_total: float = maxf(distance - POWER_LINE_MIN_SEGMENT_LENGTH, 0.0)
	var stop_total: float = start_radius + end_radius
	if stop_total > max_stop_total and stop_total > 0.0:
		var stop_scale: float = max_stop_total / stop_total
		start_radius *= stop_scale
		end_radius *= stop_scale

	var stop_start: Vector3 = pos_a + direction * start_radius
	var stop_end: Vector3 = pos_b - direction * end_radius
	var visible_length: float = stop_start.distance_to(stop_end)
	if visible_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		return

	var max_taper_each_side: float = maxf((visible_length - POWER_LINE_MIN_SEGMENT_LENGTH) * 0.5, 0.0)
	var taper_length: float = minf(POWER_LINE_TAPER_LENGTH, max_taper_each_side)
	var start_taper_end: Vector3 = stop_start + direction * taper_length
	var end_taper_start: Vector3 = stop_end - direction * taper_length

	if taper_length >= POWER_LINE_MIN_SEGMENT_LENGTH:
		_add_segment(stop_start, start_taper_end, 0.0, POWER_LINE_RENDER_RADIUS, material)
		_add_segment(end_taper_start, stop_end, POWER_LINE_RENDER_RADIUS, 0.0, material)

	var center_length: float = start_taper_end.distance_to(end_taper_start)
	if center_length >= POWER_LINE_MIN_SEGMENT_LENGTH:
		_add_segment(start_taper_end, end_taper_start, POWER_LINE_RENDER_RADIUS, POWER_LINE_RENDER_RADIUS, material)


func _add_segment(start_pos: Vector3, end_pos: Vector3, start_radius: float, end_radius: float, material: StandardMaterial3D) -> void:
	var segment_length: float = start_pos.distance_to(end_pos)
	if segment_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		return

	var segment_instance: MeshInstance3D = MeshInstance3D.new()
	var segment_mesh: CylinderMesh = CylinderMesh.new()
	segment_mesh.bottom_radius = end_radius
	segment_mesh.top_radius = start_radius
	segment_mesh.height = segment_length
	segment_instance.mesh = segment_mesh
	segment_instance.material_override = material
	segment_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var midpoint: Vector3 = (start_pos + end_pos) / 2.0
	segment_instance.position = midpoint

	var direction: Vector3 = (end_pos - start_pos).normalized()
	if direction.length() > 0.01:
		var up: Vector3 = Vector3.UP
		if abs(direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		segment_instance.look_at_from_position(midpoint, midpoint + direction, up)
		segment_instance.rotate_object_local(Vector3(1, 0, 0), PI / 2)

	add_child(segment_instance)


func _get_taper_radius(struct: Node3D) -> float:
	if struct == null:
		return 1.2
	if BuildManager == null or not BuildManager.has_method("get_building_data"):
		return 1.2
	var building_type: String = str(struct.get("building_type"))
	if building_type.is_empty():
		return 1.2
	var data: Resource = BuildManager.get_building_data(building_type)
	if data == null:
		return 1.2
	var configured: Variant = data.get("placement_sphere_radius")
	if configured == null:
		return 1.2
	return maxf(float(configured), POWER_LINE_MIN_SEGMENT_LENGTH)


## Update positions when structures move.
func update_positions(pos_a: Vector3, pos_b: Vector3, struct_a: Node3D, struct_b: Node3D) -> void:
	for child in get_children():
		child.queue_free()
	_build_line_mesh(pos_a, pos_b, struct_a, struct_b)
