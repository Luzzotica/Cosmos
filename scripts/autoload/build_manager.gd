extends Node
## BuildManager Singleton - Handles building placement and construction

# Preload PowerNode to ensure type is available
const PowerNodeClass: GDScript = preload("res://scripts/components/power_node.gd")
const PLACEMENT_HOLO_SHADER_PATH: String = "res://shaders/placement_holo.gdshader"

signal build_started(building_type: String)
signal build_cancelled
signal build_completed(building_type: String, position: Vector3)
signal placement_valid_changed(is_valid: bool)

enum BuildState {
	IDLE,
	DRAGGING,
	PLACING
}

var current_state: BuildState = BuildState.IDLE
var _dragging_building_type: String = ""
var _drag_position: Vector3 = Vector3.ZERO
var _placement_preview: Node3D = null
var _is_placement_valid: bool = false
var _placement_overlap_detector: Area3D = null
var _placement_overlap_counts: Dictionary = {}  # instance_id -> overlap count
var _preview_mesh_instances: Array[MeshInstance3D] = []
var _preview_holo_materials: Dictionary = {}  # mesh_instance_id -> ShaderMaterial
var _preview_collision_radius: float = 1.2
var _placement_holo_shader: Shader = null
var _preview_mesh_include_filter: Dictionary = {}
var _preview_mesh_exclude_filter: Dictionary = {}

# Range indicators
var _connection_range_indicator: MeshInstance3D = null
var _mining_range_indicator: MeshInstance3D = null
var _action_range_indicator: MeshInstance3D = null
var _connection_lines: Array[MeshInstance3D] = []
var _preview_max_connections: int = 0
var _preview_action_range: float = 0.0
var _preview_show_asteroid_targeting: bool = false
var _preview_show_enemy_targeting: bool = false
var _asteroid_highlights: Array[MeshInstance3D] = []
var _enemy_highlights: Array[MeshInstance3D] = []

# Building data cache
var _building_data: Dictionary = {}

const RANGE_RING_SEGMENTS: int = 96
const HIGHLIGHT_RING_SEGMENTS: int = 64
const DEFAULT_PLACEMENT_RADIUS: float = 1.2
const PLACEMENT_OCCUPANCY_MARGIN: float = 0.1
const POWER_LINE_RADIUS: float = 0.03
const POWER_LINE_CLEARANCE: float = 0.03
const POWER_LINE_RENDER_RADIUS: float = 0.15
const POWER_LINE_MIN_SEGMENT_LENGTH: float = 0.02
const POWER_LINE_TAPER_LENGTH: float = 0.4
const PREVIEW_ALPHA: float = 0.5
const PREVIEW_VALID_TINT: Color = Color(0.2, 0.72, 1.0, PREVIEW_ALPHA)
const PREVIEW_INVALID_TINT: Color = Color(1.0, 0.26, 0.22, PREVIEW_ALPHA)
const PREVIEW_VALID_EMISSION: Color = Color(0.08, 0.62, 1.0, 1.0)
const PREVIEW_INVALID_EMISSION: Color = Color(0.95, 0.2, 0.2, 1.0)

# Cooldown after placing to prevent auto-selection
var _placement_cooldown: float = 0.0
const PLACEMENT_COOLDOWN_DURATION: float = 0.2


func _ready() -> void:
	_load_building_data()
	_placement_holo_shader = load(PLACEMENT_HOLO_SHADER_PATH) as Shader
	set_process_input(true)
	set_process(true)


func _process(delta: float) -> void:
	if not _is_gameplay_active():
		_is_consuming_release = false
		return
	if GameState.is_game_over:
		return
	if _placement_cooldown > 0:
		_placement_cooldown -= delta


var _last_mouse_world_position: Vector3 = Vector3.ZERO
var _is_consuming_release: bool = false


func _input(event: InputEvent) -> void:
	if not _is_gameplay_active():
		# Never swallow UI clicks outside gameplay scenes.
		_is_consuming_release = false
		return
	if GameState.is_game_over:
		# Prevent stale release-consumption from eating UI button clicks.
		_is_consuming_release = false
		return

	# Always track mouse position for hotkey placement
	if event is InputEventMouseMotion:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera and camera.has_method("get_mouse_world_position"):
			_last_mouse_world_position = camera.get_mouse_world_position()
			# Update preview if in build mode
			if current_state != BuildState.IDLE:
				update_placement_preview(_last_mouse_world_position)
		return
	
	if event is InputEventMouseButton:
		var me: InputEventMouseButton = event as InputEventMouseButton
		if me.button_index == MOUSE_BUTTON_LEFT and not me.pressed and _is_consuming_release:
				_is_consuming_release = false
				get_viewport().set_input_as_handled()
				return
	
	if current_state == BuildState.IDLE:
		return
	
	# Escape to cancel placement
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			cancel_placement()
			get_viewport().set_input_as_handled()
			return
	
	# Confirm placement on left click, cancel on right click
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				confirm_placement()
				_is_consuming_release = true
				get_viewport().set_input_as_handled()
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				cancel_placement()
				get_viewport().set_input_as_handled()


func _load_building_data() -> void:
	# Load all building data resources
	var buildings_dir: String = "res://resources/buildings/"
	var dir: DirAccess = DirAccess.open(buildings_dir)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var resource: Resource = load(buildings_dir + file_name)
				if resource:
					_building_data[resource.id] = resource
			file_name = dir.get_next()


## Check if currently in build mode
var is_in_build_mode: bool:
	get:
		return current_state != BuildState.IDLE


## Check if a building can be placed (has enough resources)
func can_place_building(building_type: String) -> bool:
	var data: Resource = get_building_data(building_type)
	if not data:
		return false
	return GameState.minerals >= data.cost


## Get building data by type
func get_building_data(building_type: String) -> Resource:
	return _building_data.get(building_type)


## Start dragging a building for placement
func start_building(building_type: String, position: Vector3 = Vector3.ZERO) -> void:
	if not can_place_building(building_type):
		return
	
	_dragging_building_type = building_type
	current_state = BuildState.DRAGGING
	
	# Use provided position, or last known mouse position, or try to get current mouse position
	if position != Vector3.ZERO:
		_drag_position = position
	elif _last_mouse_world_position != Vector3.ZERO:
		_drag_position = _last_mouse_world_position
	else:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera and camera.has_method("get_mouse_world_position"):
			_drag_position = camera.get_mouse_world_position()
		else:
			_drag_position = Vector3.ZERO
	
	# Create placement preview
	_create_placement_preview(building_type)
	
	# Immediately update preview to mouse position
	update_placement_preview(_drag_position)
	
	build_started.emit(building_type)


## Update the placement preview position
func update_placement_preview(world_position: Vector3) -> void:
	if current_state == BuildState.IDLE:
		return
	
	_drag_position = world_position
	
	if _placement_preview:
		_placement_preview.global_position = world_position
		_update_placement_validity()
	
	# Update connection range indicator position
	if _connection_range_indicator:
		_connection_range_indicator.global_position = Vector3(world_position.x, 0.2, world_position.z)
	
	# Update mining range indicator position
	if _mining_range_indicator:
		_mining_range_indicator.global_position = Vector3(world_position.x, 0.15, world_position.z)
	
	# Update action range indicator position
	if _action_range_indicator:
		_action_range_indicator.global_position = Vector3(world_position.x, 0.18, world_position.z)
	
	# Update connection line to nearest power node
	_update_connection_preview(world_position)
	
	# Update placement target highlights based on building data flags.
	if _preview_show_asteroid_targeting:
		_update_asteroid_highlights(world_position)
		_clear_enemy_highlights()
	elif _preview_show_enemy_targeting:
		_update_enemy_highlights(world_position)
		_clear_asteroid_highlights()
	else:
		_clear_asteroid_highlights()
		_clear_enemy_highlights()


## Confirm building placement
func confirm_placement() -> void:
	if current_state == BuildState.IDLE or _dragging_building_type.is_empty():
		return
	
	if not _is_placement_valid:
		_play_sfx("structure_invalid_place", -8.0)
		return
	
	var data: Resource = get_building_data(_dragging_building_type)
	if not data:
		_reset_build_state()
		return
	
	# Consume resources
	if not GameState.consume_minerals(data.cost):
		_reset_build_state()
		return
	
	# Place the building
	_place_building(_dragging_building_type, _drag_position)
	
	# Start cooldown to prevent auto-selection
	_placement_cooldown = PLACEMENT_COOLDOWN_DURATION
	
	build_completed.emit(_dragging_building_type, _drag_position)
	_reset_build_state()


## Cancel the current build
func cancel_placement() -> void:
	if current_state != BuildState.IDLE:
		build_cancelled.emit()
		_reset_build_state()


## Internal: Create placement preview
func _create_placement_preview(building_type: String) -> void:
	_destroy_placement_preview()
	
	var data: Resource = get_building_data(building_type)
	var scene_for_preview: PackedScene = null
	if data:
		# Preview should mirror the actual structure silhouette.
		if data.get("scene") is PackedScene:
			scene_for_preview = data.get("scene") as PackedScene
		elif data.get("preview_scene") is PackedScene:
			scene_for_preview = data.get("preview_scene") as PackedScene
	
	if scene_for_preview:
		_placement_preview = _create_visual_preview_from_scene(scene_for_preview)
	else:
		# Fallback placeholder when no scene data exists.
		_placement_preview = _create_default_preview()
	
	if _placement_preview:
		get_tree().root.add_child(_placement_preview)
		_placement_preview.global_position = _drag_position
		_collect_preview_mesh_instances()
		_preview_collision_radius = _resolve_preview_collision_radius(data)
		_set_preview_visual_state(_is_placement_valid)
		_setup_placement_overlap_detector()
	
	# Create range indicator circle(s)
	_create_range_indicator(building_type)


## Create a default preview mesh
func _create_default_preview() -> Node3D:
	var preview: Node3D = Node3D.new()
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = BoxMesh.new()
	mesh_instance.mesh.size = Vector3(2, 1, 2)
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0, 1, 0, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	
	preview.add_child(mesh_instance)
	return preview


## Build a preview from the real structure scene by copying meshes only.
func _create_visual_preview_from_scene(scene: PackedScene) -> Node3D:
	var preview_root: Node3D = Node3D.new()
	var source_root: Node3D = scene.instantiate() as Node3D
	if not source_root:
		return _create_default_preview()
	
	_configure_preview_mesh_filters(source_root)
	_copy_meshes_to_preview(source_root, preview_root, Transform3D.IDENTITY)
	source_root.free()
	_clear_preview_mesh_filters()
	
	# Fallback in case source scene has no mesh content at runtime.
	if preview_root.get_child_count() == 0:
		return _create_default_preview()
	return preview_root


func _copy_meshes_to_preview(source: Node, preview_root: Node3D, parent_transform: Transform3D) -> void:
	var current_transform: Transform3D = parent_transform
	if source is Node3D:
		current_transform = parent_transform * (source as Node3D).transform
		if source.name == "ConnectionPoint":
			var preview_connection_point: Marker3D = Marker3D.new()
			preview_connection_point.name = "ConnectionPoint"
			preview_connection_point.transform = current_transform
			preview_root.add_child(preview_connection_point)
	
	if source is MeshInstance3D:
		if not _should_copy_preview_mesh(source.name):
			return
		var source_mesh: MeshInstance3D = source as MeshInstance3D
		var preview_mesh: MeshInstance3D = MeshInstance3D.new()
		preview_mesh.mesh = source_mesh.mesh
		preview_mesh.transform = current_transform
		preview_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		preview_root.add_child(preview_mesh)
	
	for child in source.get_children():
		_copy_meshes_to_preview(child, preview_root, current_transform)


func _configure_preview_mesh_filters(source_root: Node3D) -> void:
	_clear_preview_mesh_filters()
	if source_root == null:
		return
	
	var include_data: Variant = source_root.get("placement_preview_include_mesh_names")
	var exclude_data: Variant = source_root.get("placement_preview_exclude_mesh_names")
	_register_preview_filter_entries(include_data, _preview_mesh_include_filter)
	_register_preview_filter_entries(exclude_data, _preview_mesh_exclude_filter)


func _register_preview_filter_entries(entries: Variant, target: Dictionary) -> void:
	if entries == null:
		return
	if entries is PackedStringArray:
		for entry in entries:
			var entry_name: String = String(entry)
			if not entry_name.is_empty():
				target[entry_name] = true
	elif entries is Array:
		for entry in entries:
			var entry_name: String = String(entry)
			if not entry_name.is_empty():
				target[entry_name] = true


func _should_copy_preview_mesh(mesh_name: String) -> bool:
	if _preview_mesh_include_filter.size() > 0 and not _preview_mesh_include_filter.has(mesh_name):
		return false
	if _preview_mesh_exclude_filter.has(mesh_name):
		return false
	return true


func _clear_preview_mesh_filters() -> void:
	_preview_mesh_include_filter.clear()
	_preview_mesh_exclude_filter.clear()


## Internal: Destroy placement preview
func _destroy_placement_preview() -> void:
	if _placement_preview:
		_placement_preview.queue_free()
		_placement_preview = null
	_placement_overlap_detector = null
	_placement_overlap_counts.clear()
	_preview_mesh_instances.clear()
	_preview_holo_materials.clear()
	_preview_collision_radius = DEFAULT_PLACEMENT_RADIUS
	
	if _connection_range_indicator:
		_connection_range_indicator.queue_free()
		_connection_range_indicator = null
	
	if _mining_range_indicator:
		_mining_range_indicator.queue_free()
		_mining_range_indicator = null
	
	if _action_range_indicator:
		_action_range_indicator.queue_free()
		_action_range_indicator = null
	
	for line in _connection_lines:
		if is_instance_valid(line):
			line.queue_free()
	_connection_lines.clear()
	
	_clear_asteroid_highlights()
	_clear_enemy_highlights()
	_preview_max_connections = 0
	_preview_action_range = 0.0
	_preview_show_asteroid_targeting = false
	_preview_show_enemy_targeting = false


## Create range indicator showing connection radius
func _create_range_indicator(building_type: String) -> void:
	# Connection range indicator (for all buildings) - uses PowerNode's constant
	_connection_range_indicator = _create_ring_mesh(PowerNodeClass.CONNECTION_RANGE, Color(0.2, 0.72, 1.0, 0.42))
	get_tree().root.add_child(_connection_range_indicator)
	_connection_range_indicator.global_position = Vector3(_drag_position.x, 0.2, _drag_position.z)
	
	var data: Resource = get_building_data(building_type)
	_preview_action_range = _get_building_action_range(building_type)
	_preview_show_asteroid_targeting = data != null and bool(data.get("show_asteroid_targeting"))
	_preview_show_enemy_targeting = data != null and bool(data.get("show_enemy_targeting"))
	
	# Show one action range ring depending on targeting role.
	if _preview_show_asteroid_targeting and _preview_action_range > 0.0:
		_mining_range_indicator = _create_ring_mesh(_preview_action_range, Color(0.16, 0.8, 1.0, 0.32))
		get_tree().root.add_child(_mining_range_indicator)
		_mining_range_indicator.global_position = Vector3(_drag_position.x, 0.15, _drag_position.z)
	elif _preview_show_enemy_targeting and _preview_action_range > 0.0:
		_action_range_indicator = _create_ring_mesh(_preview_action_range, Color(1.0, 0.35, 0.3, 0.35))
		get_tree().root.add_child(_action_range_indicator)
		_action_range_indicator.global_position = Vector3(_drag_position.x, 0.18, _drag_position.z)
	
	_preview_max_connections = _get_preview_max_connections(building_type)


func _get_preview_max_connections(building_type: String) -> int:
	var data: Resource = get_building_data(building_type)
	if not data or not data.scene:
		return 0
	
	var temp_structure: Node = data.scene.instantiate()
	if not temp_structure:
		return 0
	
	var max_connections: int = 0
	if temp_structure is Node3D:
		var power_node: Node3D = _find_power_node_in_structure(temp_structure as Node3D)
		if power_node:
			max_connections = int(power_node.get("max_connections"))
	
	temp_structure.queue_free()
	return maxi(max_connections, 0)


func _get_building_action_range(building_type: String) -> float:
	var data: Resource = get_building_data(building_type)
	if data == null:
		return 0.0
	var maybe_value: Variant = data.get("action_range")
	if maybe_value == null:
		return 0.0
	return maxf(float(maybe_value), 0.0)


func _ensure_connection_line_pool(count: int) -> void:
	while _connection_lines.size() < count:
		var line: MeshInstance3D = MeshInstance3D.new()
		var line_mat: StandardMaterial3D = StandardMaterial3D.new()
		line_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.7)
		line_mat.emission_enabled = true
		line_mat.emission = Color(0.2, 0.8, 0.2)
		line_mat.emission_energy_multiplier = 2.0
		line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		line_mat.disable_receive_shadows = true
		line.material_override = line_mat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.mesh = null
		line.visible = false
		_connection_lines.append(line)
		get_tree().root.add_child(line)


## Create a ring mesh for range indicators
func _create_ring_mesh(radius: float, color: Color) -> MeshInstance3D:
	var ring: MeshInstance3D = MeshInstance3D.new()
	
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius - 0.15
	torus.outer_radius = radius + 0.15
	torus.rings = RANGE_RING_SEGMENTS
	torus.ring_segments = RANGE_RING_SEGMENTS
	ring.mesh = torus
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r * 0.85, color.g * 0.85, color.b * 0.85)
	material.emission_energy_multiplier = 1.9
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	
	# Torus is already flat on XZ plane by default in Godot
	return ring


## Update connection preview line to nearest power node
func _update_connection_preview(world_position: Vector3) -> void:
	if _preview_max_connections <= 0:
		for line in _connection_lines:
			if is_instance_valid(line):
				line.visible = false
		return
	
	var candidates: Array[Dictionary] = _find_power_nodes_for_preview(world_position, _preview_max_connections)
	_ensure_connection_line_pool(candidates.size())
	
	# Hide all lines before redrawing active candidates.
	for line in _connection_lines:
		if is_instance_valid(line):
			line.visible = false
	
	for i in range(candidates.size()):
		var preview_line: MeshInstance3D = _connection_lines[i]
		if not is_instance_valid(preview_line):
			continue
		
		var candidate: Dictionary = candidates[i]
		var power_node: Node3D = candidate.node
		var parent_structure: Node3D = power_node.get_parent() as Node3D
		if not parent_structure:
			continue
		
		preview_line.visible = true
	
		var start_pos: Vector3 = _get_preview_connection_anchor(world_position)
		var end_pos: Vector3 = _get_structure_top_anchor(parent_structure, parent_structure.global_position)
		
		var distance: float = start_pos.distance_to(end_pos)
		
		if distance < 0.1:
			preview_line.visible = false
			continue
		
		# Check line of sight
		var blocked: bool = not _check_line_of_sight(world_position, parent_structure.global_position, parent_structure)
		
		var start_taper: float = _get_preview_taper_radius()
		var end_taper: float = _get_structure_taper_radius(parent_structure)
		_rebuild_preview_tapered_line(preview_line, start_pos, end_pos, start_taper, end_taper)
		
		# Update line color:
		# - red when LOS is blocked OR placement is invalid for any reason
		# - green only when both LOS and placement validity pass
		var mat: StandardMaterial3D = preview_line.material_override as StandardMaterial3D
		if mat:
			var line_invalid: bool = blocked or not _is_placement_valid
			if line_invalid:
				# Red = invalid
				mat.albedo_color = Color(1.0, 0.3, 0.2, 0.7)
				mat.emission = Color(0.8, 0.1, 0.1)
			else:
				# Green = valid
				mat.albedo_color = Color(0.3, 1.0, 0.3, 0.7)
				mat.emission = Color(0.2, 0.8, 0.2)
		else:
			preview_line.visible = false


func _rebuild_preview_tapered_line(
	line_container: MeshInstance3D,
	start_pos: Vector3,
	end_pos: Vector3,
	start_stop_radius: float,
	end_stop_radius: float
) -> void:
	if line_container == null:
		return
	
	for child in line_container.get_children():
		line_container.remove_child(child)
		child.queue_free()
	
	var material: StandardMaterial3D = line_container.material_override as StandardMaterial3D
	if material == null:
		return
	
	var delta: Vector3 = end_pos - start_pos
	var distance: float = delta.length()
	if distance < POWER_LINE_MIN_SEGMENT_LENGTH:
		delta = Vector3.FORWARD * POWER_LINE_MIN_SEGMENT_LENGTH
		distance = POWER_LINE_MIN_SEGMENT_LENGTH
		end_pos = start_pos + delta
	var direction: Vector3 = delta / distance
	
	var safe_start_stop_radius: float = maxf(start_stop_radius, 0.0)
	var safe_end_stop_radius: float = maxf(end_stop_radius, 0.0)
	var max_stop_total: float = maxf(distance - POWER_LINE_MIN_SEGMENT_LENGTH, 0.0)
	var stop_total: float = safe_start_stop_radius + safe_end_stop_radius
	if stop_total > max_stop_total and stop_total > 0.0:
		var stop_scale: float = max_stop_total / stop_total
		safe_start_stop_radius *= stop_scale
		safe_end_stop_radius *= stop_scale
	
	var stop_start: Vector3 = start_pos + direction * safe_start_stop_radius
	var stop_end: Vector3 = end_pos - direction * safe_end_stop_radius
	var visible_length: float = stop_start.distance_to(stop_end)
	if visible_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		return
	
	var max_taper_each_side: float = maxf((visible_length - POWER_LINE_MIN_SEGMENT_LENGTH) * 0.5, 0.0)
	var taper_length: float = minf(POWER_LINE_TAPER_LENGTH, max_taper_each_side)
	var start_taper_end: Vector3 = stop_start + direction * taper_length
	var end_taper_start: Vector3 = stop_end - direction * taper_length
	
	if taper_length >= POWER_LINE_MIN_SEGMENT_LENGTH:
		_add_preview_line_segment(
			line_container,
			stop_start,
			start_taper_end,
			0.0,
			POWER_LINE_RENDER_RADIUS,
			material
		)
		_add_preview_line_segment(
			line_container,
			end_taper_start,
			stop_end,
			POWER_LINE_RENDER_RADIUS,
			0.0,
			material
		)
	
	var center_length: float = start_taper_end.distance_to(end_taper_start)
	if center_length >= POWER_LINE_MIN_SEGMENT_LENGTH:
		_add_preview_line_segment(
			line_container,
			start_taper_end,
			end_taper_start,
			POWER_LINE_RENDER_RADIUS,
			POWER_LINE_RENDER_RADIUS,
			material
		)


func _add_preview_line_segment(
	line_container: MeshInstance3D,
	start_pos: Vector3,
	end_pos: Vector3,
	start_radius: float,
	end_radius: float,
	material: StandardMaterial3D
) -> void:
	var segment_length: float = start_pos.distance_to(end_pos)
	if segment_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		return
	
	var segment: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.bottom_radius = end_radius
	cylinder.top_radius = start_radius
	cylinder.height = segment_length
	segment.mesh = cylinder
	segment.material_override = material
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add to tree first — global_position and look_at require is_inside_tree()
	line_container.add_child(segment)
	
	var midpoint: Vector3 = (start_pos + end_pos) / 2.0
	segment.global_position = midpoint
	
	var direction: Vector3 = (end_pos - start_pos).normalized()
	if direction.length() > 0.01:
		var up: Vector3 = Vector3.UP
		if abs(direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		segment.look_at_from_position(midpoint, midpoint + direction, up)
		segment.rotate_object_local(Vector3(1, 0, 0), PI / 2)


func _get_preview_taper_radius() -> float:
	if _dragging_building_type.is_empty():
		return _get_placement_collision_radius()
	return _get_building_taper_radius(_dragging_building_type)


func _get_structure_taper_radius(structure_node: Node3D) -> float:
	if structure_node == null:
		return DEFAULT_PLACEMENT_RADIUS
	var building_type: String = str(structure_node.get("building_type"))
	if building_type.is_empty():
		return DEFAULT_PLACEMENT_RADIUS
	return _get_building_taper_radius(building_type)


func _get_building_taper_radius(building_type: String) -> float:
	if building_type.is_empty():
		return DEFAULT_PLACEMENT_RADIUS
	var data: Resource = get_building_data(building_type)
	if data == null:
		return DEFAULT_PLACEMENT_RADIUS
	var configured_radius: Variant = data.get("placement_sphere_radius")
	if configured_radius == null:
		return DEFAULT_PLACEMENT_RADIUS
	return maxf(float(configured_radius), POWER_LINE_MIN_SEGMENT_LENGTH)


## Check line of sight between two positions (for power line placement)
func _check_line_of_sight(from_pos: Vector3, to_pos: Vector3, exclude_structure: Node3D = null) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d().direct_space_state
	if not space_state:
		return true  # Can't check, assume clear
	
	# Raise check slightly above ground
	var start: Vector3 = from_pos + Vector3(0, 0.5, 0)
	var end: Vector3 = to_pos + Vector3(0, 0.5, 0)
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = 0xFFFFFFFF  # Check all layers
	query.collide_with_bodies = true
	query.collide_with_areas = true
	
	# Exclude the target structure
	var exclude_rids: Array[RID] = []
	if exclude_structure:
		var body: CollisionObject3D = _find_collision_body(exclude_structure)
		if body:
			exclude_rids.append(body.get_rid())
	query.exclude = exclude_rids
	
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()  # Clear if nothing hit


## Find collision body in a node hierarchy
func _find_collision_body(node: Node) -> CollisionObject3D:
	if node is CollisionObject3D:
		return node as CollisionObject3D
	for child in node.get_children():
		var body: CollisionObject3D = _find_collision_body(child)
		if body:
			return body
	return null


## Setup an overlap detector area on the placement preview.
func _setup_placement_overlap_detector() -> void:
	if not _placement_preview:
		return
	
	_placement_overlap_counts.clear()
	_placement_overlap_detector = Area3D.new()
	_placement_overlap_detector.name = "PlacementOverlapDetector"
	_placement_overlap_detector.monitoring = true
	_placement_overlap_detector.monitorable = false
	_placement_overlap_detector.collision_layer = 0
	# Match selectable layer used by entities (structures/asteroids/enemies/ships).
	_placement_overlap_detector.collision_mask = 1 << 1
	
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = _get_placement_collision_radius() + PLACEMENT_OCCUPANCY_MARGIN
	shape_node.shape = sphere
	shape_node.position = Vector3(0.0, 0.5, 0.0)
	
	_placement_overlap_detector.add_child(shape_node)
	_placement_preview.add_child(_placement_overlap_detector)
	
	_placement_overlap_detector.area_entered.connect(_on_placement_detector_area_entered)
	_placement_overlap_detector.area_exited.connect(_on_placement_detector_area_exited)
	_placement_overlap_detector.body_entered.connect(_on_placement_detector_body_entered)
	_placement_overlap_detector.body_exited.connect(_on_placement_detector_body_exited)
	
	_refresh_placement_overlaps()


## Check if placement overlaps blocked entities via overlap detector state.
func _is_position_occupied_for_build(_position: Vector3) -> bool:
	_refresh_placement_overlaps()
	return not _placement_overlap_counts.is_empty()


func _refresh_placement_overlaps() -> void:
	if not _placement_overlap_detector or not is_instance_valid(_placement_overlap_detector):
		_placement_overlap_counts.clear()
		return
	
	_placement_overlap_counts.clear()
	for area in _placement_overlap_detector.get_overlapping_areas():
		_register_placement_overlap(area)
	for body in _placement_overlap_detector.get_overlapping_bodies():
		_register_placement_overlap(body)


func _register_placement_overlap(collider: Object) -> void:
	if not _is_valid_placement_blocker(collider):
		return
	var collider_id: int = collider.get_instance_id()
	var current_count: int = int(_placement_overlap_counts.get(collider_id, 0))
	_placement_overlap_counts[collider_id] = current_count + 1


func _unregister_placement_overlap(collider: Object) -> void:
	if collider == null:
		return
	var collider_id: int = collider.get_instance_id()
	if not _placement_overlap_counts.has(collider_id):
		return
	var next_count: int = int(_placement_overlap_counts[collider_id]) - 1
	if next_count <= 0:
		_placement_overlap_counts.erase(collider_id)
	else:
		_placement_overlap_counts[collider_id] = next_count


func _is_valid_placement_blocker(collider: Object) -> bool:
	var collider_node: Node = collider as Node
	if not collider_node:
		return false
	if _placement_preview and (_placement_preview == collider_node or _placement_preview.is_ancestor_of(collider_node)):
		return false
	# Any selectable-layer collider outside the preview should block placement.
	return collider_node.is_inside_tree()


func _on_placement_detector_area_entered(area: Area3D) -> void:
	_register_placement_overlap(area)
	_update_placement_validity()


func _on_placement_detector_area_exited(area: Area3D) -> void:
	_unregister_placement_overlap(area)
	_update_placement_validity()


func _on_placement_detector_body_entered(body: Node3D) -> void:
	_register_placement_overlap(body)
	_update_placement_validity()


func _on_placement_detector_body_exited(body: Node3D) -> void:
	_unregister_placement_overlap(body)
	_update_placement_validity()


## Check if placement point intersects an existing power-line segment footprint.
func _is_position_blocked_by_power_line(position: Vector3) -> bool:
	if not PowerGraphManager or not PowerGraphManager.has_method("get_edges"):
		return false
	
	var edges: Dictionary = PowerGraphManager.get_edges()
	if edges.is_empty():
		return false
	
	var checked_edges: Dictionary = {}
	var point_2d: Vector2 = Vector2(position.x, position.z)
	var required_clearance: float = _get_placement_collision_radius() + POWER_LINE_RADIUS + POWER_LINE_CLEARANCE
	
	for node1 in edges.keys():
		if not is_instance_valid(node1):
			continue
		var neighbors: Variant = edges[node1]
		if not neighbors is Dictionary:
			continue
		for node2 in neighbors.keys():
			if not is_instance_valid(node2):
				continue
			var edge_key: String = _get_edge_key(node1 as Node3D, node2 as Node3D)
			if checked_edges.has(edge_key):
				continue
			checked_edges[edge_key] = true
			
			var endpoint_a: Vector3 = _get_power_node_world_position(node1 as Node3D)
			var endpoint_b: Vector3 = _get_power_node_world_position(node2 as Node3D)
			var distance: float = _distance_to_segment_2d(
				point_2d,
				Vector2(endpoint_a.x, endpoint_a.z),
				Vector2(endpoint_b.x, endpoint_b.z)
			)
			if distance <= required_clearance:
				return true
	
	return false


func _get_placement_collision_radius() -> float:
	return maxf(_preview_collision_radius, 0.2)


func _resolve_preview_collision_radius(data: Resource) -> float:
	if data:
		var configured_radius: Variant = data.get("placement_sphere_radius")
		if configured_radius != null:
			var radius_value: float = float(configured_radius)
			if radius_value > 0.0:
				return radius_value
	return _derive_preview_collision_radius()


func _derive_preview_collision_radius() -> float:
	if not _placement_preview:
		return DEFAULT_PLACEMENT_RADIUS
	
	var selectable_area: Area3D = _placement_preview.get_node_or_null("SelectableComponent") as Area3D
	if selectable_area:
		var shape_node: CollisionShape3D = selectable_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape:
			return _shape_radius_for_placement(shape_node.shape)
	
	# If preview has only visuals, derive radius from mesh AABB.
	var has_bounds: bool = false
	var min_x: float = 0.0
	var max_x: float = 0.0
	var min_z: float = 0.0
	var max_z: float = 0.0
	for mesh_instance in _preview_mesh_instances:
		if not is_instance_valid(mesh_instance) or not mesh_instance.mesh:
			continue
		var local_aabb: AABB = mesh_instance.mesh.get_aabb()
		var world_aabb: AABB = local_aabb * mesh_instance.transform
		if not has_bounds:
			min_x = world_aabb.position.x
			max_x = world_aabb.end.x
			min_z = world_aabb.position.z
			max_z = world_aabb.end.z
			has_bounds = true
		else:
			min_x = minf(min_x, world_aabb.position.x)
			max_x = maxf(max_x, world_aabb.end.x)
			min_z = minf(min_z, world_aabb.position.z)
			max_z = maxf(max_z, world_aabb.end.z)
	
	if has_bounds:
		var radius_x: float = maxf(absf(min_x), absf(max_x))
		var radius_z: float = maxf(absf(min_z), absf(max_z))
		return maxf(maxf(radius_x, radius_z), 0.2)
	
	return DEFAULT_PLACEMENT_RADIUS


func _shape_radius_for_placement(shape: Shape3D) -> float:
	if shape is SphereShape3D:
		return maxf((shape as SphereShape3D).radius, 0.2)
	if shape is BoxShape3D:
		var extents: Vector3 = (shape as BoxShape3D).size * 0.5
		return maxf(maxf(extents.x, extents.z), 0.2)
	if shape is CylinderShape3D:
		return maxf((shape as CylinderShape3D).radius, 0.2)
	return DEFAULT_PLACEMENT_RADIUS


func _collect_preview_mesh_instances() -> void:
	_preview_mesh_instances.clear()
	if not _placement_preview:
		return
	_collect_mesh_instances_recursive(_placement_preview)


func _collect_mesh_instances_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_preview_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances_recursive(child)


func _set_preview_visual_state(is_valid: bool) -> void:
	var tint_color: Color = PREVIEW_VALID_TINT if is_valid else PREVIEW_INVALID_TINT
	var emission_color: Color = PREVIEW_VALID_EMISSION if is_valid else PREVIEW_INVALID_EMISSION
	
	for mesh_instance in _preview_mesh_instances:
		if not is_instance_valid(mesh_instance):
			continue
		var material: ShaderMaterial = _get_or_create_preview_holo_material(mesh_instance)
		if not material:
			continue
		material.set_shader_parameter("tint_color", tint_color)
		material.set_shader_parameter("emission_color", emission_color)
		material.set_shader_parameter("is_valid", 1.0 if is_valid else 0.0)


func _get_or_create_preview_holo_material(mesh_instance: MeshInstance3D) -> ShaderMaterial:
	var mesh_id: int = mesh_instance.get_instance_id()
	if _preview_holo_materials.has(mesh_id):
		var cached: ShaderMaterial = _preview_holo_materials[mesh_id] as ShaderMaterial
		if cached:
			return cached
	
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	if _placement_holo_shader == null:
		_placement_holo_shader = load(PLACEMENT_HOLO_SHADER_PATH) as Shader
	if _placement_holo_shader == null:
		return null
	shader_material.shader = _placement_holo_shader
	shader_material.set_shader_parameter("tint_color", PREVIEW_VALID_TINT)
	shader_material.set_shader_parameter("emission_color", PREVIEW_VALID_EMISSION)
	shader_material.set_shader_parameter("is_valid", 1.0)
	mesh_instance.material_override = shader_material
	_preview_holo_materials[mesh_id] = shader_material
	return shader_material


func _get_power_node_world_position(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	var parent_node: Node3D = node.get_parent() as Node3D
	if parent_node and parent_node.is_inside_tree():
		return _get_structure_top_anchor(parent_node, parent_node.global_position)
	return node.global_position


func _get_preview_connection_anchor(world_position: Vector3) -> Vector3:
	if _placement_preview and is_instance_valid(_placement_preview):
		return _get_structure_top_anchor(_placement_preview, world_position)
	return Vector3(world_position.x, world_position.y + 0.8, world_position.z)


func _get_structure_top_anchor(structure_node: Node3D, fallback_position: Vector3) -> Vector3:
	if structure_node == null:
		return fallback_position
	
	var connection_point: Node3D = structure_node.get_node_or_null("ConnectionPoint") as Node3D
	if connection_point and connection_point.is_inside_tree():
		return connection_point.global_position
	
	var top_y: float = fallback_position.y + 0.8
	var found_mesh: bool = false
	for child in structure_node.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var local_aabb: AABB = mesh_instance.mesh.get_aabb()
			var world_aabb: AABB = local_aabb * mesh_instance.global_transform
			top_y = maxf(top_y, world_aabb.end.y)
			found_mesh = true
	
	if not found_mesh:
		top_y = maxf(top_y, fallback_position.y + 0.8)
	
	return Vector3(fallback_position.x, top_y, fallback_position.z)


func _get_edge_key(node1: Node3D, node2: Node3D) -> String:
	if node1 == null or node2 == null:
		return ""
	var id1: int = node1.get_instance_id()
	var id2: int = node2.get_instance_id()
	if id1 < id2:
		return "%d_%d" % [id1, id2]
	return "%d_%d" % [id2, id1]


func _distance_to_segment_2d(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment: Vector2 = b - a
	var segment_len_sq: float = segment.length_squared()
	if segment_len_sq <= 0.000001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(segment) / segment_len_sq, 0.0, 1.0)
	var closest: Vector2 = a + segment * t
	return point.distance_to(closest)


## Find nearest power node candidates within connection range.
## Returns nearest candidates up to max_preview_count.
func _find_power_nodes_for_preview(position: Vector3, max_preview_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if max_preview_count <= 0:
		return result
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return result
	
	var structures_parent: Node = main.get_node_or_null("Structures")
	if not structures_parent:
		return result
	
	# Collect all nodes with their distances
	var all_nodes: Array = []
	
	for structure in structures_parent.get_children():
		if not structure is Node3D:
			continue
		
		# Find power node component
		var power_node: Node3D = _find_power_node_in_structure(structure)
		if power_node:
			if power_node.has_method("is_valid_connection_target") and not power_node.is_valid_connection_target():
				# Allow previewing connections to structures still under construction.
				# They can receive links before they become valid relay/target nodes.
				if not _is_structure_under_construction(structure):
					continue
			
			# Check if this node can accept more connections
			if power_node.has_method("can_accept_more_connections"):
				if not power_node.can_accept_more_connections():
					continue
			
			# Keep existing leaf-to-leaf exclusion behavior in preview.
			var other_max_connections: int = int(power_node.get("max_connections"))
			if _preview_max_connections == 1 and other_max_connections == 1:
				continue
			
			var distance: float = position.distance_to(structure.global_position)
			# Use the PowerNode's constant for range check
			if distance <= PowerNodeClass.CONNECTION_RANGE:
				all_nodes.append({
					"node": power_node,
					"structure": structure,
					"distance": distance
				})
	
	# Sort by distance
	all_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.distance < b.distance
	)
	
	var preview_count: int = mini(max_preview_count, all_nodes.size())
	for i in range(preview_count):
		result.append(all_nodes[i])
	
	return result


## Find power node component in a structure
func _find_power_node_in_structure(structure: Node3D) -> Node3D:
	for child in structure.get_children():
		# Check if this is a PowerNode by its methods
		if child.has_method("can_accept_more_connections") and child.has_method("is_valid_connection_target"):
			return child as Node3D
	return null


func _is_structure_under_construction(structure: Node3D) -> bool:
	for child in structure.get_children():
		if child.has_method("get_progress") and child.get("is_built") == false:
			return true
	return false


## Update asteroid highlights for mining station placement
func _update_asteroid_highlights(world_position: Vector3) -> void:
	_clear_asteroid_highlights()
	if _preview_action_range <= 0.0:
		return
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return
	
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	if not asteroids_parent:
		return
	
	for child in asteroids_parent.get_children():
		# Check if it's an asteroid by checking for the mine_minerals method
		if child.has_method("mine_minerals") and child.has_method("get_mineral_percentage"):
			var asteroid_node: Node3D = child as Node3D
			if asteroid_node and not asteroid_node.get("is_depleted"):
				var distance: float = world_position.distance_to(asteroid_node.global_position)
				if distance <= _preview_action_range:
					var highlight: MeshInstance3D = _create_asteroid_highlight_at(asteroid_node)
					_asteroid_highlights.append(highlight)
					get_tree().root.add_child(highlight)


## Create highlight ring around asteroid at position
func _create_asteroid_highlight_at(asteroid_node: Node3D) -> MeshInstance3D:
	var highlight: MeshInstance3D = MeshInstance3D.new()
	
	# Get asteroid size if available, otherwise use default
	var asteroid_radius: float = 1.5
	if asteroid_node.has_method("get_mineral_percentage"):
		asteroid_radius = asteroid_node.get("asteroid_size") * 0.5 if asteroid_node.get("asteroid_size") else 1.5
	
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = asteroid_radius + 0.3
	torus.outer_radius = asteroid_radius + 0.6
	torus.rings = HIGHLIGHT_RING_SEGMENTS
	torus.ring_segments = HIGHLIGHT_RING_SEGMENTS
	highlight.mesh = torus
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.8, 1.0, 0.7)
	material.emission_enabled = true
	material.emission = Color(0.12, 0.68, 1.0)
	material.emission_energy_multiplier = 2.8
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	highlight.material_override = material
	
	# Store position for after adding to tree
	var pos: Vector3 = asteroid_node.global_position
	highlight.position = Vector3(pos.x, 0.3, pos.z)
	
	return highlight


## Clear all asteroid highlights
func _clear_asteroid_highlights() -> void:
	for highlight in _asteroid_highlights:
		if is_instance_valid(highlight):
			highlight.queue_free()
	_asteroid_highlights.clear()


## Update enemy highlights for laser turret placement
func _update_enemy_highlights(world_position: Vector3) -> void:
	_clear_enemy_highlights()
	if _preview_action_range <= 0.0:
		return
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return
	
	var enemies_parent: Node = main.get_node_or_null("Enemies")
	if not enemies_parent:
		return
	
	for child in enemies_parent.get_children():
		if not (child is Node3D):
			continue
		if child.get("is_destroyed") == true:
			continue
		
		var enemy_node: Node3D = child as Node3D
		var distance: float = world_position.distance_to(enemy_node.global_position)
		if distance <= _preview_action_range:
			var highlight: MeshInstance3D = _create_enemy_highlight_at(enemy_node)
			_enemy_highlights.append(highlight)
			get_tree().root.add_child(highlight)


func _create_enemy_highlight_at(enemy_node: Node3D) -> MeshInstance3D:
	var highlight: MeshInstance3D = MeshInstance3D.new()
	var ring_radius: float = 1.0
	
	var selectable_area: Area3D = enemy_node.get_node_or_null("SelectableComponent") as Area3D
	if selectable_area:
		var shape_node: CollisionShape3D = selectable_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape:
			if shape_node.shape is SphereShape3D:
				ring_radius = maxf((shape_node.shape as SphereShape3D).radius + 0.3, 0.6)
	
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = ring_radius
	torus.outer_radius = ring_radius + 0.25
	torus.rings = HIGHLIGHT_RING_SEGMENTS
	torus.ring_segments = HIGHLIGHT_RING_SEGMENTS
	highlight.mesh = torus
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.35, 0.3, 0.7)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.2, 0.16)
	material.emission_energy_multiplier = 2.2
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	highlight.material_override = material
	
	var pos: Vector3 = enemy_node.global_position
	highlight.position = Vector3(pos.x, 0.35, pos.z)
	return highlight


func _clear_enemy_highlights() -> void:
	for highlight in _enemy_highlights:
		if is_instance_valid(highlight):
			highlight.queue_free()
	_enemy_highlights.clear()


## Internal: Update placement validity
func _update_placement_validity() -> void:
	var was_valid: bool = _is_placement_valid
	
	# Check if position is valid
	_is_placement_valid = _check_placement_validity(_drag_position)
	
	# Update preview color
	_set_preview_visual_state(_is_placement_valid)
	
	if was_valid != _is_placement_valid:
		placement_valid_changed.emit(_is_placement_valid)


## Internal: Check if placement position is valid
func _check_placement_validity(position: Vector3) -> bool:
	# Check if we have enough resources
	if not can_place_building(_dragging_building_type):
		return false
	
	# Check if position is within bounds (basic check)
	if position.y < -10 or position.y > 100:
		return false
	
	# Physics occupancy check: cannot overlap existing structures or asteroids.
	if _is_position_occupied_for_build(position):
		return false
	
	# Segment proximity check: cannot place on top of any power line path.
	if _is_position_blocked_by_power_line(position):
		return false
	
	# Placement validity already includes occupancy and power-line collision checks.
	
	return true


## Internal: Place the actual building
func _place_building(building_type: String, position: Vector3) -> void:
	var data: Resource = get_building_data(building_type)
	if not data or not data.scene:
		push_error("No scene found for building type: " + building_type)
		return
	
	var building: Node3D = data.scene.instantiate() as Node3D
	if building:
		# Add to tree first, then set global_position
		var main: Node = get_tree().root.get_node_or_null("Main")
		if main:
			var structures_parent: Node = main.get_node_or_null("Structures")
			if structures_parent:
				structures_parent.add_child(building)
			else:
				main.add_child(building)
		else:
			get_tree().root.add_child(building)
		
		# Now safe to set global_position
		building.global_position = position


## Internal: Reset build state
func _reset_build_state() -> void:
	print("[DEBUG] Resetting build state from ", current_state, " to IDLE")
	current_state = BuildState.IDLE
	_dragging_building_type = ""
	_drag_position = Vector3.ZERO
	_is_placement_valid = false
	_destroy_placement_preview()


## Check if currently in build mode
func is_building() -> bool:
	return current_state != BuildState.IDLE

## Check if selection (clicking) should be blocked
func is_selection_blocked() -> bool:
	return current_state != BuildState.IDLE or _placement_cooldown > 0

## Check if hover should be blocked (only while actually building)
func is_hover_blocked() -> bool:
	return current_state != BuildState.IDLE


func _play_sfx(sfx_id: String, volume_db: float = -6.0) -> void:
	var sfx_manager: Node = get_node_or_null("/root/SfxManager")
	if sfx_manager and sfx_manager.has_method("play_sfx"):
		sfx_manager.call("play_sfx", sfx_id, volume_db)


func _is_gameplay_active() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	var root: Node = tree.root
	if root == null:
		return false
	return root.get_node_or_null("Main") != null
