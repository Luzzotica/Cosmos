extends Node
## PowerGraphManager Singleton - Manages the power grid and energy distribution
## 
## This is the core system that handles power distribution between generators,
## sources, and users through a network of connected nodes.

class_name PowerGraphManagerClass

signal subgraphs_updated
signal node_added(node: Node3D)
signal node_removed(node: Node3D)

# Core component references - these are Node3D instances with specific scripts attached
var _nodes: Dictionary = {}  # PowerNode -> Set of connected PowerNodes (as Dictionary for set behavior)
var _users: Dictionary = {}  # PowerUser nodes
var _sources: Dictionary = {}  # PowerSource nodes
var _generators: Dictionary = {}  # PowerGenerator nodes

# Graph structure
var _graph: Dictionary = {}  # PowerNode -> Dictionary of connected PowerNodes
var _edges: Dictionary = {}  # Stores edge data between node pairs
var _subgraphs: Array = []  # Array of PowerSubgraph

# Line visuals parent
var _lines_parent: Node3D = null

# Power flow animation - edges being animated
var _pulsing_edges: Dictionary = {}  # edge_key -> remaining_time
const PULSE_DURATION: float = 0.3  # How long the pulse lasts
const RECONNECT_SCAN_INTERVAL: float = 0.5
const LEAF_RECONNECT_COOLDOWN: float = 1.25
const POWER_LINE_RENDER_RADIUS: float = 0.15
const POWER_LINE_MIN_SEGMENT_LENGTH: float = 0.02
const POWER_LINE_TAPER_LENGTH: float = 0.8
const DEFAULT_TAPER_RADIUS: float = 1.2

var _known_disrupted_edges: Dictionary = {}  # edge_key -> true
var _reconnect_queue: Dictionary = {}  # PowerNode -> true
var _leaf_reconnect_cooldowns: Dictionary = {}  # instance_id -> remaining seconds
var _reconnect_scan_timer: float = 0.0


func _ready() -> void:
	_lines_parent = Node3D.new()
	_lines_parent.name = "PowerLines"
	add_child(_lines_parent)
	_ensure_lines_parent_in_scene()
	set_process(true)


func _ensure_lines_parent_in_scene() -> void:
	# Recreate if freed (e.g. after scene change/restart)
	if _lines_parent == null or not is_instance_valid(_lines_parent):
		_lines_parent = Node3D.new()
		_lines_parent.name = "PowerLines"
		add_child(_lines_parent)
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main and main is Node3D and _lines_parent:
		if _lines_parent.get_parent() != main:
			if _lines_parent.get_parent():
				_lines_parent.get_parent().remove_child(_lines_parent)
			main.add_child(_lines_parent)
		return
	if _lines_parent and not _lines_parent.get_parent():
		add_child(_lines_parent)


func _process(delta: float) -> void:
	_update_power_flows(delta)
	_update_reconnect_state(delta)


## Get total power capacity across all sources (only from built structures)
func get_power_capacity() -> float:
	var total: float = 0.0
	for source in _sources.keys():
		if is_instance_valid(source) and _is_source_from_built_structure(source):
			total += source.get("max_storage")
	return total


## Get current power stored across all sources (only from built structures)
func get_power_current() -> float:
	var total: float = 0.0
	for source in _sources.keys():
		if is_instance_valid(source) and _is_source_from_built_structure(source):
			total += source.get("current_storage")
	return total


## Get total power generation across all generators (only from built structures)
func get_power_generation() -> float:
	var total: float = 0.0
	for generator in _generators.keys():
		if is_instance_valid(generator) and _is_generator_from_built_structure(generator):
			total += generator.get("current_output")
	return total


## Get total power consumption across all users
func get_power_consumption() -> float:
	var total: float = 0.0
	for user in _users.keys():
		if is_instance_valid(user):
			total += user.get("power_consumption")
	return total


## Get the graph structure (for testing/debugging)
func get_graph() -> Dictionary:
	return _graph


## Add a power node to the grid
func add_node(node: Node3D) -> void:
	if _nodes.has(node):
		return
	
	# Initialize graph entry for new node
	_graph[node] = {}
	_edges[node] = {}
	
	# Get the structure position (parent of power node)
	var struct: Node3D = node.get_parent() as Node3D
	var node_position: Vector3 = struct.global_position if struct else node.global_position
	
	# Find other nodes in range to connect to (already sorted by distance)
	var nodes_in_range: Array = find_power_nodes_in_range(
		node_position,
		node.get("max_connection_distance"),
		node.get("max_connections")
	)
	
	# Sort by: powered nodes first, then by distance (which is already the order from find_power_nodes_in_range)
	# This is a stable sort, so distance order is preserved within each group
	nodes_in_range.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var a_powered: bool = _is_node_powered(a)
		var b_powered: bool = _is_node_powered(b)
		if a_powered and not b_powered:
			return true
		if not a_powered and b_powered:
			return false
		# Both same power status - keep distance order (already sorted)
		return false
	)
	
	# Connect new node to existing nodes if within range
	# Note: We connect to ANY node in range - power flow is controlled by isEnabled, not connections
	for other_node in nodes_in_range:
		if not node.can_accept_more_connections():
			break
		
		if node != other_node and node.can_connect_to(other_node) and other_node.can_connect_to(node):
			# Add bidirectional connection
			_graph[node][other_node] = true
			_graph[other_node][node] = true
			
			# Create edge visualization
			_create_edge(node, other_node)
			
			# Update node components
			node.connect_node(other_node)
			other_node.connect_node(node)
	
	# Add to nodes set and rebuild subgraphs
	_nodes[node] = true
	_identify_subgraphs()
	node_added.emit(node)


## Remove a power node from the grid
func remove_node(node: Node3D) -> void:
	if not _nodes.has(node):
		return
	
	_nodes.erase(node)
	_reconnect_queue.erase(node)
	_leaf_reconnect_cooldowns.erase(node.get_instance_id())
	
	# Get all nodes that were connected to this node
	var connected_nodes: Array = _graph.get(node, {}).keys()
	
	# Remove this node from all its connections
	for connected_node in connected_nodes:
		if _graph.has(connected_node):
			_graph[connected_node].erase(node)
		
		# Remove edge
		_remove_edge(node, connected_node)
		
		if is_instance_valid(connected_node):
			connected_node.disconnect_node(node)
	
	# Remove the node's entry from the graphs
	_graph.erase(node)
	_edges.erase(node)
	
	# Try to reconnect affected leaf endpoints immediately.
	_attempt_leaf_reconnect(connected_nodes, true)
	
	# Rebuild subgraphs
	_identify_subgraphs()
	node_removed.emit(node)


## Enable a node in the grid
func enable_node(node: Node3D) -> void:
	if _nodes.has(node):
		node.set_enabled(true)
		_identify_subgraphs()


## Disable a node in the grid
func disable_node(node: Node3D) -> void:
	if _nodes.has(node):
		node.set_enabled(false)
		_identify_subgraphs()


## Called when a node's enabled state changes - recalculate subgraphs
func on_node_enabled_changed(node: Node3D) -> void:
	if _nodes.has(node):
		_identify_subgraphs()


## Check if edge between two nodes is enabled
func is_edge_enabled(node1: Node3D, node2: Node3D) -> bool:
	if not _edges.has(node1) or not _edges[node1].has(node2):
		return false
	var edge_data: Variant = _edges[node1][node2]
	return edge_data != null and _can_edge_handle_power(node1, node2)


func _can_edge_handle_power(node1: Node3D, node2: Node3D) -> bool:
	return node1.get("is_enabled") and node2.get("is_enabled") and _has_edge_line_of_sight(node1, node2)


func _has_edge_line_of_sight(node1: Node3D, node2: Node3D) -> bool:
	var struct1: Node3D = node1.get_parent() as Node3D
	var struct2: Node3D = node2.get_parent() as Node3D
	if not struct1 or not struct2:
		return true
	return PowerNode.has_line_of_sight(struct1.global_position, struct2.global_position, struct1, struct2)


func _update_reconnect_state(delta: float) -> void:
	if _leaf_reconnect_cooldowns.is_empty():
		_reconnect_scan_timer = maxf(_reconnect_scan_timer - delta, 0.0)
	else:
		var cooldown_ids: Array = _leaf_reconnect_cooldowns.keys()
		for node_id in cooldown_ids:
			var remaining: float = _leaf_reconnect_cooldowns[node_id]
			remaining -= delta
			if remaining <= 0.0:
				_leaf_reconnect_cooldowns.erase(node_id)
			else:
				_leaf_reconnect_cooldowns[node_id] = remaining
		_reconnect_scan_timer = maxf(_reconnect_scan_timer - delta, 0.0)
	
	if _reconnect_scan_timer > 0.0 or _reconnect_queue.is_empty():
		return
	_reconnect_scan_timer = RECONNECT_SCAN_INTERVAL
	
	var queued_nodes: Array = _reconnect_queue.keys()
	_reconnect_queue.clear()
	_attempt_leaf_reconnect(queued_nodes)


func _attempt_leaf_reconnect(candidates: Array, force: bool = false) -> void:
	if candidates.is_empty():
		return
	
	var any_reconnected: bool = false
	for candidate in candidates:
		var leaf_node: Node3D = candidate as Node3D
		if not _is_valid_leaf_reconnect_candidate(leaf_node, force):
			continue
		
		var candidate_max_distance: float = float(leaf_node.get("max_connection_distance"))
		var candidate_max_connections: int = int(leaf_node.get("max_connections"))
		var candidate_position: Vector3 = _get_node_world_position(leaf_node)
		var alternatives: Array = find_power_nodes_in_range(
			candidate_position,
			candidate_max_distance,
			candidate_max_connections
		)
		
		var reconnected: bool = false
		for other in alternatives:
			var target_node: Node3D = other as Node3D
			if not _is_valid_reconnect_target(leaf_node, target_node):
				continue
			if _connect_nodes(leaf_node, target_node):
				any_reconnected = true
				reconnected = true
				break
		
		# Keep retry pressure low so disrupted links do not cause thrashing.
		if reconnected or not force:
			_leaf_reconnect_cooldowns[leaf_node.get_instance_id()] = LEAF_RECONNECT_COOLDOWN
	
	if any_reconnected:
		_identify_subgraphs()


func _connect_nodes(node1: Node3D, node2: Node3D) -> bool:
	if node1 == null or node2 == null:
		return false
	if not _graph.has(node1) or not _graph.has(node2):
		return false
	if _graph[node1].has(node2):
		return false
	if not node1.can_connect_to(node2) or not node2.can_connect_to(node1):
		return false
	
	_graph[node1][node2] = true
	_graph[node2][node1] = true
	_create_edge(node1, node2)
	node1.connect_node(node2)
	node2.connect_node(node1)
	return true


func _is_valid_leaf_reconnect_candidate(node: Node3D, force: bool) -> bool:
	if not is_instance_valid(node):
		return false
	if not _nodes.has(node):
		return false
	if not node.has_method("get_node_type") or not node.has_method("can_accept_more_connections"):
		return false
	if int(node.call("get_node_type")) != int(PowerNode.NodeType.LEAF):
		return false
	if not node.can_accept_more_connections():
		return false
	if not force and _leaf_reconnect_cooldowns.has(node.get_instance_id()):
		return false
	return true


func _is_valid_reconnect_target(leaf_node: Node3D, target_node: Node3D) -> bool:
	if target_node == null or target_node == leaf_node:
		return false
	if not is_instance_valid(target_node):
		return false
	if not _nodes.has(target_node):
		return false
	if not target_node.has_method("can_accept_more_connections"):
		return false
	if _graph.has(leaf_node) and _graph[leaf_node].has(target_node):
		return false
	if not target_node.can_accept_more_connections():
		return false
	if target_node.has_method("is_valid_connection_target") and not target_node.is_valid_connection_target():
		return false
	
	var leaf_max_connections: int = int(leaf_node.get("max_connections"))
	var target_max_connections: int = int(target_node.get("max_connections"))
	if leaf_max_connections == 1 and target_max_connections == 1:
		return false
	
	return leaf_node.can_connect_to(target_node) and target_node.can_connect_to(leaf_node)


func _get_node_world_position(node: Node3D) -> Vector3:
	var struct: Node3D = node.get_parent() as Node3D
	if struct:
		return struct.global_position
	return node.global_position


func _queue_reconnect_for_leaf(node: Node3D) -> void:
	if not _is_valid_leaf_reconnect_candidate(node, false):
		return
	_reconnect_queue[node] = true


## Add a power user to tracking
func add_user(user: Node3D) -> void:
	if not _users.has(user):
		_users[user] = true
		_identify_subgraphs()


## Remove a power user from tracking
func remove_user(user: Node3D) -> void:
	if _users.erase(user):
		_identify_subgraphs()


## Add a power source to tracking
func add_source(source: Node3D) -> void:
	if not _sources.has(source):
		_sources[source] = true
		_identify_subgraphs()


## Remove a power source from tracking
func remove_source(source: Node3D) -> void:
	if _sources.erase(source):
		_identify_subgraphs()


## Add a power generator to tracking
func add_generator(generator: Node3D) -> void:
	if not _generators.has(generator):
		_generators[generator] = true
		_identify_subgraphs()


## Remove a power generator from tracking
func remove_generator(generator: Node3D) -> void:
	if _generators.erase(generator):
		_identify_subgraphs()


## Check if a node is powered (has power in its subgraph)
func _is_node_powered(node: Node3D) -> bool:
	var subgraph: PowerSubgraph = find_subgraph_for_node(node)
	return subgraph != null and subgraph.power_current > 0


## Identify all disconnected subgraphs in the power grid using DFS
func _identify_subgraphs() -> void:
	_subgraphs.clear()
	
	var visited: Dictionary = {}
	var unvisited: Dictionary = _nodes.duplicate()
	
	while not unvisited.is_empty():
		var start_node: Variant = unvisited.keys()[0]
		unvisited.erase(start_node)
		if not is_instance_valid(start_node):
			continue
		
		# Find all nodes in this subgraph using DFS
		var subgraph_nodes: Dictionary = {}
		var current_visited: Dictionary = {}
		_find_connected_nodes(start_node, current_visited, subgraph_nodes, unvisited)
		
		# Find all components in this subgraph
		var subgraph_users: Array = []
		var subgraph_sources: Array = []
		var subgraph_generators: Array = []
		
		for user in _users.keys():
			if is_instance_valid(user):
				var parent_node: Node3D = _get_power_node_parent(user)
				if parent_node and subgraph_nodes.has(parent_node):
					subgraph_users.append(user)
		
		for source in _sources.keys():
			if is_instance_valid(source) and _is_source_from_built_structure(source):
				var parent_node: Node3D = _get_power_node_parent(source)
				if parent_node and subgraph_nodes.has(parent_node):
					subgraph_sources.append(source)
		
		for generator in _generators.keys():
			if is_instance_valid(generator) and _is_generator_from_built_structure(generator):
				var parent_node: Node3D = _get_power_node_parent_for_generator(generator)
				if parent_node and subgraph_nodes.has(parent_node):
					subgraph_generators.append(generator)
		
		# Create and add the subgraph
		var subgraph: PowerSubgraph = PowerSubgraph.new()
		subgraph.nodes = subgraph_nodes.keys()
		subgraph.users = subgraph_users
		subgraph.sources = subgraph_sources
		subgraph.generators = subgraph_generators
		_subgraphs.append(subgraph)
		
		for key in current_visited:
			visited[key] = true
	
	subgraphs_updated.emit()


## DFS helper to find all connected nodes
func _find_connected_nodes(node: Node3D, visited: Dictionary, subgraph: Dictionary, unvisited: Dictionary) -> void:
	if not is_instance_valid(node):
		return
	visited[node] = true
	subgraph[node] = true
	unvisited.erase(node)
	
	if not _graph.has(node):
		return
	
	for neighbor in _graph[node].keys():
		if not is_instance_valid(neighbor):
			continue
		if not visited.has(neighbor) and is_edge_enabled(node, neighbor):
			_find_connected_nodes(neighbor, visited, subgraph, unvisited)


## Find the subgraph containing a specific node
func find_subgraph_for_node(node: Node3D) -> PowerSubgraph:
	for subgraph in _subgraphs:
		if node in subgraph.nodes:
			return subgraph
	return null


## Handle excess power from a generator by storing in nearby sources
func handle_generator_excess(generator: Node3D, excess_power: float) -> void:
	var parent_node: Node3D = _get_power_node_parent_for_generator(generator)
	if not parent_node:
		return
	
	var subgraph: PowerSubgraph = find_subgraph_for_node(parent_node)
	if not subgraph:
		return
	
	var queue: Array = []
	var visited: Dictionary = {}
	var path: Dictionary = {}
	var start_node: Node3D = parent_node
	
	while excess_power > 0:
		# Find the nearest source node in the graph
		var query_data: Dictionary = find_nearest_source_node(
			start_node,
			queue,
			visited,
			path
		)
		
		if query_data.source_node == null:
			return
		
		start_node = query_data.source_node
		
		# Get the source component from the node
		var source: Node3D = _get_source_from_node(query_data.source_node)
		if source == null:
			return
		
		# Try to store power in the source
		var available_space: float = source.get("max_storage") - source.get("current_storage")
		if available_space > 0:
			var power_to_store: float = clampf(excess_power, 0.0, available_space)
			excess_power -= power_to_store
			source.store_power(power_to_store)
		
		if queue.is_empty() or subgraph.power_current >= subgraph.power_capacity:
			break


## Draw power from sources for a user
func draw_power_for_user(user: Node3D, amount: float) -> float:
	var parent_node: Node3D = _get_power_node_parent(user)
	if not parent_node:
		return 0.0
	
	var subgraph: PowerSubgraph = find_subgraph_for_node(parent_node)
	if not subgraph:
		return 0.0
	
	var queue: Array = []
	var visited: Dictionary = {}
	var path: Dictionary = {}
	var start_node: Node3D = parent_node
	
	var total_power: float = 0.0
	
	while amount > 0:
		# Find the nearest source node in the graph
		var query_data: Dictionary = find_nearest_source_node(
			start_node,
			queue,
			visited,
			path
		)
		
		if query_data.source_node == null:
			return total_power
		
		start_node = query_data.source_node
		
		# Get the source component from the node
		var source: Node3D = _get_source_from_node(query_data.source_node)
		if source == null:
			return total_power
		
		# Try to draw power from the source
		var current_storage: float = source.get("current_storage")
		if current_storage > 0:
			var power_to_use: float = clampf(amount, 0.0, current_storage)
			amount -= power_to_use
			source.draw_power(power_to_use)
			total_power += power_to_use
			
			# Trigger power flow animation along the path from source to user
			if query_data.path.size() > 1:
				_trigger_power_flow(query_data.path)
		
		if queue.is_empty() or subgraph.power_current == 0.0:
			break
	
	return total_power


## Trigger a power flow animation along a path - pulses ALL edges instantly
func _trigger_power_flow(path: Array) -> void:
	if path.size() < 2:
		return
	
	# Pulse all edges in the path at once
	for i in range(path.size() - 1):
		var node1: Node3D = path[i]
		var node2: Node3D = path[i + 1]
		var edge_key: String = _get_edge_key(node1, node2)
		_pulsing_edges[edge_key] = PULSE_DURATION


## Get a unique key for an edge (order-independent)
func _get_edge_key(node1: Node3D, node2: Node3D) -> String:
	var id1: int = node1.get_instance_id()
	var id2: int = node2.get_instance_id()
	if id1 < id2:
		return "%d_%d" % [id1, id2]
	return "%d_%d" % [id2, id1]


## Update all pulsing edges
func _update_power_flows(delta: float) -> void:
	var edges_to_remove: Array = []
	
	for edge_key in _pulsing_edges.keys():
		var remaining: float = _pulsing_edges[edge_key]
		remaining -= delta
		
		if remaining <= 0:
			edges_to_remove.append(edge_key)
		else:
			_pulsing_edges[edge_key] = remaining
	
	# Remove expired pulses and reset their colors
	for edge_key in edges_to_remove:
		_pulsing_edges.erase(edge_key)
	
	# Update all edge visuals
	_update_all_edge_visuals()


## Update visual state of all edges
func _update_all_edge_visuals() -> void:
	var current_disrupted_edges: Dictionary = {}
	
	for node1 in _edges.keys():
		if not is_instance_valid(node1):
			continue
		for node2 in _edges[node1].keys():
			if not is_instance_valid(node2):
				continue
			
			var edge_data: Variant = _edges[node1][node2]
			if not edge_data is Dictionary:
				continue
			if not edge_data.has("line") or not is_instance_valid(edge_data.line):
				continue
			
			var line: MeshInstance3D = edge_data.line
			var mat: StandardMaterial3D = line.material_override as StandardMaterial3D
			if not mat:
				continue
			
			var edge_key: String = _get_edge_key(node1, node2)
			var edge_has_los: bool = _has_edge_line_of_sight(node1, node2)
			var endpoints_enabled: bool = node1.get("is_enabled") and node2.get("is_enabled")
			if not edge_has_los:
				current_disrupted_edges[edge_key] = true
				if not _known_disrupted_edges.has(edge_key):
					_queue_reconnect_for_leaf(node1)
					_queue_reconnect_for_leaf(node2)
				
				# Blocked LOS - red and dim to indicate disrupted link.
				mat.emission = Color(0.6, 0.1, 0.1)
				mat.emission_energy_multiplier = 1.2
				mat.albedo_color = Color(0.9, 0.2, 0.2, 0.75)
			elif _pulsing_edges.has(edge_key) and endpoints_enabled:
				# Pulsing - bright yellow/white
				var remaining: float = _pulsing_edges[edge_key]
				var intensity: float = remaining / PULSE_DURATION  # 1.0 to 0.0
				mat.emission = Color(1.0, 0.9 * intensity, 0.2 * intensity)
				mat.emission_energy_multiplier = 3.0 + 5.0 * intensity
				mat.albedo_color = Color(1.0, 0.9, 0.4, 0.9)
			else:
				# Normal - blue (dimmer when endpoint nodes are disabled)
				if endpoints_enabled:
					mat.emission = Color(0.2, 0.5, 0.9)
					mat.emission_energy_multiplier = 2.0
					mat.albedo_color = Color(0.3, 0.7, 1.0, 0.8)
				else:
					mat.emission = Color(0.1, 0.2, 0.4)
					mat.emission_energy_multiplier = 0.8
					mat.albedo_color = Color(0.2, 0.35, 0.6, 0.6)
	
	_known_disrupted_edges = current_disrupted_edges


## BFS to find nearest source node
func find_nearest_source_node(
	start_node: Node3D,
	queue_start: Array = [],
	visited_start: Dictionary = {},
	path_start: Dictionary = {}
) -> Dictionary:
	var queue: Array = queue_start
	var visited: Dictionary = visited_start
	var path_map: Dictionary = path_start
	
	# Start with the given node
	if start_node not in queue:
		queue.append(start_node)
	visited[start_node] = true
	
	while not queue.is_empty():
		var current: Variant = queue.pop_front()
		
		# Add all unvisited neighbors to the queue
		if not _graph.has(current):
			continue
		
		for neighbor in _graph[current].keys():
			if not visited.has(neighbor) and is_edge_enabled(current, neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
				path_map[neighbor] = current
		
		# Check if this node has a source component from a built structure
		var source: Node3D = _get_source_from_node(current)
		var has_source: bool = source != null and _is_source_from_built_structure(source)
		if has_source:
			# Reconstruct path from path_map
			var path: Array = []
			var node: Variant = current
			while node != start_node:
				path.insert(0, node)
				if not path_map.has(node):
					break
				node = path_map[node]
			path.insert(0, start_node)
			
			return {
				"source_node": current,
				"path": path,
				"visited": visited,
				"queue": queue
			}
	
	return {
		"source_node": null,
		"path": [],
		"visited": visited,
		"queue": queue
	}


## Find all power nodes within range of a position, sorted by distance (closest first)
## Returns ALL nodes in range - connections can be made to any node, power flow is controlled separately
func find_power_nodes_in_range(position: Vector3, radius: float, max_connections: int) -> Array:
	var nodes_in_range: Array = []
	
	for node in _nodes.keys():
		if not is_instance_valid(node):
			continue
		if not node.is_inside_tree():
			continue
		
		var node_max_distance: float = node.get("max_connection_distance")
		var node_max_connections: int = node.get("max_connections")
		
		# Get structure position (parent of the power node)
		var struct: Node3D = node.get_parent() as Node3D
		if struct and not struct.is_inside_tree():
			continue
		var node_pos: Vector3 = struct.global_position if struct else node.global_position
		var distance: float = node_pos.distance_to(position)
		
		if (distance <= radius or distance <= node_max_distance) and \
		   node.can_accept_more_connections() and \
		   not (max_connections == 1 and node_max_connections == 1):
			nodes_in_range.append({"node": node, "distance": distance})
	
	# Sort by distance (closest first)
	nodes_in_range.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.distance < b.distance
	)
	
	# Return just the nodes
	var result: Array = []
	for item in nodes_in_range:
		result.append(item.node)
	return result


## Returns candidate leaf targets for saboteurs: player-owned leaf nodes with structure,
## upstream neighbor, and line midpoint. Each entry: { structure, power_node, upstream_node,
## line_midpoint, is_damage_dealer }
func get_saboteur_leaf_targets(player_structures: Array) -> Array:
	var targets: Array = []
	for node in _nodes.keys():
		if not is_instance_valid(node):
			continue
		if not node.has_method("get_node_type"):
			continue
		if int(node.call("get_node_type")) != int(PowerNode.NodeType.LEAF):
			continue
		var struct: Node3D = node.get_parent() as Node3D
		if not struct or struct not in player_structures:
			continue
		# Skip unbuilt structures
		var construction: Node = struct.get_node_or_null("ConstructionComponent")
		if construction != null and construction.get("is_built") != true:
			continue
		# Skip destroyed
		if struct.get("is_destroyed") == true:
			continue
		if not _graph.has(node):
			continue
		var neighbors: Array = _graph[node].keys()
		if neighbors.is_empty():
			continue
		var upstream_node: Node3D = neighbors[0]
		if not is_instance_valid(upstream_node):
			continue
		var leaf_pos: Vector3 = _get_node_world_position(node)
		var upstream_pos: Vector3 = _get_node_world_position(upstream_node)
		var line_midpoint: Vector3 = (leaf_pos + upstream_pos) * 0.5
		var building_type: String = str(struct.get("building_type"))
		var is_damage_dealer: bool = (building_type == "laser_turret")
		targets.append({
			"structure": struct,
			"power_node": node,
			"upstream_node": upstream_node,
			"line_midpoint": line_midpoint,
			"line_start": leaf_pos,
			"line_end": upstream_pos,
			"is_damage_dealer": is_damage_dealer
		})
	return targets


## Get the power node parent of a component
func _get_power_node_parent(component: Node3D) -> Node3D:
	var parent: Node = component.get_parent()
	if parent and parent.has_method("can_accept_more_connections"):
		return parent
	return null


## Get power node parent for a generator (goes through source)
func _get_power_node_parent_for_generator(generator: Node3D) -> Node3D:
	var source_parent: Node = generator.get_parent()
	if source_parent:
		return _get_power_node_parent(source_parent)
	return null


## Check if a PowerSource belongs to a fully built structure (e.g. solar panel)
## PowerSource -> PowerNode -> Structure; Structure has ConstructionComponent
func _is_source_from_built_structure(source: Node) -> bool:
	var power_node: Node = source.get_parent()
	if not power_node:
		return true
	var structure: Node = power_node.get_parent()
	if not structure:
		return true
	var construction: Node = structure.get_node_or_null("ConstructionComponent")
	if construction == null:
		return true  # No construction component = assume built
	return construction.get("is_built") == true


## Check if a PowerGenerator belongs to a fully built structure
## PowerGenerator -> PowerSource -> PowerNode -> Structure
func _is_generator_from_built_structure(generator: Node) -> bool:
	var source: Node = generator.get_parent()
	if not source:
		return true
	var power_node: Node = source.get_parent()
	if not power_node:
		return true
	var structure: Node = power_node.get_parent()
	if not structure:
		return true
	var construction: Node = structure.get_node_or_null("ConstructionComponent")
	if construction == null:
		return true
	return construction.get("is_built") == true


## Get source component from a power node
func _get_source_from_node(node: Node3D) -> Node3D:
	for child in node.get_children():
		if child.has_method("store_power") and child.has_method("draw_power"):
			return child
	return null


## Create visual edge between two nodes
func _create_edge(node1: Node3D, node2: Node3D) -> void:
	if _edges.has(node1) and _edges[node1].has(node2):
		return
	
	var edge_key: String = _edge_key(node1, node2)
	var line: MeshInstance3D = null
	if _lines_parent and node1.is_inside_tree() and node2.is_inside_tree():
		_ensure_lines_parent_in_scene()
		# Use legacy mesh path so lines render in the 3D scene (LineBatchManager has visibility issues)
		line = _create_line_mesh(node1, node2)
		if line:
			_lines_parent.add_child(line)
			_apply_line_transform(line, node1, node2)
	
	if not _edges.has(node1):
		_edges[node1] = {}
	if not _edges.has(node2):
		_edges[node2] = {}
	
	var edge_data: Dictionary = {
		"start": node1,
		"end": node2,
		"line": line,
		"edge_key": edge_key
	}
	_edges[node1][node2] = edge_data
	_edges[node2][node1] = edge_data


## Create a line mesh between two nodes (single merged mesh: cone + cylinder + cone)
func _create_line_mesh(node1: Node3D, node2: Node3D) -> MeshInstance3D:
	var line_instance: MeshInstance3D = MeshInstance3D.new()
	
	var pos1: Vector3 = _get_connection_anchor(node1)
	var pos2: Vector3 = _get_connection_anchor(node2)
	
	# Create glowing material
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.7, 1.0, 0.8)  # Light blue
	material.emission_enabled = true
	material.emission = Color(0.2, 0.5, 0.9)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_receive_shadows = true
	line_instance.material_override = material
	line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var delta: Vector3 = pos2 - pos1
	var distance: float = delta.length()
	if distance < POWER_LINE_MIN_SEGMENT_LENGTH:
		delta = Vector3.FORWARD * POWER_LINE_MIN_SEGMENT_LENGTH
		distance = POWER_LINE_MIN_SEGMENT_LENGTH
		pos2 = pos1 + delta
	var direction: Vector3 = delta / distance
	
	var start_stop_radius: float = maxf(_get_taper_radius_for_power_node(node1), 0.0)
	var end_stop_radius: float = maxf(_get_taper_radius_for_power_node(node2), 0.0)
	var max_stop_total: float = maxf(distance - POWER_LINE_MIN_SEGMENT_LENGTH, 0.0)
	var stop_total: float = start_stop_radius + end_stop_radius
	if stop_total > max_stop_total and stop_total > 0.0:
		var stop_scale: float = max_stop_total / stop_total
		start_stop_radius *= stop_scale
		end_stop_radius *= stop_scale
	
	var stop_start: Vector3 = pos1 + direction * start_stop_radius
	var stop_end: Vector3 = pos2 - direction * end_stop_radius
	var visible_length: float = stop_start.distance_to(stop_end)
	if visible_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		return line_instance
	
	var max_taper_each_side: float = maxf((visible_length - POWER_LINE_MIN_SEGMENT_LENGTH) * 0.5, 0.0)
	var taper_length: float = minf(POWER_LINE_TAPER_LENGTH, max_taper_each_side)
	
	var merged_mesh: ArrayMesh = _create_merged_tapered_line_mesh(taper_length, visible_length)
	if merged_mesh != null:
		line_instance.mesh = merged_mesh
	
	return line_instance


## Apply position and rotation to a line mesh after it's in the tree (uses global coords for correct placement).
func _apply_line_transform(line: MeshInstance3D, node1: Node3D, node2: Node3D) -> void:
	if line == null or not line.is_inside_tree():
		return
	var pos1: Vector3 = _get_connection_anchor(node1)
	var pos2: Vector3 = _get_connection_anchor(node2)
	var delta: Vector3 = pos2 - pos1
	var distance: float = delta.length()
	if distance < POWER_LINE_MIN_SEGMENT_LENGTH:
		delta = Vector3.FORWARD * POWER_LINE_MIN_SEGMENT_LENGTH
		distance = POWER_LINE_MIN_SEGMENT_LENGTH
	var direction: Vector3 = delta / distance
	var start_stop_radius: float = maxf(_get_taper_radius_for_power_node(node1), 0.0)
	var end_stop_radius: float = maxf(_get_taper_radius_for_power_node(node2), 0.0)
	var max_stop_total: float = maxf(distance - POWER_LINE_MIN_SEGMENT_LENGTH, 0.0)
	var stop_total: float = start_stop_radius + end_stop_radius
	if stop_total > max_stop_total and stop_total > 0.0:
		var stop_scale: float = max_stop_total / stop_total
		start_stop_radius *= stop_scale
		end_stop_radius *= stop_scale
	var stop_start: Vector3 = pos1 + direction * start_stop_radius
	var stop_end: Vector3 = pos2 - direction * end_stop_radius
	# 270° rotation makes mesh +Y point toward node1; position at stop_end so line spans stop_start→stop_end
	line.global_position = stop_end
	var up: Vector3 = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	line.look_at(stop_start, up)
	line.rotate_object_local(Vector3(1, 0, 0), 3 * PI / 2)


## Build a single ArrayMesh for tapered line (cone + cylinder + cone) to avoid seams and visual artifacts.
func _create_merged_tapered_line_mesh(taper_length: float, visible_length: float) -> ArrayMesh:
	const RADIAL_SEGMENTS: int = 12
	const MIN_CAP_RADIUS: float = 0.001
	var start_radius: float = MIN_CAP_RADIUS if taper_length >= POWER_LINE_MIN_SEGMENT_LENGTH else POWER_LINE_RENDER_RADIUS
	var end_radius: float = MIN_CAP_RADIUS if taper_length >= POWER_LINE_MIN_SEGMENT_LENGTH else POWER_LINE_RENDER_RADIUS
	var center_radius: float = POWER_LINE_RENDER_RADIUS
	var y0: float = 0.0
	var y1: float = taper_length
	var y2: float = visible_length - taper_length
	var y3: float = visible_length
	var radii: Array[float] = [start_radius, center_radius, center_radius, end_radius]
	var heights: Array[float] = [y0, y1, y2, y3]
	if taper_length < POWER_LINE_MIN_SEGMENT_LENGTH:
		radii = [center_radius, center_radius]
		heights = [y0, y3]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_idx in range(heights.size()):
		var y: float = heights[ring_idx]
		var r: float = radii[ring_idx]
		for j in range(RADIAL_SEGMENTS):
			var angle: float = TAU * float(j) / float(RADIAL_SEGMENTS)
			var x: float = r * cos(angle)
			var z: float = r * sin(angle)
			st.add_vertex(Vector3(x, y, z))
	for ring_idx in range(heights.size() - 1):
		var base: int = ring_idx * RADIAL_SEGMENTS
		for j in range(RADIAL_SEGMENTS):
			var j_next: int = (j + 1) % RADIAL_SEGMENTS
			var a: int = base + j
			var b: int = base + j_next
			var c: int = base + RADIAL_SEGMENTS + j
			var d: int = base + RADIAL_SEGMENTS + j_next
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	return st.commit()


func _get_taper_radius_for_power_node(power_node: Node3D) -> float:
	if power_node == null:
		return DEFAULT_TAPER_RADIUS
	var structure: Node3D = power_node.get_parent() as Node3D
	if structure == null:
		return DEFAULT_TAPER_RADIUS
	var building_type: String = str(structure.get("building_type"))
	if building_type.is_empty():
		return DEFAULT_TAPER_RADIUS
	if BuildManager == null or not BuildManager.has_method("get_placement_sphere_radius"):
		return DEFAULT_TAPER_RADIUS
	var radius: float = BuildManager.get_placement_sphere_radius(building_type)
	if radius <= 0.0:
		return DEFAULT_TAPER_RADIUS
	return maxf(radius, POWER_LINE_MIN_SEGMENT_LENGTH)


func _get_connection_anchor(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	var structure: Node3D = node.get_parent() as Node3D
	if structure == null or not structure.is_inside_tree():
		return node.global_position
	
	var connection_point: Node3D = structure.get_node_or_null("VisualRoot/ConnectionPoint") as Node3D
	if connection_point and connection_point.is_inside_tree():
		return connection_point.global_position
	
	var top_y: float = structure.global_position.y + 0.8
	var found_mesh: bool = false
	for child in structure.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var local_aabb: AABB = mesh_instance.mesh.get_aabb()
			var world_aabb: AABB = local_aabb * mesh_instance.global_transform
			top_y = maxf(top_y, world_aabb.end.y)
			found_mesh = true
	
	if not found_mesh:
		top_y = maxf(top_y, node.global_position.y + 0.8)
	
	return Vector3(structure.global_position.x, top_y, structure.global_position.z)


func _edge_key(node1: Node3D, node2: Node3D) -> String:
	var a: int = node1.get_instance_id()
	var b: int = node2.get_instance_id()
	if a > b:
		var t: int = a
		a = b
		b = t
	return "e_%d_%d" % [a, b]


## Remove visual edge between two nodes
func _remove_edge(node1: Node3D, node2: Node3D) -> void:
	if _edges.has(node1) and _edges[node1].has(node2):
		var edge_data: Dictionary = _edges[node1][node2]
		if edge_data.has("line") and is_instance_valid(edge_data.line):
			edge_data.line.queue_free()
		elif edge_data.has("edge_key") and LineBatchManager != null:
			LineBatchManager.free_line(edge_data.edge_key)
	
	if _edges.has(node1):
		_edges[node1].erase(node2)
	if _edges.has(node2):
		_edges[node2].erase(node1)


## Check if a specific node is enabled
func is_node_enabled(node: Node3D) -> bool:
	return node.get("is_enabled")


## Get all edges for visualization
func get_edges() -> Dictionary:
	return _edges


## Reset for new game scene (e.g. restart). Clears graph and recreates lines parent.
## Call from main_game when the game scene loads, before structures are spawned.
func reset_for_game_scene() -> void:
	clear()
	if _lines_parent == null or not is_instance_valid(_lines_parent):
		_lines_parent = Node3D.new()
		_lines_parent.name = "PowerLines"
		add_child(_lines_parent)
	_ensure_lines_parent_in_scene()


## Clear all data (for testing/reset)
func clear() -> void:
	_nodes.clear()
	_users.clear()
	_sources.clear()
	_generators.clear()
	_graph.clear()
	_edges.clear()
	_subgraphs.clear()


## PowerSubgraph inner class
class PowerSubgraph:
	var nodes: Array = []
	var users: Array = []
	var sources: Array = []
	var generators: Array = []
	
	## Get total power capacity of all sources in this subgraph
	var power_capacity: float:
		get:
			var total: float = 0.0
			for source in sources:
				if is_instance_valid(source):
					total += source.get("max_storage")
			return total
	
	## Get current power stored in all sources
	var power_current: float:
		get:
			var total: float = 0.0
			for source in sources:
				if is_instance_valid(source):
					total += source.get("current_storage")
			return total
	
	## Get total power generation
	var power_generation: float:
		get:
			var total: float = 0.0
			for generator in generators:
				if is_instance_valid(generator):
					total += generator.get("current_output")
			return total
	
	## Get total power consumption
	var power_consumption: float:
		get:
			var total: float = 0.0
			for user in users:
				if is_instance_valid(user):
					total += user.get("power_consumption")
			return total
	
	## Get power balance (generation - consumption)
	var power_balance: float:
		get:
			return power_generation - power_consumption
	
	## Get available power
	var available_power: float:
		get:
			return power_current + power_balance
	
	## Check if subgraph has enough power
	var has_enough_power: bool:
		get:
			return available_power >= power_consumption
