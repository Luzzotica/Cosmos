extends Node
## BuildManager Singleton - Handles building placement and construction

# Preload PowerNode to ensure type is available
const PowerNodeClass: GDScript = preload("res://scripts/components/power_node.gd")

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

# Range indicators
var _connection_range_indicator: MeshInstance3D = null
var _mining_range_indicator: MeshInstance3D = null
var _connection_line: MeshInstance3D = null
var _closest_power_node: Node3D = null  # PowerNode component
var _connection_blocked: bool = false  # True if line of sight is blocked
var _asteroid_highlights: Array[MeshInstance3D] = []

const MINING_RANGE: float = 12.5  # Should match MiningStation default

# Building data cache
var _building_data: Dictionary = {}

# Cooldown after placing to prevent auto-selection
var _placement_cooldown: float = 0.0
const PLACEMENT_COOLDOWN_DURATION: float = 0.2


func _ready() -> void:
	_load_building_data()
	set_process_input(true)
	set_process(true)


func _process(delta: float) -> void:
	if _placement_cooldown > 0:
		_placement_cooldown -= delta


var _last_mouse_world_position: Vector3 = Vector3.ZERO
var _is_consuming_release: bool = false


func _input(event: InputEvent) -> void:
	# Always track mouse position for hotkey placement
	if event is InputEventMouseMotion:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera and camera.has_method("get_mouse_world_position"):
			_last_mouse_world_position = camera.get_mouse_world_position()
			# Update preview if in build mode
			if current_state != BuildState.IDLE:
				update_placement_preview(_last_mouse_world_position)
		return
	
	# Debug: Log mouse clicks
	if event is InputEventMouseButton:
		var me: InputEventMouseButton = event as InputEventMouseButton
		if me.button_index == MOUSE_BUTTON_LEFT:
			print("[DEBUG] BuildManager saw LEFT click, pressed=", me.pressed, " state=", current_state, " consuming_release=", _is_consuming_release)
			if not me.pressed and _is_consuming_release:
				print("[DEBUG] BuildManager CONSUMING release event")
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
				print("[DEBUG] BuildManager confirming placement")
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
	
	# Update connection line to nearest power node
	_update_connection_preview(world_position)
	
	# Update asteroid highlights for mining stations
	if _dragging_building_type == "mining_station":
		_update_asteroid_highlights(world_position)


## Confirm building placement
func confirm_placement() -> void:
	if current_state == BuildState.IDLE or _dragging_building_type.is_empty():
		return
	
	if not _is_placement_valid:
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
	if not data or not data.preview_scene:
		# Create a simple placeholder preview
		_placement_preview = _create_default_preview()
	else:
		_placement_preview = data.preview_scene.instantiate()
	
	if _placement_preview:
		get_tree().root.add_child(_placement_preview)
		_placement_preview.global_position = _drag_position
	
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


## Internal: Destroy placement preview
func _destroy_placement_preview() -> void:
	if _placement_preview:
		_placement_preview.queue_free()
		_placement_preview = null
	
	if _connection_range_indicator:
		_connection_range_indicator.queue_free()
		_connection_range_indicator = null
	
	if _mining_range_indicator:
		_mining_range_indicator.queue_free()
		_mining_range_indicator = null
	
	if _connection_line:
		_connection_line.queue_free()
		_connection_line = null
	
	_clear_asteroid_highlights()
	_closest_power_node = null


## Create range indicator showing connection radius
func _create_range_indicator(building_type: String) -> void:
	# Connection range indicator (for all buildings) - uses PowerNode's constant
	_connection_range_indicator = _create_ring_mesh(PowerNodeClass.CONNECTION_RANGE, Color(0.3, 0.7, 1.0, 0.4))
	get_tree().root.add_child(_connection_range_indicator)
	_connection_range_indicator.global_position = Vector3(_drag_position.x, 0.2, _drag_position.z)
	
	# Mining range indicator (only for mining stations)
	if building_type == "mining_station":
		_mining_range_indicator = _create_ring_mesh(MINING_RANGE, Color(1.0, 0.8, 0.2, 0.3))
		get_tree().root.add_child(_mining_range_indicator)
		_mining_range_indicator.global_position = Vector3(_drag_position.x, 0.15, _drag_position.z)
	
	# Connection line - we'll create the mesh dynamically in _update_connection_preview
	_connection_line = MeshInstance3D.new()
	
	var line_mat: StandardMaterial3D = StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.7)
	line_mat.emission_enabled = true
	line_mat.emission = Color(0.2, 0.8, 0.2)
	line_mat.emission_energy_multiplier = 2.0
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_connection_line.material_override = line_mat
	_connection_line.visible = false
	
	get_tree().root.add_child(_connection_line)


## Create a ring mesh for range indicators
func _create_ring_mesh(radius: float, color: Color) -> MeshInstance3D:
	var ring: MeshInstance3D = MeshInstance3D.new()
	
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius - 0.2
	torus.outer_radius = radius + 0.2
	torus.rings = 48
	torus.ring_segments = 48
	ring.mesh = torus
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r * 0.7, color.g * 0.7, color.b * 0.7)
	material.emission_energy_multiplier = 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	
	# Torus is already flat on XZ plane by default in Godot
	return ring


## Update connection preview line to nearest power node
func _update_connection_preview(world_position: Vector3) -> void:
	if not _connection_line:
		return
	
	# Find nearest valid power node in range (sources and relays only, not leaves)
	_closest_power_node = _find_nearest_power_node(world_position)
	_connection_blocked = false
	
	if _closest_power_node:
		_connection_line.visible = true
		
		var start_pos: Vector3 = world_position
		start_pos.y = 0.3
		var parent_structure: Node3D = _closest_power_node.get_parent() as Node3D
		if not parent_structure:
			_connection_line.visible = false
			return
		var end_pos: Vector3 = parent_structure.global_position
		end_pos.y = 0.3
		
		var distance: float = start_pos.distance_to(end_pos)
		
		if distance < 0.1:
			_connection_line.visible = false
			return
		
		# Check line of sight
		_connection_blocked = not _check_line_of_sight(world_position, parent_structure.global_position, parent_structure)
		
		# Create cylinder mesh with the exact distance as height (same as power_graph_manager)
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = 0.15
		cylinder.bottom_radius = 0.15
		cylinder.height = distance
		_connection_line.mesh = cylinder
		
		# Position at midpoint
		var midpoint: Vector3 = (start_pos + end_pos) / 2.0
		_connection_line.global_position = midpoint
		
		# Rotate to point from start to end (same logic as power_graph_manager)
		var direction: Vector3 = (end_pos - start_pos).normalized()
		if direction.length() > 0.01:
			var up: Vector3 = Vector3.UP
			if abs(direction.dot(up)) > 0.99:
				up = Vector3.RIGHT
			_connection_line.look_at_from_position(midpoint, midpoint + direction, up)
			_connection_line.rotate_object_local(Vector3(1, 0, 0), PI / 2)
		
		# Update line color based on blocked status
		var mat: StandardMaterial3D = _connection_line.material_override as StandardMaterial3D
		if mat:
			if _connection_blocked:
				# Red = blocked
				mat.albedo_color = Color(1.0, 0.3, 0.2, 0.7)
				mat.emission = Color(0.8, 0.1, 0.1)
			else:
				# Green = valid
				mat.albedo_color = Color(0.3, 1.0, 0.3, 0.7)
				mat.emission = Color(0.2, 0.8, 0.2)
	else:
		_connection_line.visible = false


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


## Find the nearest power node within connection range
## Returns ANY node in range - the preview line color will indicate if it's a good target
func _find_nearest_power_node(position: Vector3) -> Node3D:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return null
	
	var structures_parent: Node = main.get_node_or_null("Structures")
	if not structures_parent:
		return null
	
	# Collect all nodes with their distances
	var all_nodes: Array = []
	
	for structure in structures_parent.get_children():
		if not structure is Node3D:
			continue
		
		# Find power node component
		var power_node: Node3D = _find_power_node_in_structure(structure)
		if power_node:
			# Check if this node can accept more connections
			if power_node.has_method("can_accept_more_connections"):
				if not power_node.can_accept_more_connections():
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
	
	# Return the closest node
	if all_nodes.size() > 0:
		return all_nodes[0].node
	
	return null


## Find power node component in a structure
func _find_power_node_in_structure(structure: Node3D) -> Node3D:
	for child in structure.get_children():
		# Check if this is a PowerNode by its methods
		if child.has_method("can_accept_more_connections") and child.has_method("is_valid_connection_target"):
			return child as Node3D
	return null


## Update asteroid highlights for mining station placement
func _update_asteroid_highlights(world_position: Vector3) -> void:
	_clear_asteroid_highlights()
	
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
				if distance <= MINING_RANGE:
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
	torus.rings = 24
	torus.ring_segments = 24
	highlight.mesh = torus
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.3, 0.7)  # Yellow highlight
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.1)
	material.emission_energy_multiplier = 2.5
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


## Internal: Update placement validity
func _update_placement_validity() -> void:
	var was_valid: bool = _is_placement_valid
	
	# Check if position is valid
	_is_placement_valid = _check_placement_validity(_drag_position)
	
	# Update preview color
	if _placement_preview:
		var mesh_instance: MeshInstance3D = _placement_preview.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_instance and mesh_instance.material_override:
			var mat: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(0, 1, 0, 0.5) if _is_placement_valid else Color(1, 0, 0, 0.5)
	
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
	
	# Note: We allow placement even without power connection
	# Buildings just won't start construction until connected to power
	# The connection line will show red if blocked, but placement is still allowed
	
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
