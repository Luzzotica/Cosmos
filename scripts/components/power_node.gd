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
## When true, PowerGraphManager.add_node registers this node without auto-linking to nodes in range.
## Used for construction-only PowerNodes; edges are added via sync_construction_shadow_edges from the main PowerNode.
@export var skip_auto_connect_on_register: bool = false
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
		if not skip_auto_connect_on_register:
			_disable_main_while_structure_under_construction()
		if skip_auto_connect_on_register:
			PowerGraphManager.add_node_without_auto_connect(self)
		else:
			PowerGraphManager.add_node(self)


## Main PowerNode stays disabled until construction completes; shadow edges carry build power.
func _disable_main_while_structure_under_construction() -> void:
	var p: Node = get_parent()
	if p == null:
		return
	for child in p.get_children():
		if child is ConstructionComponent:
			var cc: ConstructionComponent = child as ConstructionComponent
			if not cc.is_built:
				is_enabled = false
			return


func _unregister_from_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.remove_node(self)


func _notify_power_graph_enabled_changed() -> void:
	if PowerGraphManager and PowerGraphManager.has_method("on_node_enabled_changed"):
		PowerGraphManager.on_node_enabled_changed(self)


## Get the type of this node (SOURCE, NODE, or LEAF)
## Relay/source topology is determined by children. Power flow while unbuilt is gated by [member is_enabled]
## (disabled main does not carry power over edges); do not force LEAF just because ConstructionComponent exists.
func get_node_type() -> NodeType:
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
## Sources and relays are always valid while they have free slots. Leaf consumers are only valid when
## isolated (no links yet) so a relay placed after them can connect; once linked, new structures skip
## them so the grid extends through relays/sources instead (see PowerGraphManager.add_node).
## Construction-only shadow nodes never accept auto-links (edges come from sync_construction_shadow_edges).
func is_valid_connection_target() -> bool:
	if skip_auto_connect_on_register:
		return false
	var node_type: NodeType = get_node_type()
	if node_type == NodeType.LEAF:
		return connected_nodes.is_empty() and can_accept_more_connections()
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
	query.collision_mask = 1 << 19  # PowerLineBlocking layer only
	query.collide_with_bodies = true
	query.collide_with_areas = true
	
	# Exclude all collision bodies from the two structures we're connecting
	var exclude_rids: Array[RID] = []
	for exclude_node in [exclude1, exclude2]:
		if exclude_node:
			for body in _find_all_collision_bodies(exclude_node):
				exclude_rids.append(body.get_rid())
	query.exclude = exclude_rids
	
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()  # Clear if nothing hit


## Find first collision body in a node hierarchy
static func _find_collision_body(node: Node) -> CollisionObject3D:
	var bodies: Array = _find_all_collision_bodies(node)
	return bodies[0] if bodies.size() > 0 else null


## Find all collision bodies in a node hierarchy
static func _find_all_collision_bodies(node: Node) -> Array[CollisionObject3D]:
	var result: Array[CollisionObject3D] = []
	if node is CollisionObject3D:
		result.append(node as CollisionObject3D)
	for child in node.get_children():
		result.append_array(_find_all_collision_bodies(child))
	return result


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
