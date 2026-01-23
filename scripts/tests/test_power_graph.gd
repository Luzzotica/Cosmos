extends GutTest
## GUT Tests for PowerGraphManager
## 
## These tests mirror the Flutter tests to ensure the power graph system
## behaves identically after migration.

const PowerNode = preload("res://scripts/components/power_node.gd")
const PowerSource = preload("res://scripts/components/power_source.gd")
const PowerGenerator = preload("res://scripts/components/power_generator.gd")
const PowerUser = preload("res://scripts/components/power_user.gd")

var _test_nodes: Array = []


func before_each() -> void:
	# Clear the power graph before each test
	PowerGraphManager.clear()
	_test_nodes.clear()


func after_each() -> void:
	# Clean up test nodes
	for node in _test_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_test_nodes.clear()
	PowerGraphManager.clear()


## Helper to create a test node at a position
func _create_test_node(pos: Vector3, max_distance: float = 100.0, max_conn: int = 4, enabled: bool = true) -> Node3D:
	var parent: Node3D = Node3D.new()
	parent.global_position = pos
	
	var node: PowerNode = PowerNode.new()
	node.max_connection_distance = max_distance
	node.max_connections = max_conn
	node.is_enabled = enabled
	
	parent.add_child(node)
	add_child_autofree(parent)
	_test_nodes.append(parent)
	
	# Manually register since we're not going through normal tree enter
	PowerGraphManager.add_node(node)
	
	return node


## Helper to create a node with a source
func _create_node_with_source(pos: Vector3, max_storage: float = 100.0, current: float = 0.0) -> Dictionary:
	var parent: Node3D = Node3D.new()
	parent.global_position = pos
	
	var node: PowerNode = PowerNode.new()
	node.max_connection_distance = 100.0
	node.max_connections = 4
	node.is_enabled = true
	
	var source: PowerSource = PowerSource.new()
	source.max_storage = max_storage
	source.current_storage = current
	
	parent.add_child(node)
	node.add_child(source)
	add_child_autofree(parent)
	_test_nodes.append(parent)
	
	PowerGraphManager.add_node(node)
	PowerGraphManager.add_source(source)
	
	return {"parent": parent, "node": node, "source": source}


## Helper to create a node with a user
func _create_node_with_user(pos: Vector3, use_cost: float = 50.0, buffer_cap: float = 100.0) -> Dictionary:
	var parent: Node3D = Node3D.new()
	parent.global_position = pos
	
	var node: PowerNode = PowerNode.new()
	node.max_connection_distance = 100.0
	node.max_connections = 4
	node.is_enabled = true
	
	var user: PowerUser = PowerUser.new()
	user.use_power_cost = use_cost
	user.power_buffer_capacity = buffer_cap
	
	parent.add_child(node)
	node.add_child(user)
	add_child_autofree(parent)
	_test_nodes.append(parent)
	
	PowerGraphManager.add_node(node)
	PowerGraphManager.add_user(user)
	
	return {"parent": parent, "node": node, "user": user}


## Helper to create a node with source and generator
func _create_node_with_generator(pos: Vector3, power_output: float = 50.0, max_storage: float = 100.0, current: float = 0.0) -> Dictionary:
	var parent: Node3D = Node3D.new()
	parent.global_position = pos
	
	var node: PowerNode = PowerNode.new()
	node.max_connection_distance = 100.0
	node.max_connections = 4
	node.is_enabled = true
	
	var source: PowerSource = PowerSource.new()
	source.max_storage = max_storage
	source.current_storage = current
	
	var generator: PowerGenerator = PowerGenerator.new()
	generator.power_output = power_output
	generator.is_active = true
	
	parent.add_child(node)
	node.add_child(source)
	source.add_child(generator)
	add_child_autofree(parent)
	_test_nodes.append(parent)
	
	PowerGraphManager.add_node(node)
	PowerGraphManager.add_source(source)
	PowerGraphManager.add_generator(generator)
	
	return {"parent": parent, "node": node, "source": source, "generator": generator}


# ====================
# Component Registration Tests
# ====================

func test_adds_and_removes_nodes() -> void:
	var node: Node3D = _create_test_node(Vector3.ZERO)
	
	var subgraph: PowerGraphManagerClass.PowerSubgraph = PowerGraphManager.find_subgraph_for_node(node)
	assert_not_null(subgraph, "Node should be in a subgraph after adding")
	
	PowerGraphManager.remove_node(node)
	
	subgraph = PowerGraphManager.find_subgraph_for_node(node)
	assert_null(subgraph, "Node should not be in a subgraph after removing")


func test_adds_and_removes_sources() -> void:
	var data: Dictionary = _create_node_with_source(Vector3.ZERO, 100.0, 50.0)
	
	assert_eq(PowerGraphManager.get_power_capacity(), 100.0, "Power capacity should be 100")
	
	PowerGraphManager.remove_source(data.source)
	
	assert_eq(PowerGraphManager.get_power_capacity(), 0.0, "Power capacity should be 0 after removing source")


# ====================
# Graph Structure Tests
# ====================

func test_connects_nodes_within_range() -> void:
	# Create three nodes in a line, each 75 units apart (within 100 range)
	var node1: Node3D = _create_test_node(Vector3(0, 0, 0))
	var node2: Node3D = _create_test_node(Vector3(75, 0, 0))
	var node3: Node3D = _create_test_node(Vector3(150, 0, 0))
	
	assert_eq(node1.connected_nodes.size(), 1, "Node1 should have 1 connection")
	assert_eq(node2.connected_nodes.size(), 2, "Node2 should have 2 connections")
	assert_eq(node3.connected_nodes.size(), 1, "Node3 should have 1 connection")
	
	assert_true(node1.connected_nodes.has(node2), "Node1 should be connected to Node2")
	assert_true(node2.connected_nodes.has(node1), "Node2 should be connected to Node1")
	assert_true(node2.connected_nodes.has(node3), "Node2 should be connected to Node3")
	assert_true(node3.connected_nodes.has(node2), "Node3 should be connected to Node2")


func test_respects_max_connections() -> void:
	# Node1 has 20 max connections, Node2 has only 1
	var parent1: Node3D = Node3D.new()
	parent1.global_position = Vector3(0, 0, 0)
	var node1: PowerNode = PowerNode.new()
	node1.max_connection_distance = 100.0
	node1.max_connections = 20
	node1.is_enabled = true
	parent1.add_child(node1)
	add_child_autofree(parent1)
	_test_nodes.append(parent1)
	PowerGraphManager.add_node(node1)
	
	var parent2: Node3D = Node3D.new()
	parent2.global_position = Vector3(75, 0, 0)
	var node2: PowerNode = PowerNode.new()
	node2.max_connection_distance = 100.0
	node2.max_connections = 1
	node2.is_enabled = true
	parent2.add_child(node2)
	add_child_autofree(parent2)
	_test_nodes.append(parent2)
	PowerGraphManager.add_node(node2)
	
	assert_eq(node1.connected_nodes.size(), 1, "Node1 should have 1 connection")
	assert_eq(node2.connected_nodes.size(), 1, "Node2 should have 1 connection")


func test_does_not_connect_nodes_out_of_range() -> void:
	# Create two nodes 150 units apart (outside 100 range)
	var node1: Node3D = _create_test_node(Vector3(0, 0, 0))
	var node2: Node3D = _create_test_node(Vector3(150, 0, 0))
	
	assert_eq(node1.connected_nodes.size(), 0, "Node1 should have no connections")
	assert_eq(node2.connected_nodes.size(), 0, "Node2 should have no connections")


# ====================
# Pathfinding Tests
# ====================

func test_finds_nearest_source_node() -> void:
	# Create a chain: startNode -> middleNode -> sourceNode
	var start_data: Dictionary = _create_node_with_user(Vector3(0, 0, 0))
	var middle: Node3D = _create_test_node(Vector3(75, 0, 0))
	var source_data: Dictionary = _create_node_with_source(Vector3(150, 0, 0), 100.0, 50.0)
	
	var result: Dictionary = PowerGraphManager.find_nearest_source_node(start_data.node)
	
	assert_eq(result.source_node, source_data.node, "Should find the source node")
	assert_eq(result.path.size(), 3, "Path should have 3 nodes")
	assert_eq(result.path[0], start_data.node, "Path should start with start node")
	assert_eq(result.path[1], middle, "Path should go through middle node")
	assert_eq(result.path[2], source_data.node, "Path should end with source node")


# ====================
# Power Distribution Tests
# ====================

func test_handles_individual_power_sources() -> void:
	var data: Dictionary = _create_node_with_generator(Vector3.ZERO, 50.0, 100.0, 25.0)
	
	# Simulate generating power (manual store since we're not running _process)
	data.source.store_power(50.0)
	
	assert_eq(data.source.current_storage, 75.0, "Source should have 75 power after generating 50")
	
	data.source.store_power(50.0)
	
	assert_eq(data.source.current_storage, 100.0, "Source should be capped at max storage")


func test_distributes_power_between_sources() -> void:
	# Create two connected sources, generator on first
	var data1: Dictionary = _create_node_with_generator(Vector3(0, 0, 0), 75.0, 100.0, 0.0)
	var data2: Dictionary = _create_node_with_source(Vector3(75, 0, 0), 100.0, 0.0)  # Within range
	
	# First store fills source1
	data1.source.store_power(75.0)
	assert_eq(data1.source.current_storage, 75.0, "Source1 should have 75 power")
	assert_eq(data2.source.current_storage, 0.0, "Source2 should still have 0 power")
	
	# Second store should fill source1 then overflow to source2
	data1.source.store_power(75.0)  # Only 25 space in source1
	
	# Manually handle excess since we're not running the full generator logic
	var excess: float = 75.0 - 25.0  # 50 excess
	PowerGraphManager.handle_generator_excess(data1.generator, excess)
	
	assert_eq(data1.source.current_storage, 100.0, "Source1 should be full")
	assert_eq(data2.source.current_storage, 50.0, "Source2 should have received excess")


func test_draws_power_for_user() -> void:
	# Create user node with two sources behind it
	var user_data: Dictionary = _create_node_with_user(Vector3(0, 0, 0), 50.0, 50.0)
	var source1_data: Dictionary = _create_node_with_source(Vector3(75, 0, 0), 100.0, 75.0)
	var source2_data: Dictionary = _create_node_with_source(Vector3(150, 0, 0), 100.0, 50.0)
	
	# Draw power - should take from closest source first
	var drawn: float = PowerGraphManager.draw_power_for_user(user_data.user, 50.0)
	
	assert_eq(drawn, 50.0, "Should draw 50 power")
	assert_eq(source1_data.source.current_storage, 25.0, "Source1 should have 25 remaining")
	assert_eq(source2_data.source.current_storage, 50.0, "Source2 should still have 50")
	
	# Draw more - should take rest from source1 then from source2
	drawn = PowerGraphManager.draw_power_for_user(user_data.user, 50.0)
	
	assert_eq(drawn, 50.0, "Should draw 50 more power")
	assert_eq(source1_data.source.current_storage, 0.0, "Source1 should be empty")
	assert_eq(source2_data.source.current_storage, 25.0, "Source2 should have 25 remaining")


func test_user_consume_power() -> void:
	# Create user with sources
	var user_data: Dictionary = _create_node_with_user(Vector3(0, 0, 0), 50.0, 50.0)
	var source1_data: Dictionary = _create_node_with_source(Vector3(75, 0, 0), 100.0, 75.0)
	var source2_data: Dictionary = _create_node_with_source(Vector3(150, 0, 0), 100.0, 50.0)
	
	# First consume should succeed (draws from grid into buffer, then uses)
	var result: bool = user_data.user.consume_power()
	assert_true(result, "First consume should succeed")
	assert_eq(source1_data.source.current_storage, 25.0, "Source1 should have 25 remaining")
	
	# Second consume should also succeed
	result = user_data.user.consume_power()
	assert_true(result, "Second consume should succeed")
	assert_eq(source1_data.source.current_storage, 0.0, "Source1 should be empty")
	assert_eq(source2_data.source.current_storage, 25.0, "Source2 should have 25 remaining")
	
	# Third consume should fail (not enough power left)
	result = user_data.user.consume_power()
	assert_false(result, "Third consume should fail - not enough power")


# ====================
# Subgraph Tests
# ====================

func test_single_connected_subgraph() -> void:
	# Create a connected network with various components
	var gen_data: Dictionary = _create_node_with_generator(Vector3(0, 0, 0), 50.0, 100.0, 0.0)
	var user_data: Dictionary = _create_node_with_user(Vector3(75, 0, 0))
	var source_data: Dictionary = _create_node_with_source(Vector3(150, 0, 0), 100.0, 0.0)
	
	var subgraph: PowerGraphManagerClass.PowerSubgraph = PowerGraphManager.find_subgraph_for_node(gen_data.node)
	
	assert_not_null(subgraph, "Should find a subgraph")
	assert_true(gen_data.node in subgraph.nodes, "Subgraph should contain generator node")
	assert_true(user_data.node in subgraph.nodes, "Subgraph should contain user node")
	assert_true(source_data.node in subgraph.nodes, "Subgraph should contain source node")
	assert_true(gen_data.source in subgraph.sources, "Subgraph should contain generator's source")
	assert_true(source_data.source in subgraph.sources, "Subgraph should contain standalone source")
	assert_true(user_data.user in subgraph.users, "Subgraph should contain user")
	assert_true(gen_data.generator in subgraph.generators, "Subgraph should contain generator")


func test_multiple_disconnected_subgraphs() -> void:
	# Create two separate networks (200 units apart, outside connection range)
	var source1_data: Dictionary = _create_node_with_source(Vector3(0, 0, 0), 100.0, 50.0)
	var user1_data: Dictionary = _create_node_with_user(Vector3(75, 0, 0))
	
	var source2_data: Dictionary = _create_node_with_source(Vector3(200, 0, 0), 100.0, 50.0)
	var user2_data: Dictionary = _create_node_with_user(Vector3(275, 0, 0))
	
	var subgraph1: PowerGraphManagerClass.PowerSubgraph = PowerGraphManager.find_subgraph_for_node(source1_data.node)
	var subgraph2: PowerGraphManagerClass.PowerSubgraph = PowerGraphManager.find_subgraph_for_node(source2_data.node)
	
	assert_not_null(subgraph1, "Should find subgraph1")
	assert_not_null(subgraph2, "Should find subgraph2")
	assert_ne(subgraph1, subgraph2, "Subgraphs should be different")
	
	assert_true(source1_data.node in subgraph1.nodes, "Subgraph1 should contain source1 node")
	assert_true(user1_data.node in subgraph1.nodes, "Subgraph1 should contain user1 node")
	assert_true(source1_data.source in subgraph1.sources, "Subgraph1 should contain source1")
	assert_true(user1_data.user in subgraph1.users, "Subgraph1 should contain user1")
	
	assert_true(source2_data.node in subgraph2.nodes, "Subgraph2 should contain source2 node")
	assert_true(user2_data.node in subgraph2.nodes, "Subgraph2 should contain user2 node")
	assert_true(source2_data.source in subgraph2.sources, "Subgraph2 should contain source2")
	assert_true(user2_data.user in subgraph2.users, "Subgraph2 should contain user2")


# ====================
# Node State Tests
# ====================

func test_enable_and_disable_node() -> void:
	var node1: Node3D = _create_test_node(Vector3(0, 0, 0))
	var node2: Node3D = _create_test_node(Vector3(75, 0, 0))
	
	# Initially both nodes and their edge should be enabled
	assert_true(node1.is_enabled, "Node1 should be enabled initially")
	assert_true(node2.is_enabled, "Node2 should be enabled initially")
	assert_true(PowerGraphManager.is_edge_enabled(node1, node2), "Edge should be enabled initially")
	
	# Disable node1
	PowerGraphManager.disable_node(node1)
	assert_false(node1.is_enabled, "Node1 should be disabled")
	assert_true(node2.is_enabled, "Node2 should still be enabled")
	assert_true(PowerGraphManager.is_edge_enabled(node1, node2), "Edge should still be enabled (one node enabled)")
	
	# Disable node2 as well
	PowerGraphManager.disable_node(node2)
	assert_false(node1.is_enabled, "Node1 should still be disabled")
	assert_false(node2.is_enabled, "Node2 should be disabled")
	assert_false(PowerGraphManager.is_edge_enabled(node1, node2), "Edge should be disabled (both nodes disabled)")


func test_add_disabled_node() -> void:
	# Create first node (enabled)
	var node1: Node3D = _create_test_node(Vector3(0, 0, 0), 100.0, 4, true)
	
	# Create second node as disabled
	var parent2: Node3D = Node3D.new()
	parent2.global_position = Vector3(75, 0, 0)
	var node2: PowerNode = PowerNode.new()
	node2.max_connection_distance = 100.0
	node2.max_connections = 4
	node2.is_enabled = false  # Start disabled
	parent2.add_child(node2)
	add_child_autofree(parent2)
	_test_nodes.append(parent2)
	
	# Disable node1 before adding node2
	node1.is_enabled = false
	PowerGraphManager.add_node(node2)
	
	# Verify edge is disabled when both nodes are disabled
	assert_false(node1.is_enabled, "Node1 should be disabled")
	assert_false(node2.is_enabled, "Node2 should be disabled")
	assert_false(PowerGraphManager.is_edge_enabled(node1, node2), "Edge should be disabled")
	
	# Enable node2 and verify edge becomes enabled
	PowerGraphManager.enable_node(node2)
	assert_false(node1.is_enabled, "Node1 should still be disabled")
	assert_true(node2.is_enabled, "Node2 should be enabled")
	assert_true(PowerGraphManager.is_edge_enabled(node1, node2), "Edge should be enabled now")
