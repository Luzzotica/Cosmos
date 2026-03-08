extends Node
## Batches power line segments into MultiMeshes to reduce draw calls.

const POWER_LINE_RENDER_RADIUS: float = 0.15
const POWER_LINE_MIN_SEGMENT_LENGTH: float = 0.02
const POWER_LINE_TAPER_LENGTH: float = 0.8
## Min fraction of distance that must remain visible (caps taper radii)
const MIN_VISIBLE_FRACTION: float = 0.5
const FAR_AWAY: Vector3 = Vector3(0.0, -10000.0, 0.0)

var _root: Node3D = null
var _pool_key: String = "power_line_cylinder"
var _pool_data: Dictionary = {}
var _material: StandardMaterial3D = null
var _mesh: CylinderMesh = null
var _line_allocations: Dictionary = {}  # edge_key -> [indices]
var _free_indices: Array = []


func _ready() -> void:
	_ensure_mesh_and_material()
	_ensure_root()


func _ensure_mesh_and_material() -> void:
	if _mesh != null:
		return
	_mesh = CylinderMesh.new()
	_mesh.top_radius = POWER_LINE_RENDER_RADIUS
	_mesh.bottom_radius = POWER_LINE_RENDER_RADIUS
	_mesh.height = 1.0
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.2, 0.45, 0.9, 0.85)
	_material.emission_enabled = true
	_material.emission = Color(0.15, 0.5, 0.95)
	_material.emission_energy_multiplier = 3.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.disable_receive_shadows = true


func _ensure_root() -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main and main is Node3D:
		if _root == null or not is_instance_valid(_root):
			_root = Node3D.new()
			_root.name = "LineBatchRoot"
		# Always parent to Main when available so lines render in the game 3D world
		if _root.get_parent() != main:
			if _root.get_parent():
				_root.get_parent().remove_child(_root)
			main.add_child(_root)
		return
	if _root != null and is_instance_valid(_root):
		return
	_root = Node3D.new()
	_root.name = "LineBatchRoot"
	add_child(_root)


func _ensure_pool() -> void:
	if _pool_data.has(_pool_key):
		return
	_ensure_root()
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "PowerLineSegments"
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 0
	mm.mesh = _mesh
	mmi.multimesh = mm
	mmi.material_override = _material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)
	_pool_data[_pool_key] = {
		"multimesh": mm,
		"free_indices": []
	}


## Allocate batched line segments. pos1/pos2 are connection anchors; start_radius/end_radius are taper radii at endpoints.
## Returns an edge_key that can be passed to free_line.
func allocate_line(edge_key: String, pos1: Vector3, pos2: Vector3, start_radius: float = 0.0, end_radius: float = 0.0) -> void:
	if edge_key.is_empty():
		return
	if _line_allocations.has(edge_key):
		free_line(edge_key)
	_ensure_pool()
	var pool: Dictionary = _pool_data[_pool_key]
	var mm: MultiMesh = pool.multimesh
	var free_indices: Array = pool.free_indices

	var delta: Vector3 = pos2 - pos1
	var distance: float = delta.length()
	if distance < POWER_LINE_MIN_SEGMENT_LENGTH:
		delta = Vector3.FORWARD * POWER_LINE_MIN_SEGMENT_LENGTH
		distance = delta.length()
	var direction: Vector3 = delta / distance
	# Cap taper radii so at least MIN_VISIBLE_FRACTION of the line is visible
	var max_stop_total: float = distance * (1.0 - MIN_VISIBLE_FRACTION)
	var abs_max: float = maxf(distance - POWER_LINE_MIN_SEGMENT_LENGTH, 0.0)
	max_stop_total = minf(max_stop_total, abs_max)
	var stop_total: float = start_radius + end_radius
	if stop_total > max_stop_total and stop_total > 0.0:
		var stop_scale: float = max_stop_total / stop_total
		start_radius *= stop_scale
		end_radius *= stop_scale
	var stop_start: Vector3 = pos1 + direction * start_radius
	var stop_end: Vector3 = pos2 - direction * end_radius
	var visible_length: float = stop_start.distance_to(stop_end)
	if visible_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		return
	var max_taper_each_side: float = maxf((visible_length - POWER_LINE_MIN_SEGMENT_LENGTH) * 0.5, 0.0)
	var taper_length: float = minf(POWER_LINE_TAPER_LENGTH, max_taper_each_side)
	var start_taper_end: Vector3 = stop_start + direction * taper_length
	var end_taper_start: Vector3 = stop_end - direction * taper_length
	var indices: Array = []
	# Segment 1: taper start
	if taper_length >= POWER_LINE_MIN_SEGMENT_LENGTH:
		var idx: int = _alloc_index(pool, free_indices, mm)
		if idx >= 0:
			var t: Transform3D = _segment_transform(stop_start, start_taper_end, 0.0, POWER_LINE_RENDER_RADIUS)
			mm.set_instance_transform(idx, t)
			indices.append(idx)
	# Segment 2: center
	var center_length: float = start_taper_end.distance_to(end_taper_start)
	if center_length >= POWER_LINE_MIN_SEGMENT_LENGTH:
		var idx: int = _alloc_index(pool, free_indices, mm)
		if idx >= 0:
			var t: Transform3D = _segment_transform(start_taper_end, end_taper_start, POWER_LINE_RENDER_RADIUS, POWER_LINE_RENDER_RADIUS)
			mm.set_instance_transform(idx, t)
			indices.append(idx)
	# Segment 3: taper end
	if taper_length >= POWER_LINE_MIN_SEGMENT_LENGTH:
		var idx: int = _alloc_index(pool, free_indices, mm)
		if idx >= 0:
			var t: Transform3D = _segment_transform(end_taper_start, stop_end, POWER_LINE_RENDER_RADIUS, 0.0)
			mm.set_instance_transform(idx, t)
			indices.append(idx)
	pool.free_indices = free_indices
	_pool_data[_pool_key] = pool
	_line_allocations[edge_key] = indices


func _alloc_index(pool: Dictionary, free_indices: Array, mm: MultiMesh) -> int:
	var index: int = -1
	if free_indices.is_empty():
		index = mm.instance_count
		mm.instance_count = index + 1
	else:
		index = int(free_indices.pop_back())
	return index


func _segment_transform(start_pos: Vector3, end_pos: Vector3, _start_radius: float, _end_radius: float) -> Transform3D:
	var segment_length: float = start_pos.distance_to(end_pos)
	if segment_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		return Transform3D(Basis.IDENTITY, FAR_AWAY)
	var midpoint: Vector3 = (start_pos + end_pos) * 0.5
	var direction: Vector3 = (end_pos - start_pos).normalized()
	# CylinderMesh already uses POWER_LINE_RENDER_RADIUS; only scale length (Y) axis
	var up: Vector3 = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x_axis: Vector3 = direction.cross(up).normalized()
	if x_axis.length() < 0.01:
		x_axis = Vector3.RIGHT
	var z_axis: Vector3 = x_axis.cross(direction).normalized()
	var cyl_basis: Basis = Basis(x_axis, direction, z_axis).scaled(Vector3(1.0, segment_length, 1.0))
	return Transform3D(cyl_basis, midpoint)


func free_line(edge_key: String) -> void:
	if not _line_allocations.has(edge_key):
		return
	if not _pool_data.has(_pool_key):
		_line_allocations.erase(edge_key)
		return
	var pool: Dictionary = _pool_data[_pool_key]
	var mm: MultiMesh = pool.multimesh
	var free_indices: Array = pool.free_indices
	for idx in _line_allocations[edge_key]:
		free_indices.append(idx)
		mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, FAR_AWAY))
	pool.free_indices = free_indices
	_pool_data[_pool_key] = pool
	_line_allocations.erase(edge_key)
