extends GutTest
## Power graph tests against PowerGraphManager (autoload) and PowerNode / PowerSource / PowerUser.

const TEST_RANGE: float = 100.0

var _scene_root: Node3D = null


class TestStructure extends Node3D:
	var building_type: String = "power_node"


## Minimal stand-in for ConstructionComponent so get_node_type() sees an unbuilt structure.
class FakeConstruction extends Node:
	var is_built: bool = false

	func get_progress() -> float:
		return 0.0


func before_each() -> void:
	PowerGraphManager.clear()
	_scene_root = Node3D.new()
	add_child_autofree(_scene_root)


func after_each() -> void:
	PowerGraphManager.clear()


func _await_graph() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _make_structure(pos: Vector3) -> TestStructure:
	var s: TestStructure = TestStructure.new()
	s.position = pos
	_scene_root.add_child(s)
	return s


func _add_power_node(
	struct: Node3D,
	max_dist: float = TEST_RANGE,
	max_conns: int = 4,
	enabled: bool = true,
	skip_auto: bool = false
) -> PowerNode:
	var pn: PowerNode = PowerNode.new()
	pn.max_connection_distance = max_dist
	pn.max_connections = max_conns
	pn.is_enabled = enabled
	pn.skip_auto_connect_on_register = skip_auto
	struct.add_child(pn)
	return pn


func _graph_size() -> int:
	return PowerGraphManager.get_graph().size()


func test_adds_and_removes_nodes() -> void:
	var n0: int = _graph_size()
	var st: TestStructure = _make_structure(Vector3.ZERO)
	var pn: PowerNode = _add_power_node(st)
	await _await_graph()
	assert_eq(_graph_size(), n0 + 1, "graph should register PowerNode")
	assert_not_null(PowerGraphManager.find_subgraph_for_node(pn), "subgraph should exist")
	st.queue_free()
	await _await_graph()
	assert_eq(_graph_size(), n0, "graph should remove node when structure freed")


func test_adds_and_removes_sources() -> void:
	var n0: int = _graph_size()
	var st: TestStructure = _make_structure(Vector3.ZERO)
	var pn: PowerNode = _add_power_node(st)
	var src: PowerSource = PowerSource.new()
	src.max_storage = 100.0
	pn.add_child(src)
	await _await_graph()
	assert_eq(PowerGraphManager.get_power_capacity(), 100.0, "capacity should include source")
	st.queue_free()
	await _await_graph()
	assert_eq(PowerGraphManager.get_power_capacity(), 0.0, "capacity 0 after structure freed")
	assert_eq(_graph_size(), n0, "graph empty after free")


func test_connects_nodes_within_range() -> void:
	var s1: TestStructure = _make_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_structure(Vector3(75, 0, 0))
	var s3: TestStructure = _make_structure(Vector3(150, 0, 0))
	var p1: PowerNode = _add_power_node(s1)
	var p2: PowerNode = _add_power_node(s2)
	var p3: PowerNode = _add_power_node(s3)
	await _await_graph()
	assert_eq(p1.connected_nodes.size(), 1, "end node has 1 neighbor")
	assert_eq(p2.connected_nodes.size(), 2, "middle node has 2 neighbors")
	assert_eq(p3.connected_nodes.size(), 1, "end node has 1 neighbor")
	assert_true(p1.connected_nodes.has(p2), "p1–p2")
	var c2: Array[PowerNode] = p2.connected_nodes
	assert_true(c2.has(p1) and c2.has(p3), "p2 links p1 and p3")


func test_connects_nodes_within_range_asymmetric_max_connections() -> void:
	var s1: TestStructure = _make_structure(Vector3.ZERO)
	var s2: TestStructure = _make_structure(Vector3(50, 0, 0))
	var p1: PowerNode = _add_power_node(s1, TEST_RANGE, 20, true)
	var p2: PowerNode = _add_power_node(s2, TEST_RANGE, 1, true)
	await _await_graph()
	assert_eq(p1.connected_nodes.size(), 1)
	assert_eq(p2.connected_nodes.size(), 1)
	assert_true(p1.connected_nodes.has(p2) and p2.connected_nodes.has(p1))


func test_does_not_connect_nodes_out_of_range() -> void:
	var s1: TestStructure = _make_structure(Vector3.ZERO)
	var s2: TestStructure = _make_structure(Vector3(200, 0, 0))
	_add_power_node(s1, 100.0, 4, true)
	_add_power_node(s2, 100.0, 4, true)
	await _await_graph()
	var p1: PowerNode = s1.get_child(0) as PowerNode
	var p2: PowerNode = s2.get_child(0) as PowerNode
	assert_eq(p1.connected_nodes.size(), 0)
	assert_eq(p2.connected_nodes.size(), 0)


func test_finds_nearest_source_node() -> void:
	var s1: TestStructure = _make_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_structure(Vector3(75, 0, 0))
	var s3: TestStructure = _make_structure(Vector3(150, 0, 0))
	var p1: PowerNode = _add_power_node(s1)
	var p2: PowerNode = _add_power_node(s2)
	var p3: PowerNode = _add_power_node(s3)
	var src: PowerSource = PowerSource.new()
	src.max_storage = 100.0
	p3.add_child(src)
	await _await_graph()
	var result: Dictionary = PowerGraphManager.find_nearest_source_node(p1)
	var source_node: Node3D = result.get("source_node") as Node3D
	assert_eq(source_node, p3, "nearest source should be p3")
	var path: Array = result.get("path", [])
	assert_eq(path.size(), 3, "path length")
	assert_eq(path[0], p1)
	assert_eq(path[1], p2)
	assert_eq(path[2], p3)


func test_draw_power_returns_zero_when_subgraph_storage_empty() -> void:
	## At zero stored power, draw_power_for_user should return immediately without BFS (FPS fix).
	var s1: TestStructure = _make_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_structure(Vector3(75, 0, 0))
	var p1: PowerNode = _add_power_node(s1)
	var p2: PowerNode = _add_power_node(s2)
	var src: PowerSource = PowerSource.new()
	src.max_storage = 100.0
	src.current_storage = 0.0
	p1.add_child(src)
	var pu: PowerUser = PowerUser.new()
	pu.is_construction_user = false
	p2.add_child(pu)
	await _await_graph()
	var drawn: float = PowerGraphManager.draw_power_for_user(pu, 10.0)
	assert_eq(drawn, 0.0, "no stored power means nothing to draw")


func test_construction_shadow_links_to_neighbor_main_not_peer_shadow() -> void:
	## Shadow mirrors topology but links to the neighbor's main PowerNode. Peer mains are disabled while
	## building, so there is no conducting edge to skip ahead of upstream construction.
	var s1: TestStructure = _make_structure(Vector3.ZERO)
	var s2: TestStructure = _make_structure(Vector3(10, 0, 0))
	var pn1: PowerNode = _add_power_node(s1, TEST_RANGE, 4, true)
	var pn2: PowerNode = _add_power_node(s2, TEST_RANGE, 4, true)
	await _await_graph()
	pn1.is_enabled = false
	pn2.is_enabled = false
	var c1: PowerNode = PowerNode.new()
	c1.skip_auto_connect_on_register = true
	c1.max_connection_distance = TEST_RANGE
	c1.max_connections = 4
	c1.is_enabled = true
	s1.add_child(c1)
	var c2: PowerNode = PowerNode.new()
	c2.skip_auto_connect_on_register = true
	c2.max_connection_distance = TEST_RANGE
	c2.max_connections = 4
	c2.is_enabled = true
	s2.add_child(c2)
	await _await_graph()
	PowerGraphManager.sync_construction_shadow_edges(pn1, c1)
	PowerGraphManager.sync_construction_shadow_edges(pn2, c2)
	var g: Dictionary = PowerGraphManager.get_graph()
	assert_true(g[c1].has(pn2), "shadow should link to neighbor main (non-conducting until built)")
	assert_false(g[c1].has(c2), "must not create peer shadow–shadow edges that bypass disabled mains")


func test_construction_shadow_keeps_peer_and_powered_links_when_main_has_two_neighbors() -> void:
	## Mid node links to solar (powered) and a peer under construction; shadow mirrors both mains.
	var s_solar: TestStructure = _make_structure(Vector3.ZERO)
	var pn_solar: PowerNode = _add_power_node(s_solar, TEST_RANGE, 4, true)
	var src: PowerSource = PowerSource.new()
	src.max_storage = 100.0
	src.current_storage = 80.0
	pn_solar.add_child(src)
	var s_mid: TestStructure = _make_structure(Vector3(40, 0, 0))
	var pn_mid: PowerNode = _add_power_node(s_mid, TEST_RANGE, 4, true)
	var s_peer: TestStructure = _make_structure(Vector3(80, 0, 0))
	var pn_peer: PowerNode = _add_power_node(s_peer, TEST_RANGE, 4, true)
	await _await_graph()
	pn_peer.is_enabled = false
	var c_peer: PowerNode = PowerNode.new()
	c_peer.skip_auto_connect_on_register = true
	c_peer.max_connection_distance = TEST_RANGE
	c_peer.max_connections = 4
	c_peer.is_enabled = true
	s_peer.add_child(c_peer)
	var c_mid: PowerNode = PowerNode.new()
	c_mid.skip_auto_connect_on_register = true
	c_mid.max_connection_distance = TEST_RANGE
	c_mid.max_connections = 4
	c_mid.is_enabled = true
	s_mid.add_child(c_mid)
	await _await_graph()
	PowerGraphManager.sync_construction_shadow_edges(pn_peer, c_peer)
	PowerGraphManager.sync_construction_shadow_edges(pn_mid, c_mid)
	var g: Dictionary = PowerGraphManager.get_graph()
	assert_true(g[c_mid].has(pn_solar), "mid shadow should reach powered solar main")
	assert_true(g[c_mid].has(pn_peer), "mid shadow should mirror link to peer main (disabled until built)")
	assert_false(g[c_mid].has(c_peer), "must not link to peer construction shadow")


func test_construction_chain_builds_in_placement_order_not_parallel() -> void:
	## Place a source then three relays in a line (no skip-to-source for downstream). Only the first
	## relay should receive construction power until it finishes; peer shadow bridges would break this.
	## Use real connection range (15m): relays at 10, 25, 40 so only R1 is in range of solar; R2/R3 chain.
	const CHAIN_RANGE: float = PowerNode.CONNECTION_RANGE
	var s_solar: TestStructure = _make_structure(Vector3.ZERO)
	var pn_solar: PowerNode = _add_power_node(s_solar, CHAIN_RANGE, 4, true)
	var src: PowerSource = PowerSource.new()
	src.max_storage = 1000.0
	src.current_storage = 1000.0
	pn_solar.add_child(src)
	await _await_graph()
	var relays: Array[Dictionary] = []
	var xs: Array[float] = [10.0, 25.0, 40.0]
	for i in range(3):
		var st: TestStructure = _make_structure(Vector3(xs[i], 0, 0))
		var pn: PowerNode = _add_power_node(st, CHAIN_RANGE, 4, true)
		var cc: ConstructionComponent = ConstructionComponent.new()
		cc.construction_time = 500.0
		cc.requires_power = true
		cc.build_power_cost = 10.0
		st.add_child(cc)
		relays.append({"cc": cc})
	await _await_graph()
	for _i in range(90):
		await get_tree().process_frame
	var cc0: ConstructionComponent = relays[0]["cc"] as ConstructionComponent
	var cc1: ConstructionComponent = relays[1]["cc"] as ConstructionComponent
	var cc2: ConstructionComponent = relays[2]["cc"] as ConstructionComponent
	assert_gt(cc0.build_progress, 0.0, "first relay in chain should receive build power from the grid")
	assert_eq(cc1.build_progress, 0.0, "second relay must not build in parallel with the first")
	assert_eq(cc2.build_progress, 0.0, "third relay must not build in parallel with upstream relays")


func test_construction_shadow_edge_mirrors_main_without_extra_neighbor_slot() -> void:
	var st: TestStructure = _make_structure(Vector3.ZERO)
	var relay_st: TestStructure = _make_structure(Vector3(40, 0, 0))
	var main_pn: PowerNode = _add_power_node(st, TEST_RANGE, 1, false)
	var relay_pn: PowerNode = _add_power_node(relay_st, TEST_RANGE, 4, true)
	await _await_graph()
	assert_eq(main_pn.connected_nodes.size(), 1)
	assert_eq(relay_pn.connected_nodes.size(), 1)
	assert_true(main_pn.connected_nodes.has(relay_pn))
	var cons: PowerNode = PowerNode.new()
	cons.skip_auto_connect_on_register = true
	cons.max_connection_distance = TEST_RANGE
	cons.max_connections = 1
	cons.is_enabled = true
	st.add_child(cons)
	await _await_graph()
	PowerGraphManager.sync_construction_shadow_edges(main_pn, cons)
	assert_eq(relay_pn.connected_nodes.size(), 1, "relay still only counts main")
	assert_eq(cons.connected_nodes.size(), 1)
	assert_true(cons.connected_nodes.has(relay_pn))
	assert_true(PowerGraphManager.get_graph().has(cons))
	assert_true(PowerGraphManager.get_graph()[cons].has(relay_pn))


func test_add_node_connects_to_relay_under_construction_without_power() -> void:
	## Main power hook must stay a valid link target while building (disabled = no relay yet, but edges exist).
	var s_existing: TestStructure = _make_structure(Vector3.ZERO)
	var _fc: FakeConstruction = FakeConstruction.new()
	s_existing.add_child(_fc)
	var pn_existing: PowerNode = _add_power_node(s_existing, TEST_RANGE, 4, false)
	pn_existing.invalidate_type_cache()
	assert_eq(int(pn_existing.get_node_type()), int(PowerNode.NodeType.NODE))
	assert_true(pn_existing.is_valid_connection_target())

	await _await_graph()

	var s_new: TestStructure = _make_structure(Vector3(40, 0, 0))
	var pn_new: PowerNode = _add_power_node(s_new, TEST_RANGE, 4, true)
	await _await_graph()

	assert_true(pn_new.connected_nodes.has(pn_existing), "should connect even without powered subgraph")


func test_relay_placed_after_isolated_leaf_connects() -> void:
	## Leaf placed alone, then relay nearby: relay must link to the leaf so it can receive power/build.
	## Regression: linked leaves were never valid targets, so isolated leaves stayed disconnected forever.
	var s_leaf: TestStructure = _make_structure(Vector3.ZERO)
	var pn_leaf: PowerNode = _add_power_node(s_leaf, TEST_RANGE, 4, true)
	var pu: PowerUser = PowerUser.new()
	pu.is_construction_user = false
	pn_leaf.add_child(pu)
	pn_leaf.invalidate_type_cache()
	assert_eq(int(pn_leaf.get_node_type()), int(PowerNode.NodeType.LEAF))

	await _await_graph()
	assert_eq(pn_leaf.connected_nodes.size(), 0, "leaf starts with no neighbors")

	var s_relay: TestStructure = _make_structure(Vector3(10, 0, 0))
	var pn_relay: PowerNode = _add_power_node(s_relay, TEST_RANGE, 4, true)
	await _await_graph()

	assert_eq(pn_relay.connected_nodes.size(), 1, "relay should connect to the isolated leaf")
	assert_eq(pn_leaf.connected_nodes.size(), 1, "leaf should connect to the relay")
	assert_true(pn_relay.connected_nodes.has(pn_leaf) and pn_leaf.connected_nodes.has(pn_relay))


func test_add_node_skips_leaf_prefers_distant_relay() -> void:
	## Leaf (consumer) is closer than the powered relay; new node must not waste a link on the leaf.
	var s_leaf: TestStructure = _make_structure(Vector3.ZERO)
	var pn_leaf: PowerNode = _add_power_node(s_leaf, TEST_RANGE, 4, true)
	var pu: PowerUser = PowerUser.new()
	pu.is_construction_user = false
	pn_leaf.add_child(pu)
	pn_leaf.invalidate_type_cache()

	var s_relay: TestStructure = _make_structure(Vector3(50, 0, 0))
	var pn_relay: PowerNode = _add_power_node(s_relay, TEST_RANGE, 4, true)
	var src: PowerSource = PowerSource.new()
	src.max_storage = 100.0
	src.current_storage = 50.0
	pn_relay.add_child(src)
	pn_relay.invalidate_type_cache()

	await _await_graph()

	var s_new: TestStructure = _make_structure(Vector3(10, 0, 0))
	var pn_new: PowerNode = _add_power_node(s_new, TEST_RANGE, 4, true)
	await _await_graph()

	assert_true(pn_new.connected_nodes.has(pn_relay), "should connect to relay, not skip for distance")
	assert_false(pn_new.connected_nodes.has(pn_leaf), "must not connect to leaf consumer")


func test_is_edge_enabled_requires_both_endpoints_enabled() -> void:
	var s1: TestStructure = _make_structure(Vector3.ZERO)
	var s2: TestStructure = _make_structure(Vector3(30, 0, 0))
	var p1: PowerNode = _add_power_node(s1, TEST_RANGE, 4, true)
	var p2: PowerNode = _add_power_node(s2, TEST_RANGE, 4, true)
	await _await_graph()
	assert_true(PowerGraphManager.is_edge_enabled(p1, p2), "both enabled")
	p1.is_enabled = false
	await _await_graph()
	assert_false(PowerGraphManager.is_edge_enabled(p1, p2), "main disabled blocks edge power")
