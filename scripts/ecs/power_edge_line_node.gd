extends Node3D
class_name PowerEdgeLineNode
## Line node for a power edge. Contains mesh and Area3D for blockage detection.
## Set edge_entity before adding to tree. Area3D body_entered/exited update C_PowerEdge.is_blocked.

const C_PowerEdge = preload("res://scripts/ecs/components/c_power_edge.gd")

const POWER_LINE_RENDER_RADIUS: float = 0.15
const POWER_LINE_MIN_SEGMENT_LENGTH: float = 0.02
const POWER_LINE_TAPER_LENGTH: float = 0.8
const DEFAULT_TAPER_RADIUS: float = 1.2

var edge_entity: Node = null  # Entity with C_PowerEdge
var _blocking_count: int = 0


func setup(pos_a: Vector3, pos_b: Vector3, struct_a: Node3D, struct_b: Node3D) -> void:
	_build_line_mesh(pos_a, pos_b, struct_a, struct_b)
	_build_area(pos_a, pos_b)


func _build_line_mesh(pos_a: Vector3, pos_b: Vector3, struct_a: Node3D, struct_b: Node3D) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.45, 0.9, 0.85)
	material.emission_enabled = true
	material.emission = Color(0.15, 0.5, 0.95)
	material.emission_energy_multiplier = 3.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_receive_shadows = true

	var delta: Vector3 = pos_b - pos_a
	var distance: float = delta.length()
	if distance < POWER_LINE_MIN_SEGMENT_LENGTH:
		delta = Vector3.FORWARD * POWER_LINE_MIN_SEGMENT_LENGTH
		distance = POWER_LINE_MIN_SEGMENT_LENGTH
		pos_b = pos_a + delta
	var direction: Vector3 = delta / distance

	var start_radius: float = _get_taper_radius(struct_a)
	var end_radius: float = _get_taper_radius(struct_b)
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


static func get_connection_anchor(struct: Node3D) -> Vector3:
	if struct == null or not struct.is_inside_tree():
		return Vector3.ZERO
	var connection_point: Node3D = struct.get_node_or_null("ConnectionPoint") as Node3D
	if connection_point and connection_point.is_inside_tree():
		return connection_point.global_position
	var top_y: float = struct.global_position.y + 0.8
	for child in struct.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.mesh:
				var world_aabb: AABB = mi.mesh.get_aabb() * mi.global_transform
				top_y = maxf(top_y, world_aabb.end.y)
	return Vector3(struct.global_position.x, top_y, struct.global_position.z)


func _get_taper_radius(struct: Node3D) -> float:
	if struct == null:
		return DEFAULT_TAPER_RADIUS
	if BuildManager == null or not BuildManager.has_method("get_building_data"):
		return DEFAULT_TAPER_RADIUS
	var building_type: String = str(struct.get("building_type"))
	if building_type.is_empty():
		return DEFAULT_TAPER_RADIUS
	var data: Resource = BuildManager.get_building_data(building_type)
	if data == null:
		return DEFAULT_TAPER_RADIUS
	var configured: Variant = data.get("placement_sphere_radius")
	if configured == null:
		return DEFAULT_TAPER_RADIUS
	return maxf(float(configured), POWER_LINE_MIN_SEGMENT_LENGTH)


func _build_area(pos_a: Vector3, pos_b: Vector3) -> void:
	var area: Area3D = Area3D.new()
	area.name = "PowerEdgeArea"
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 0xFFFFFFFF  # Detect all layers, filter in callback

	var shape: CylinderShape3D = CylinderShape3D.new()
	var length: float = pos_a.distance_to(pos_b)
	shape.height = maxf(length, 0.5)
	shape.radius = 0.5

	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	area.add_child(col)

	var midpoint: Vector3 = (pos_a + pos_b) / 2.0
	area.position = midpoint
	var direction: Vector3 = (pos_b - pos_a).normalized()
	if direction.length() > 0.01:
		var up: Vector3 = Vector3.UP
		if abs(direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		# Node not in tree yet; use Basis instead of look_at
		var basis: Basis = Basis.looking_at(direction, up)
		area.transform = Transform3D(basis, midpoint)
		area.rotate_object_local(Vector3(1, 0, 0), -PI / 2)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _is_enemy(body: Node) -> bool:
	if body is CharacterBody3D or body is RigidBody3D:
		if body.is_in_group("enemies"):
			return true
		var parent: Node = body.get_parent()
		if parent and parent.is_in_group("enemies"):
			return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if not _is_enemy(body):
		return
	_blocking_count += 1
	_update_blocked_state()


func _on_body_exited(body: Node3D) -> void:
	if not _is_enemy(body):
		return
	_blocking_count = maxi(0, _blocking_count - 1)
	_update_blocked_state()


func _update_blocked_state() -> void:
	if edge_entity == null or not is_instance_valid(edge_entity):
		return
	var c: C_PowerEdge = edge_entity.get_component(C_PowerEdge) as C_PowerEdge
	if c:
		c.is_blocked = _blocking_count > 0
