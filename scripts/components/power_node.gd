@tool
extends Node3D
class_name PowerNode
## Component for structures that route power through the grid

signal connections_changed
signal enabled_changed(is_enabled: bool)

## Node types for power grid role identification
enum NodeType {
	SOURCE,  # Has PowerSource child - generates/stores power (solar panels)
	NODE,    # No PowerSource or PowerUser - pure relay (power nodes)
	LEAF     # Has PowerUser child but no PowerSource - consumes power (mining stations, turrets)
}

## Connection range - this single value controls both visual indicator AND actual connections
const CONNECTION_RANGE: float = 15.0

@export var max_connection_distance: float = CONNECTION_RANGE
@export var max_connections: int = 4
@export var is_enabled: bool = true:
	set(value):
		var old_value: bool = is_enabled
		is_enabled = value
		enabled_changed.emit(is_enabled)
		# Notify power graph to recalculate subgraphs when enabled state changes
		if old_value != value and not Engine.is_editor_hint():
			_notify_power_graph_enabled_changed()

var connected_nodes: Array[PowerNode] = []
var is_powered: bool = false
var _cached_node_type: NodeType = NodeType.NODE
var _type_cached: bool = false


func _enter_tree() -> void:
	# Register with power graph when added to scene
	if not Engine.is_editor_hint():
		call_deferred("_register_with_power_graph")


func _exit_tree() -> void:
	# Unregister from power graph when removed
	if not Engine.is_editor_hint():
		_unregister_from_power_graph()


func _register_with_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.add_node(self)


func _unregister_from_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.remove_node(self)


func _notify_power_graph_enabled_changed() -> void:
	if PowerGraphManager and PowerGraphManager.has_method("on_node_enabled_changed"):
		PowerGraphManager.on_node_enabled_changed(self)


## Get the type of this node (SOURCE, NODE, or LEAF)
## Note: Unbuilt structures always act as LEAF (can't relay power)
func get_node_type() -> NodeType:
	# Check if parent structure is under construction - if so, treat as LEAF
	var parent_structure: Node3D = get_parent() as Node3D
	if parent_structure:
		# Check for ConstructionComponent sibling
		for sibling in parent_structure.get_children():
			if sibling.has_method("get_progress") and sibling.get("is_built") == false:
				return NodeType.LEAF  # Under construction = can't relay power
	
	if _type_cached:
		return _cached_node_type
	
	var has_source: bool = false
	var has_user: bool = false
	
	for child in get_children():
		# Check for PowerSource by its methods
		if child.has_method("store_power") and child.has_method("draw_power"):
			has_source = true
		# Check for PowerUser by its methods - but skip construction power users
		elif child.has_method("consume_power") and child.has_method("draw_power_from_graph"):
			# Check if this is a construction power user (temporary)
			if not child.get("is_construction_user"):
				has_user = true
	
	if has_source:
		_cached_node_type = NodeType.SOURCE
	elif has_user:
		_cached_node_type = NodeType.LEAF
	else:
		_cached_node_type = NodeType.NODE
	
	_type_cached = true
	return _cached_node_type


## Invalidate the cached node type (call when structure finishes building)
func invalidate_type_cache() -> void:
	_type_cached = false


## Check if this node is a valid connection target for new buildings
## Sources and Nodes can accept connections, Leaves cannot
func is_valid_connection_target() -> bool:
	var node_type: NodeType = get_node_type()
	# Leaves (consumers like mining stations) should not be connected TO
	# Only sources and relay nodes can be targets
	if node_type == NodeType.LEAF:
		return false
	return can_accept_more_connections()


## Check if this node can accept more connections
func can_accept_more_connections() -> bool:
	return connected_nodes.size() < max_connections


## Check if this node can connect to another node
func can_connect_to(other: PowerNode) -> bool:
	if other == self:
		return false
	if other.get_parent() == get_parent():
		return false  # Same parent structure
	
	var my_structure: Node3D = get_parent() as Node3D
	var other_structure: Node3D = other.get_parent() as Node3D
	if not my_structure or not other_structure:
		return false
	
	# Check distance
	var distance: float = my_structure.global_position.distance_to(other_structure.global_position)
	if distance > max_connection_distance:
		return false
	
	# Check line of sight - power lines can't go through objects
	if not has_line_of_sight(my_structure.global_position, other_structure.global_position, my_structure, other_structure):
		return false
	
	return true


## Check if there's a clear line of sight between two positions
## Excludes the two endpoint structures from the raycast
static func has_line_of_sight(from_pos: Vector3, to_pos: Vector3, exclude1: Node3D = null, exclude2: Node3D = null) -> bool:
	var space_state: PhysicsDirectSpaceState3D = exclude1.get_world_3d().direct_space_state if exclude1 else null
	if not space_state:
		return true  # Can't check, assume clear
	
	# Raise the check slightly above ground
	var start: Vector3 = from_pos + Vector3(0, 0.5, 0)
	var end: Vector3 = to_pos + Vector3(0, 0.5, 0)
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = 0xFFFFFFFF  # Check all layers
	query.collide_with_bodies = true
	query.collide_with_areas = true
	
	# Exclude the two structures we're connecting
	var exclude_rids: Array[RID] = []
	if exclude1:
		var body1: CollisionObject3D = _find_collision_body(exclude1)
		if body1:
			exclude_rids.append(body1.get_rid())
	if exclude2:
		var body2: CollisionObject3D = _find_collision_body(exclude2)
		if body2:
			exclude_rids.append(body2.get_rid())
	query.exclude = exclude_rids
	
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()  # Clear if nothing hit


## Find collision body in a node hierarchy
static func _find_collision_body(node: Node) -> CollisionObject3D:
	if node is CollisionObject3D:
		return node as CollisionObject3D
	for child in node.get_children():
		var body: CollisionObject3D = _find_collision_body(child)
		if body:
			return body
	return null


## Connect another node to this node
func connect_node(node: PowerNode) -> void:
	if not can_accept_more_connections():
		return
	
	if node not in connected_nodes:
		connected_nodes.append(node)
		connections_changed.emit()


## Disconnect a node from this node
func disconnect_node(node: PowerNode) -> void:
	var idx: int = connected_nodes.find(node)
	if idx >= 0:
		connected_nodes.remove_at(idx)
		connections_changed.emit()


## Disconnect all nodes
func disconnect_all_nodes() -> void:
	connected_nodes.clear()
	connections_changed.emit()


## Set the powered state
func set_powered(powered: bool) -> void:
	is_powered = powered


## Set the enabled state
func set_enabled(enabled: bool) -> void:
	is_enabled = enabled


## Get connection count text for UI
func get_connection_status() -> String:
	return "%d/%d" % [connected_nodes.size(), max_connections]
