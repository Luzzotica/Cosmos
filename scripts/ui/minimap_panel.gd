extends Control
class_name MinimapPanel
## HUD minimap that projects world X/Z positions to 2D.

@export var refresh_interval: float = 0.1
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.9) # #000000
@export var border_color: Color = Color(0.643137, 0.262745, 0.133333, 1.0) # #a44322
@export var structure_color: Color = Color(0.972549, 0.737255, 0.0156863, 1.0) # #f8bc04
@export var asteroid_color: Color = Color(0.32549, 0.0588235, 0.117647, 0.95) # #530f1e
@export var enemy_color: Color = Color(0.643137, 0.262745, 0.133333, 1.0) # #a44322
@export var edge_color: Color = Color(0.972549, 0.737255, 0.0156863, 0.95) # #f8bc04
@export var disabled_edge_color: Color = Color(0.0196078, 0.0784314, 0.152941, 0.45) # #051427
@export var camera_marker_color: Color = Color(0.972549, 0.737255, 0.0156863, 1.0) # #f8bc04
@export var point_radius: float = 2.5
@export var edge_width: float = 1.5
@export var camera_marker_radius: float = 4.0

var _main: Node3D = null
var _rts_camera: Camera3D = null
var _structures_parent: Node3D = null
var _asteroids_parent: Node3D = null
var _enemies_parent: Node3D = null
var _world_bounds: Rect2 = Rect2(Vector2(-200, -200), Vector2(400, 400))
var _time_since_refresh: float = 0.0

var _structure_points: Array[Vector2] = []
var _asteroid_points: Array[Vector2] = []
var _enemy_points: Array[Vector2] = []
var _edge_segments_enabled: Array[PackedVector2Array] = []
var _edge_segments_disabled: Array[PackedVector2Array] = []
var _camera_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_resolve_scene_references()
	_refresh_draw_data()
	queue_redraw()


func _process(delta: float) -> void:
	_time_since_refresh += delta
	if _time_since_refresh < refresh_interval:
		return
	_time_since_refresh = 0.0
	_refresh_draw_data()
	queue_redraw()


func _draw() -> void:
	var panel_rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, background_color, true)
	draw_rect(panel_rect, border_color, false, 2.0)

	for segment in _edge_segments_disabled:
		if segment.size() == 2:
			draw_line(segment[0], segment[1], disabled_edge_color, edge_width)

	for segment in _edge_segments_enabled:
		if segment.size() == 2:
			draw_line(segment[0], segment[1], edge_color, edge_width)

	for point in _asteroid_points:
		draw_circle(point, point_radius, asteroid_color)
	for point in _structure_points:
		draw_circle(point, point_radius, structure_color)
	for point in _enemy_points:
		draw_circle(point, point_radius, enemy_color)

	draw_circle(_camera_point, camera_marker_radius, camera_marker_color)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button_event.button_index != MOUSE_BUTTON_LEFT or not mouse_button_event.pressed:
		return

	_resolve_scene_references()
	if _rts_camera == null:
		return

	var target_world_position: Vector3 = _minimap_to_world(mouse_button_event.position)
	if _rts_camera.has_method("set_camera_position"):
		_rts_camera.call("set_camera_position", target_world_position)

	accept_event()


func _refresh_draw_data() -> void:
	_resolve_scene_references()
	_world_bounds = _get_world_bounds()

	_structure_points = _collect_world_points(_structures_parent)
	_asteroid_points = _collect_world_points(_asteroids_parent)
	_enemy_points = _collect_world_points(_enemies_parent)
	_collect_edge_segments()
	_update_camera_marker()


func _resolve_scene_references() -> void:
	if _main == null or not is_instance_valid(_main):
		_main = get_tree().root.get_node_or_null("Main") as Node3D

	if _main == null:
		return

	if _rts_camera == null or not is_instance_valid(_rts_camera):
		_rts_camera = _main.get_node_or_null("RTSCamera") as Camera3D
	if _structures_parent == null or not is_instance_valid(_structures_parent):
		_structures_parent = _main.get_node_or_null("Structures") as Node3D
	if _asteroids_parent == null or not is_instance_valid(_asteroids_parent):
		_asteroids_parent = _main.get_node_or_null("Asteroids") as Node3D
	if _enemies_parent == null or not is_instance_valid(_enemies_parent):
		_enemies_parent = _main.get_node_or_null("Enemies") as Node3D


func _collect_world_points(parent_node: Node3D) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if parent_node == null or not is_instance_valid(parent_node):
		return points

	for child in parent_node.get_children():
		if child is Node3D and is_instance_valid(child):
			var node3d: Node3D = child as Node3D
			points.append(_world_to_minimap(node3d.global_position))

	return points


func _collect_edge_segments() -> void:
	_edge_segments_enabled.clear()
	_edge_segments_disabled.clear()

	if not PowerGraphManager or not PowerGraphManager.has_method("get_edges"):
		return

	var edges: Dictionary = PowerGraphManager.get_edges()
	var seen: Dictionary = {}

	for start_node in edges.keys():
		if not is_instance_valid(start_node):
			continue

		var neighbor_map: Variant = edges[start_node]
		if not (neighbor_map is Dictionary):
			continue

		for end_node in (neighbor_map as Dictionary).keys():
			if not is_instance_valid(end_node):
				continue

			var edge_key: String = _make_edge_key(start_node, end_node)
			if seen.has(edge_key):
				continue
			seen[edge_key] = true

			var start_world: Vector3 = _power_node_world_position(start_node)
			var end_world: Vector3 = _power_node_world_position(end_node)
			var segment: PackedVector2Array = PackedVector2Array([
				_world_to_minimap(start_world),
				_world_to_minimap(end_world)
			])

			var is_enabled: bool = true
			if PowerGraphManager.has_method("is_edge_enabled"):
				is_enabled = PowerGraphManager.is_edge_enabled(start_node, end_node)

			if is_enabled:
				_edge_segments_enabled.append(segment)
			else:
				_edge_segments_disabled.append(segment)


func _update_camera_marker() -> void:
	if _rts_camera != null and is_instance_valid(_rts_camera):
		_camera_point = _world_to_minimap(_rts_camera.global_position)
	else:
		_camera_point = size * 0.5


func _get_world_bounds() -> Rect2:
	if _rts_camera != null and is_instance_valid(_rts_camera):
		var bounds_min_value: Variant = _rts_camera.get("bounds_min")
		var bounds_max_value: Variant = _rts_camera.get("bounds_max")
		if bounds_min_value is Vector3 and bounds_max_value is Vector3:
			var bounds_min: Vector3 = bounds_min_value as Vector3
			var bounds_max: Vector3 = bounds_max_value as Vector3
			var width: float = maxf(0.001, bounds_max.x - bounds_min.x)
			var depth: float = maxf(0.001, bounds_max.z - bounds_min.z)
			return Rect2(Vector2(bounds_min.x, bounds_min.z), Vector2(width, depth))

	if _main != null and is_instance_valid(_main):
		var map_data: Variant = _main.get("_current_map_data")
		if map_data != null:
			var map_size_value: Variant = map_data.get("map_size")
			if map_size_value is Vector2:
				var map_size: Vector2 = map_size_value as Vector2
				var half_size: Vector2 = map_size * 0.5
				return Rect2(Vector2(-half_size.x, -half_size.y), map_size)

	return Rect2(Vector2(-200, -200), Vector2(400, 400))


func _world_to_minimap(world_position: Vector3) -> Vector2:
	var width: float = maxf(0.001, _world_bounds.size.x)
	var depth: float = maxf(0.001, _world_bounds.size.y)
	var normalized_x: float = clampf((world_position.x - _world_bounds.position.x) / width, 0.0, 1.0)
	var normalized_z: float = clampf((world_position.z - _world_bounds.position.y) / depth, 0.0, 1.0)
	return Vector2(normalized_x * size.x, normalized_z * size.y)


func _minimap_to_world(minimap_position: Vector2) -> Vector3:
	var width: float = maxf(0.001, _world_bounds.size.x)
	var depth: float = maxf(0.001, _world_bounds.size.y)
	var normalized_x: float = clampf(minimap_position.x / maxf(1.0, size.x), 0.0, 1.0)
	var normalized_z: float = clampf(minimap_position.y / maxf(1.0, size.y), 0.0, 1.0)
	var world_x: float = _world_bounds.position.x + normalized_x * width
	var world_z: float = _world_bounds.position.y + normalized_z * depth
	return Vector3(world_x, 0.0, world_z)


func _power_node_world_position(node: Node) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	if node.get_parent() is Node3D:
		return (node.get_parent() as Node3D).global_position
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3.ZERO


func _make_edge_key(start_node: Object, end_node: Object) -> String:
	var start_id: int = start_node.get_instance_id()
	var end_id: int = end_node.get_instance_id()
	if start_id < end_id:
		return "%d:%d" % [start_id, end_id]
	return "%d:%d" % [end_id, start_id]
