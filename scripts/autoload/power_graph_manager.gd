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

var _known_disrupted_edges: Dictionary = {}  # edge_key -> true
var _reconnect_queue: Dictionary = {}  # PowerNode -> true
var _leaf_reconnect_cooldowns: Dictionary = {}  # instance_id -> remaining seconds
var _reconnect_scan_timer: float = 0.0


func _ready() -> void:
	_lines_parent = Node3D.new()
	_lines_parent.name = "PowerLines"
	add_child(_lines_parent)
	set_process(true)


func _process(delta: float) -> void:
	_update_power_flows(delta)
	_update_reconnect_state(delta)


## Get total power capacity across all sources
func get_power_capacity() -> float:
	var total: float = 0.0
	for source in _sources.keys():
		if is_instance_valid(source):
			total += source.get("max_storage")
	return total


## Get current power stored across all sources
func get_power_current() -> float:
	var total: float = 0.0
	for source in _sources.keys():
		if is_instance_valid(source):
			total += source.get("current_storage")
	return total


## Get total power generation across all generators
func get_power_generation() -> float:
	var total: float = 0.0
	for generator in _generators.keys():
		if is_instance_valid(generator):
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
	return (node1.get("is_enabled") or node2.get("is_enabled")) and _has_edge_line_of_sight(node1, node2)


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
			if is_instance_valid(source):
				var parent_node: Node3D = _get_power_node_parent(source)
				if parent_node and subgraph_nodes.has(parent_node):
					subgraph_sources.append(source)
		
		for generator in _generators.keys():
			if is_instance_valid(generator):
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
	visited[node] = true
	subgraph[node] = true
	unvisited.erase(node)
	
	if not _graph.has(node):
		return
	
	for neighbor in _graph[node].keys():
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
			var endpoints_enabled: bool = node1.get("is_enabled") or node2.get("is_enabled")
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
		
		# Check if this node has a source component
		var has_source: bool = _get_source_from_node(current) != null
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
		
		var node_max_distance: float = node.get("max_connection_distance")
		var node_max_connections: int = node.get("max_connections")
		
		# Get structure position (parent of the power node)
		var struct: Node3D = node.get_parent() as Node3D
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
	
	# Create visual line (only if nodes are in tree)
	var line: MeshInstance3D = null
	if _lines_parent and node1.is_inside_tree() and node2.is_inside_tree():
		line = _create_line_mesh(node1, node2)
		_lines_parent.add_child(line)
	
	# Store edge data with visual reference
	if not _edges.has(node1):
		_edges[node1] = {}
	if not _edges.has(node2):
		_edges[node2] = {}
	
	var edge_data: Dictionary = {
		"start": node1,
		"end": node2,
		"line": line
	}
	_edges[node1][node2] = edge_data
	_edges[node2][node1] = edge_data


## Create a line mesh between two nodes
func _create_line_mesh(node1: Node3D, node2: Node3D) -> MeshInstance3D:
	var line_instance: MeshInstance3D = MeshInstance3D.new()
	
	# Get parent positions (nodes are children of structures)
	var parent1: Node = node1.get_parent()
	var parent2: Node = node2.get_parent()
	var pos1: Vector3 = parent1.global_position if parent1 and parent1.is_inside_tree() else node1.position
	var pos2: Vector3 = parent2.global_position if parent2 and parent2.is_inside_tree() else node2.position
	
	# Create a cylinder mesh as the line
	var cylinder: CylinderMesh = CylinderMesh.new()
	var distance: float = pos1.distance_to(pos2)
	if distance < 0.1:
		distance = 0.1  # Minimum distance
	cylinder.top_radius = 0.15
	cylinder.bottom_radius = 0.15
	cylinder.height = distance
	
	line_instance.mesh = cylinder
	
	# Create glowing material
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.7, 1.0, 0.8)  # Light blue
	material.emission_enabled = true
	material.emission = Color(0.2, 0.5, 0.9)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_instance.material_override = material
	
	# Position at midpoint
	var midpoint: Vector3 = (pos1 + pos2) / 2.0
	midpoint.y = 0.3  # Slightly above ground
	line_instance.position = midpoint
	
	# Rotate to point from pos1 to pos2
	var direction: Vector3 = (pos2 - pos1).normalized()
	if direction.length() > 0.01:
		# Calculate rotation to align cylinder (Y-axis) with direction
		var up: Vector3 = Vector3.UP
		if abs(direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		line_instance.look_at_from_position(midpoint, midpoint + direction, up)
		line_instance.rotate_object_local(Vector3(1, 0, 0), PI / 2)
	
	return line_instance


## Remove visual edge between two nodes
func _remove_edge(node1: Node3D, node2: Node3D) -> void:
	# Remove visual line
	if _edges.has(node1) and _edges[node1].has(node2):
		var edge_data: Dictionary = _edges[node1][node2]
		if edge_data.has("line") and is_instance_valid(edge_data.line):
			edge_data.line.queue_free()
	
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
