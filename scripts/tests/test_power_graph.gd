extends GutTest
## Power graph tests - ECS implementation.
## Ported from Cosmos-Old Dart tests; same assertions, ECS-based setup.

# Preloaded resources (load once, reuse)
const _O_POWER_GRAPH: Script = preload("res://scripts/observers/o_power_graph.gd")
const _O_CONSTRUCTION_BUILT: Script = preload("res://scripts/observers/o_construction_built.gd")
const _O_CONSTRUCTION_POWER_NODE: Script = preload("res://scripts/observers/o_construction_power_node.gd")
const _O_POWER_EDGE_BLOCKED: Script = preload("res://scripts/observers/o_power_edge_blocked.gd")
const _POWER_GENERATOR_SYSTEM: Script = preload("res://scripts/ecs/systems/power_generator_system.gd")
const _POWER_EDGE_VISUAL_SYSTEM: Script = preload("res://scripts/ecs/systems/power_edge_visual_system.gd")
const _TEST_SCENE: PackedScene = preload("res://addons/gecs/tests/test_scene.tscn")
const _ENTITY: GDScript = preload("res://addons/gecs/ecs/entity.gd")
const _C_STRUCTURE: Script = preload("res://scripts/ecs/components/c_structure.gd")
const _C_POWER_NODE: Script = preload("res://scripts/ecs/components/c_power_node.gd")
const _C_TRANSFORM3D: Script = preload("res://scripts/ecs/components/c_transform3d.gd")
const _C_CONSTRUCTION: Script = preload("res://scripts/ecs/components/c_construction.gd")
const _C_POWER_SOURCE: Script = preload("res://scripts/ecs/components/c_power_source.gd")
const _C_POWER_USER: Script = preload("res://scripts/ecs/components/c_power_user.gd")
const _C_POWER_GENERATOR: Script = preload("res://scripts/ecs/components/c_power_generator.gd")
const _C_POWER_EDGE: Script = preload("res://scripts/ecs/components/c_power_edge.gd")
const _PowerEdgeLineNodeScript: GDScript = preload("res://scripts/ecs/power_edge_line_node.gd")

var _world: Node = null
var _scene_root: Node3D = null


func before_each() -> void:
	_scene_root = Node3D.new()
	add_child_autofree(_scene_root)
	_world = _create_ecs_world()
	ECS.world = _world
	if GameWorld:
		var lines_parent: Node3D = Node3D.new()
		_scene_root.add_child(lines_parent)
		GameWorld.set_world(null, lines_parent)
	# Add power graph observers and systems
	if _O_POWER_GRAPH:
		_world.add_observer(_O_POWER_GRAPH.new())
	if _O_CONSTRUCTION_BUILT:
		_world.add_observer(_O_CONSTRUCTION_BUILT.new())
	if _O_CONSTRUCTION_POWER_NODE:
		_world.add_observer(_O_CONSTRUCTION_POWER_NODE.new())
	if _O_POWER_EDGE_BLOCKED:
		_world.add_observer(_O_POWER_EDGE_BLOCKED.new())
	var power_gen: Script = _POWER_GENERATOR_SYSTEM
	var power_edge_visual: Script = _POWER_EDGE_VISUAL_SYSTEM
	if power_gen:
		_world.add_system(power_gen.new(), true)
	if power_edge_visual:
		_world.add_system(power_edge_visual.new(), true)
	if _world.has_method("finalize_system_setup"):
		_world.finalize_system_setup()


func after_each() -> void:
	if _world and _world.has_method("purge"):
		_world.purge(false)
	if ECS:
		ECS.world = null


func _create_ecs_world() -> Node:
	var root: Node = _TEST_SCENE.instantiate()
	add_child_autofree(root)
	return root.get_node("World")


## Node3D with building_type property for structure compatibility
class TestStructure extends Node3D:
	var building_type: String = "power_node"
	func can_accept_more_connections() -> bool:
		return true


func _make_test_structure(pos: Vector3, bt: String = "power_node") -> TestStructure:
	var s: TestStructure = TestStructure.new()
	s.building_type = bt
	s.position = pos
	_scene_root.add_child(s)
	return s


## Create entity with structure_node, C_PowerNode, etc. Add to world.
func _add_power_entity(struct: Node3D, components_override: Array = []) -> Node:
	var entity: Node = _ENTITY.new()
	var c_struct: Resource = _C_STRUCTURE.new() as Resource
	c_struct.set("structure_node", struct)
	c_struct.set("building_type", struct.get("building_type") if struct.get("building_type") else "power_node")
	var c_node: Resource = null
	for c in components_override:
		if c.get_script() == _C_POWER_NODE:
			c_node = c
			break
	if c_node == null:
		c_node = _C_POWER_NODE.new() as Resource
		c_node.set("structure_node", struct)
		c_node.set("max_connection_distance", 100.0)
		c_node.set("max_connections", 4)
		c_node.set("is_enabled", true)
	else:
		c_node.set("structure_node", struct)
	var c_transform: Resource = _C_TRANSFORM3D.new() as Resource
	c_transform.set("position", struct.position)
	# Built structures don't have C_Construction (removed on completion). Omit to match real gameplay.
	var comps: Array = [c_struct, c_node, c_transform]
	for c in components_override:
		if c.get_script() != _C_POWER_NODE:
			comps.append(c)
	_world.add_entity(entity, comps, false)
	# Re-set structure_node after add (GECS may clear refs)
	var stored_struct: Resource = entity.get_component(_C_STRUCTURE)
	if stored_struct:
		stored_struct.set("structure_node", struct)
	for comp_script in [_C_POWER_NODE, _C_POWER_SOURCE, _C_POWER_USER, _C_POWER_GENERATOR]:
		var c: Resource = entity.get_component(comp_script as Script)
		if c:
			c.set("structure_node", struct)
	return entity


func _run_power_systems(delta: float = 0.016) -> void:
	# Refresh graph so tests see current state (observers use call_deferred; we sync here)
	if PowerGraph and ECS and ECS.world:
		PowerGraph.refresh_graph(ECS.world)
	if ECS and ECS.world:
		ECS.process(delta)


func _get_entity_for_struct(struct: Node3D) -> Node:
	for e in _world.query.with_all([_C_STRUCTURE]).execute():
		var cs: Resource = e.get_component(_C_STRUCTURE)
		if cs and cs.get("structure_node") == struct:
			return e
	return null


func _get_connected_structure_nodes(entity: Node) -> Array:
	var c_node: Resource = entity.get_component(_C_POWER_NODE)
	if not c_node:
		return []
	var ids: Array = c_node.get("connected_entity_ids")
	var out: Array = []
	for eid in ids:
		var entities: Array = _world.query.with_all([_C_STRUCTURE]).execute()
		for e in entities:
			if e.get_instance_id() == eid:
				var cs: Resource = e.get_component(_C_STRUCTURE)
				if cs and cs.get("structure_node"):
					out.append(cs.get("structure_node"))
				break
	return out


# ---- Component Registration ----

func test_adds_and_removes_nodes() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_power_entity(struct)
	_run_power_systems()
	await get_tree().process_frame
	_run_power_systems()
	var sg = PowerGraph.find_subgraph_for_node(struct)
	assert_not_null(sg, "find_subgraph_for_node should return non-null after add")
	_world.remove_entity(ent)
	await get_tree().process_frame  # Let Observer's call_deferred run
	_run_power_systems()
	sg = PowerGraph.find_subgraph_for_node(struct)
	assert_null(sg, "find_subgraph_for_node should return null after remove")


func test_adds_and_removes_sources() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var c_src: Resource = _C_POWER_SOURCE.new() as Resource
	c_src.set("max_storage", 100.0)
	_add_power_entity(struct, [c_src])
	_run_power_systems()
	assert_eq(PowerGraph.get_power_capacity(), 100.0, "power capacity should be 100")
	_world.remove_entity(_world.entities[0])
	_run_power_systems()
	assert_eq(PowerGraph.get_power_capacity(), 0.0, "power capacity should be 0 after remove")


# ---- Graph Structure ----

func test_connects_nodes_within_range() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(75, 0, 0))
	var s3: TestStructure = _make_test_structure(Vector3(150, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	_add_power_entity(s3)
	_run_power_systems()
	var entities: Array = _world.query.with_all([_C_POWER_NODE]).execute()
	var e1: Node = null
	var e2: Node = null
	var e3: Node = null
	for e in entities:
		var cs: Resource = e.get_component(_C_STRUCTURE)
		if cs and cs.get("structure_node") == s1:
			e1 = e
		elif cs and cs.get("structure_node") == s2:
			e2 = e
		elif cs and cs.get("structure_node") == s3:
			e3 = e
	assert_not_null(e1)
	assert_not_null(e2)
	assert_not_null(e3)
	var cn1: Resource = e1.get_component(_C_POWER_NODE)
	var cn2: Resource = e2.get_component(_C_POWER_NODE)
	var cn3: Resource = e3.get_component(_C_POWER_NODE)
	assert_eq(cn1.get("connected_entity_ids").size(), 1, "node1 should have 1 connection")
	assert_eq(cn2.get("connected_entity_ids").size(), 2, "node2 should have 2 connections")
	assert_eq(cn3.get("connected_entity_ids").size(), 1, "node3 should have 1 connection")
	var conn1: Array = _get_connected_structure_nodes(e1)
	assert_true(conn1.has(s2), "node1 should connect to node2")
	var conn2: Array = _get_connected_structure_nodes(e2)
	assert_true(conn2.has(s1) and conn2.has(s3), "node2 should connect to node1 and node3")
	var conn3: Array = _get_connected_structure_nodes(e3)
	assert_true(conn3.has(s2), "node3 should connect to node2")


func test_connects_nodes_within_range_asymmetric_max_connections() -> void:
	# 2 nodes with asymmetric max_connections (20 and 1) - both can connect
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(50, 0, 0))
	var cn1: Resource = _C_POWER_NODE.new() as Resource
	cn1.set("structure_node", s1)
	cn1.set("max_connection_distance", 100.0)
	cn1.set("max_connections", 20)
	cn1.set("is_enabled", true)
	var cn2: Resource = _C_POWER_NODE.new() as Resource
	cn2.set("structure_node", s2)
	cn2.set("max_connection_distance", 100.0)
	cn2.set("max_connections", 1)
	cn2.set("is_enabled", true)
	var ent1: Node = _add_power_entity(s1, [cn1])
	var ent2: Node = _add_power_entity(s2, [cn2])
	_run_power_systems()
	var c1: Resource = ent1.get_component(_C_POWER_NODE)
	var c2: Resource = ent2.get_component(_C_POWER_NODE)
	assert_eq(c1.get("connected_entity_ids").size(), 1, "node1 should have 1 connection")
	assert_eq(c2.get("connected_entity_ids").size(), 1, "node2 should have 1 connection")
	assert_true(_get_connected_structure_nodes(ent1).has(s2), "node1 should connect to node2")
	assert_true(_get_connected_structure_nodes(ent2).has(s1), "node2 should connect to node1")


func test_does_not_connect_nodes_out_of_range() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(200, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	_run_power_systems()
	var entities: Array = _world.query.with_all([_C_POWER_NODE]).execute()
	var cn1: Resource = null
	var cn2: Resource = null
	for e in entities:
		var cs: Resource = e.get_component(_C_STRUCTURE)
		if cs and cs.get("structure_node") == s1:
			cn1 = e.get_component(_C_POWER_NODE)
		elif cs and cs.get("structure_node") == s2:
			cn2 = e.get_component(_C_POWER_NODE)
	assert_true(cn1.get("connected_entity_ids").is_empty(), "node1 should have no connections")
	assert_true(cn2.get("connected_entity_ids").is_empty(), "node2 should have no connections")


# ---- Edge Entities & Visualization ----

func test_connected_nodes_create_c_power_edge_entities() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	_run_power_systems()

	var edge_entities: Array = _world.query.with_all([_C_POWER_EDGE]).execute()
	assert_gte(edge_entities.size(), 1, "Connected nodes should create at least one C_PowerEdge entity")
	var c_edge: Resource = edge_entities[0].get_component(_C_POWER_EDGE)
	assert_not_null(c_edge, "Edge entity should have C_PowerEdge component")
	assert_true(c_edge.get("entity_id_a") > 0 or c_edge.get("entity_id_b") > 0, "Edge should reference node ids")


func test_edge_line_nodes_added_to_power_lines_parent() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(8, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	_run_power_systems()

	if not GameWorld or not GameWorld.power_lines_parent:
		pass_test("GameWorld.power_lines_parent not set, skip line node check")
		return

	var line_count: int = 0
	for child in GameWorld.power_lines_parent.get_children():
		if child.get_script() == _PowerEdgeLineNodeScript:
			line_count += 1
	assert_gte(line_count, 1, "PowerEdgeLineNode should be added to power_lines_parent for visualization")


func test_edge_entity_has_line_node_reference() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(6, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	_run_power_systems()

	var edge_entities: Array = _world.query.with_all([_C_POWER_EDGE]).execute()
	assert_gte(edge_entities.size(), 1)
	var c_edge: Resource = edge_entities[0].get_component(_C_POWER_EDGE)
	var line_node: Node = c_edge.get("line_node")
	assert_not_null(line_node, "C_PowerEdge should reference line_node for visual updates")
	assert_true(is_instance_valid(line_node), "line_node should be valid")


func test_edge_removed_when_node_disconnected() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var ent1: Node = _add_power_entity(s1)
	var ent2: Node = _add_power_entity(s2)
	_run_power_systems()

	var edge_before: Array = _world.query.with_all([_C_POWER_EDGE]).execute()
	assert_gte(edge_before.size(), 1, "Should have edge when connected")

	_world.remove_entity(ent2)
	await get_tree().process_frame
	_run_power_systems()

	var edge_after: Array = _world.query.with_all([_C_POWER_EDGE]).execute()
	assert_eq(edge_after.size(), 0, "Edge entity should be removed when node disconnected")


func test_leaf_node_connects_to_closest_enabled_node() -> void:
	# Layout: s1 at 0, s2 at 20, leaf at 35. Leaf is 15 from s2, 35 from s1.
	# Leaf (max_connections=1) should connect to s2 (closer), not s1 (farther).
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(20, 0, 0))
	var s_leaf: TestStructure = _make_test_structure(Vector3(35, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	var c_leaf: Resource = _C_POWER_NODE.new() as Resource
	c_leaf.set("structure_node", s_leaf)
	c_leaf.set("max_connection_distance", 100.0)
	c_leaf.set("max_connections", 1)
	c_leaf.set("is_enabled", true)
	var ent_leaf: Node = _add_power_entity(s_leaf, [c_leaf])
	_run_power_systems()
	var leaf_conns: Array = _get_connected_structure_nodes(ent_leaf)
	assert_eq(leaf_conns.size(), 1, "leaf should have exactly one connection")
	assert_true(leaf_conns.has(s2), "leaf should connect to closer node s2, not farther s1")


# # ---- Pathfinding ----

func test_finds_nearest_source_node() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(75, 0, 0))
	var s3: TestStructure = _make_test_structure(Vector3(150, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	var c_src: Resource = _C_POWER_SOURCE.new() as Resource
	c_src.set("max_storage", 100.0)
	_add_power_entity(s3, [c_src])
	_run_power_systems()
	var user_ent: Node = _get_entity_for_struct(s1)
	assert_not_null(user_ent, "user entity exists")
	var result: Dictionary = PowerGraph.find_nearest_source_entity(user_ent)
	var src_ent: Node = result.get("source_entity")
	if src_ent == null:
		fail_test("should find a source entity")
		return
	var src_cs: Resource = src_ent.get_component(_C_STRUCTURE)
	assert_eq(src_cs.get("structure_node"), s3, "source node should be s3 (has source)")
	var path: Array = result.get("path", [])
	var path_structs: Array = []
	for pe in path:
		assert_not_null(pe, "path must not contain null entities")
		var pcs: Resource = pe.get_component(_C_STRUCTURE)
		if pcs and pcs.get("structure_node"):
			path_structs.append(pcs.get("structure_node"))
	assert_eq(path_structs, [s1, s2, s3], "path should be start->middle->source")


# # ---- Producer "always online" (Bug: solar panels showing offline) ----

func test_producers_with_power_source_are_always_powered() -> void:
	# Entities with C_PowerSource/C_PowerGenerator produce power - should never show "offline"
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var c_src: Resource = _C_POWER_SOURCE.new() as Resource
	c_src.set("max_storage", 100.0)
	c_src.set("current_storage", 0.0)
	var c_gen: Resource = _C_POWER_GENERATOR.new() as Resource
	c_gen.set("power_output", 10.0)
	c_gen.set("is_active", true)
	var ent: Node = _add_power_entity(s1, [c_src, c_gen])
	_run_power_systems()
	assert_true(PowerGraph.is_entity_powered(ent), "Producer (source+generator) should always be powered")


# ---- Multi-layer connections (Bug: beyond first layer fails) ----

func test_user_draws_power_through_two_relay_hops() -> void:
	# Chain: user(0) - relay(5) - relay(10) - source(15). User must draw through 2 relays.
	var s_user: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s_relay1: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var s_relay2: TestStructure = _make_test_structure(Vector3(10, 0, 0))
	var s_src: TestStructure = _make_test_structure(Vector3(15, 0, 0))
	var c_user: Resource = _C_POWER_USER.new() as Resource
	c_user.set("use_power_cost", 20.0)
	c_user.set("buffer_capacity", 100.0)
	var c_src: Resource = _C_POWER_SOURCE.new() as Resource
	c_src.set("max_storage", 100.0)
	c_src.set("current_storage", 50.0)
	_add_power_entity(s_user, [c_user])
	_add_power_entity(s_relay1, [])  # Pure relay
	_add_power_entity(s_relay2, [])  # Pure relay
	_add_power_entity(s_src, [c_src])
	_run_power_systems()
	var user_ent: Node = _get_entity_for_struct(s_user)
	var drawn: float = PowerGraph.draw_power_for_user_entity(user_ent, 20.0)
	assert_eq(drawn, 20.0, "User should draw power through 2 relay hops to source")
	var ent_src: Node = _get_entity_for_struct(s_src)
	var c_src_actual: Resource = ent_src.get_component(_C_POWER_SOURCE)
	assert_eq(c_src_actual.get("current_storage"), 30.0, "Source should have 30 left after 20 drawn")


func test_find_subgraph_includes_all_nodes_in_chain() -> void:
	# 4 nodes in chain - subgraph should include all when querying from any
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var s3: TestStructure = _make_test_structure(Vector3(10, 0, 0))
	var s4: TestStructure = _make_test_structure(Vector3(15, 0, 0))
	var c_src: Resource = _C_POWER_SOURCE.new() as Resource
	c_src.set("max_storage", 100.0)
	c_src.set("current_storage", 50.0)
	_add_power_entity(s1, [])
	_add_power_entity(s2, [])
	_add_power_entity(s3, [])
	_add_power_entity(s4, [c_src])
	_run_power_systems()
	var sg: Variant = PowerGraph.find_subgraph_for_node(s1)
	assert_not_null(sg, "Subgraph should exist")
	assert_eq(sg.nodes.size(), 4, "Subgraph should include all 4 nodes in chain")
	assert_eq(sg.sources.size(), 1, "Subgraph should have 1 source")


# ---- Power Distribution ----

func test_handles_individual_power_sources_generator() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var c_src: Resource = _C_POWER_SOURCE.new() as Resource
	c_src.set("max_storage", 100.0)
	c_src.set("current_storage", 25.0)
	var c_gen: Resource = _C_POWER_GENERATOR.new() as Resource
	c_gen.set("power_output", 50.0)
	c_gen.set("is_active", true)
	_add_power_entity(s1, [c_src, c_gen])
	_run_power_systems(1.0)
	var ent: Node = _get_entity_for_struct(s1)
	var c_src_actual: Resource = ent.get_component(_C_POWER_SOURCE)
	assert_eq(c_src_actual.get("current_storage"), 75.0, "after 1s gen: storage 25->75")
	_run_power_systems(1.0)
	c_src_actual = ent.get_component(_C_POWER_SOURCE)
	assert_eq(c_src_actual.get("current_storage"), 100.0, "after 2s gen: storage 75->100")


func test_handles_individual_power_sources_user_draw() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(75, 0, 0))
	var s3: TestStructure = _make_test_structure(Vector3(150, 0, 0))
	var src1: Resource = _C_POWER_SOURCE.new() as Resource
	src1.set("max_storage", 100.0)
	src1.set("current_storage", 25.0)
	var src2: Resource = _C_POWER_SOURCE.new() as Resource
	src2.set("max_storage", 100.0)
	src2.set("current_storage", 75.0)
	var c_user: Resource = _C_POWER_USER.new() as Resource
	c_user.set("use_power_cost", 50.0)
	c_user.set("buffer_capacity", 100.0)

	_add_power_entity(s1, [c_user])
	_add_power_entity(s2, [src1])
	_add_power_entity(s3, [src2])

	var ent2: Node = _get_entity_for_struct(s2)
	var ent3: Node = _get_entity_for_struct(s3)
	var c_src1: Resource = ent2.get_component(_C_POWER_SOURCE)
	var c_src2: Resource = ent3.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 25.0, "initial source1")
	assert_eq(c_src2.get("current_storage"), 75.0, "initial source2")

	_run_power_systems()

	assert_eq(c_src1.get("current_storage"), 25.0, "initial source1")
	assert_eq(c_src2.get("current_storage"), 75.0, "initial source2")
	var user_ent: Node = _get_entity_for_struct(s1)
	var drawn1: float = PowerGraph.draw_power_for_user_entity(user_ent, 30.0)
	assert_eq(drawn1, 30.0, "drawn 30")
	c_src1 = ent2.get_component(_C_POWER_SOURCE)
	c_src2 = ent3.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 0.0, "source1 emptied (25) + 5 from source2")
	assert_eq(c_src2.get("current_storage"), 70.0, "source2 75-5=70")
	var drawn2: float = PowerGraph.draw_power_for_user_entity(user_ent, 50.0)
	assert_eq(drawn2, 50.0, "drawn 50")
	c_src1 = ent2.get_component(_C_POWER_SOURCE)
	c_src2 = ent3.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 0.0, "source1 still 0")
	assert_eq(c_src2.get("current_storage"), 20.0, "source2 70-50=20")


func test_distributes_generator_excess_power() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var src1: Resource = _C_POWER_SOURCE.new() as Resource
	src1.set("max_storage", 100.0)
	var src2: Resource = _C_POWER_SOURCE.new() as Resource
	src2.set("max_storage", 100.0)
	var c_gen: Resource = _C_POWER_GENERATOR.new() as Resource
	c_gen.set("power_output", 75.0)
	c_gen.set("is_active", true)
	_add_power_entity(s1, [src1, c_gen])
	_add_power_entity(s2, [src2])
	var ent1: Node = _get_entity_for_struct(s1)
	var ent2: Node = _get_entity_for_struct(s2)
	var c_gen_actual: Resource = ent1.get_component(_C_POWER_GENERATOR)
	c_gen_actual.set("is_active", true)
	_run_power_systems(1.0)
	var c_src1: Resource = ent1.get_component(_C_POWER_SOURCE)
	var c_src2: Resource = ent2.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 75.0, "source1 gets 75 from gen")
	assert_eq(c_src2.get("current_storage"), 0.0, "source2 unchanged (excess not yet distributed)")
	_run_power_systems(1.0)
	c_src1 = ent1.get_component(_C_POWER_SOURCE)
	c_src2 = ent2.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 100.0, "source1 full")
	assert_eq(c_src2.get("current_storage"), 50.0, "source2 gets excess 50")


func test_draws_power_for_user() -> void:
	var s_user: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s_src1: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var s_src2: TestStructure = _make_test_structure(Vector3(10, 0, 0))
	var src1: Resource = _C_POWER_SOURCE.new() as Resource
	src1.set("max_storage", 100.0)
	src1.set("current_storage", 75.0)
	var src2: Resource = _C_POWER_SOURCE.new() as Resource
	src2.set("max_storage", 100.0)
	src2.set("current_storage", 50.0)
	var c_user: Resource = _C_POWER_USER.new() as Resource
	c_user.set("use_power_cost", 50.0)
	c_user.set("buffer_capacity", 50.0)
	_add_power_entity(s_user, [c_user])
	_add_power_entity(s_src1, [src1])
	_add_power_entity(s_src2, [src2])
	_run_power_systems()
	var user_ent: Node = _get_entity_for_struct(s_user)
	var ent_src1: Node = _get_entity_for_struct(s_src1)
	var ent_src2: Node = _get_entity_for_struct(s_src2)
	var c_user_actual: Resource = user_ent.get_component(_C_POWER_USER)
	var c_src1: Resource = ent_src1.get_component(_C_POWER_SOURCE)
	var c_src2: Resource = ent_src2.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 75.0, "initial")
	assert_eq(c_src2.get("current_storage"), 50.0, "initial")
	var consume_once: Callable = func() -> bool:
		var drew: float = PowerGraph.draw_power_for_user_entity(user_ent, 50.0)
		c_user_actual = user_ent.get_component(_C_POWER_USER)
		# draw_power_for_user_entity already adds drew to buffer; do not add again
		if c_user_actual.get("power_buffer") >= 50.0:
			c_user_actual.set("power_buffer", 0.0)
			return true
		return false
	var result: bool = consume_once.call()
	assert_true(result, "first consume succeeds")
	c_src1 = ent_src1.get_component(_C_POWER_SOURCE)
	c_src2 = ent_src2.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 25.0, "after first consume")
	assert_eq(c_src2.get("current_storage"), 50.0, "src2 unchanged after first")
	result = consume_once.call()
	assert_true(result, "second consume succeeds")
	c_src1 = ent_src1.get_component(_C_POWER_SOURCE)
	c_src2 = ent_src2.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 0.0, "after second consume")
	assert_eq(c_src2.get("current_storage"), 25.0, "after second consume")
	result = consume_once.call()
	assert_false(result, "third consume fails")
	c_src1 = ent_src1.get_component(_C_POWER_SOURCE)
	c_src2 = ent_src2.get_component(_C_POWER_SOURCE)
	assert_eq(c_src1.get("current_storage"), 0.0, "after third attempt")
	assert_eq(c_src2.get("current_storage"), 0.0, "both empty")


# # ---- Subgraph Tests ----

func test_single_connected_subgraph() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var s3: TestStructure = _make_test_structure(Vector3(10, 0, 0))
	var src1: Resource = _C_POWER_SOURCE.new() as Resource
	src1.set("max_storage", 100.0)
	var src2: Resource = _C_POWER_SOURCE.new() as Resource
	src2.set("max_storage", 100.0)
	var c_user: Resource = _C_POWER_USER.new() as Resource
	c_user.set("use_power_cost", 50.0)
	c_user.set("buffer_capacity", 100.0)
	var c_gen: Resource = _C_POWER_GENERATOR.new() as Resource
	c_gen.set("power_output", 50.0)
	c_gen.set("is_active", true)
	_add_power_entity(s1, [src1, c_gen])
	_add_power_entity(s2, [c_user])
	_add_power_entity(s3, [src2])
	_run_power_systems()
	var sg = PowerGraph.find_subgraph_for_node(s1)
	assert_not_null(sg, "subgraph exists")
	assert_eq(sg.nodes.size(), 3, "subgraph has 3 nodes")
	assert_eq(sg.sources.size(), 2, "subgraph has 2 sources")
	assert_eq(sg.users.size(), 1, "subgraph has 1 user")
	assert_eq(sg.generators.size(), 1, "subgraph has 1 generator")


func test_multiple_disconnected_subgraphs() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var s3: TestStructure = _make_test_structure(Vector3(200, 0, 0))
	var s4: TestStructure = _make_test_structure(Vector3(205, 0, 0))
	var src1: Resource = _C_POWER_SOURCE.new() as Resource
	src1.set("max_storage", 100.0)
	var src2: Resource = _C_POWER_SOURCE.new() as Resource
	src2.set("max_storage", 100.0)
	var c_user1: Resource = _C_POWER_USER.new() as Resource
	c_user1.set("use_power_cost", 50.0)
	c_user1.set("buffer_capacity", 100.0)
	var c_user2: Resource = _C_POWER_USER.new() as Resource
	c_user2.set("use_power_cost", 50.0)
	c_user2.set("buffer_capacity", 100.0)
	_add_power_entity(s1, [src1])
	_add_power_entity(s2, [c_user1])
	_add_power_entity(s3, [src2])
	_add_power_entity(s4, [c_user2])
	_run_power_systems()
	var sg1 = PowerGraph.find_subgraph_for_node(s1)
	var sg2 = PowerGraph.find_subgraph_for_node(s3)
	assert_not_null(sg1)
	assert_not_null(sg2)
	assert_ne(sg1, sg2, "subgraphs should be different")
	assert_eq(sg1.nodes.size(), 2, "sg1 has 2 nodes")
	assert_eq(sg1.sources.size(), 1, "sg1 has 1 source")
	assert_eq(sg1.users.size(), 1, "sg1 has 1 user")
	assert_eq(sg2.nodes.size(), 2, "sg2 has 2 nodes")
	assert_eq(sg2.sources.size(), 1, "sg2 has 1 source")
	assert_eq(sg2.users.size(), 1, "sg2 has 1 user")


# # ---- Node State Tests ----

func test_enable_and_disable_node() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	_run_power_systems()
	assert_true(PowerGraph.is_edge_enabled(s1, s2), "edge initially enabled")
	PowerGraph.set_node_enabled(s1, false)
	_run_power_systems()
	var cn1: Resource = null
	for e in _world.query.with_all([_C_STRUCTURE]).execute():
		var cs: Resource = e.get_component(_C_STRUCTURE)
		if cs and cs.get("structure_node") == s1:
			cn1 = e.get_component(_C_POWER_NODE)
			break
	assert_false(cn1.get("is_enabled"), "node1 disabled")
	assert_false(PowerGraph.is_edge_enabled(s1, s2), "edge should be disabled when one endpoint is disabled")
	PowerGraph.set_node_enabled(s2, false)
	_run_power_systems()
	assert_false(PowerGraph.is_edge_enabled(s1, s2), "edge disabled when both disabled")


func test_add_disabled_node() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(50, 0, 0))
	_add_power_entity(s1)
	var cn2: Resource = _C_POWER_NODE.new() as Resource
	cn2.set("structure_node", s2)
	cn2.set("max_connection_distance", 100.0)
	cn2.set("max_connections", 4)
	cn2.set("is_enabled", false)
	var ent2: Node = _add_power_entity(s2, [cn2])
	_run_power_systems()
	assert_false(PowerGraph.is_edge_enabled(s1, s2), "edge disabled when s2 starts disabled")
	PowerGraph.set_node_enabled(s2, true)
	_run_power_systems()
	var stored: Resource = ent2.get_component(_C_POWER_NODE)
	assert_true(stored.get("is_enabled"), "node2 enabled after set_node_enabled")
	assert_true(PowerGraph.is_edge_enabled(s1, s2), "edge enabled when node2 enabled")


func test_add_disabled_node_with_multiple_connections() -> void:
	var s1: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s2: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var s3: TestStructure = _make_test_structure(Vector3(10, 0, 0))
	_add_power_entity(s1)
	_add_power_entity(s2)
	var cn3: Resource = _C_POWER_NODE.new() as Resource
	cn3.set("structure_node", s3)
	cn3.set("max_connection_distance", 100.0)
	cn3.set("max_connections", 4)
	cn3.set("is_enabled", false)
	var ent3: Node = _add_power_entity(s3, [cn3])
	_run_power_systems()
	var stored: Resource = ent3.get_component(_C_POWER_NODE)
	assert_true(_get_entity_for_struct(s2).get_component(_C_POWER_NODE).get("is_enabled"), "node2 enabled")
	assert_false(stored.get("is_enabled"), "node3 disabled")
	assert_false(PowerGraph.is_edge_enabled(s2, s3), "edge s2-s3 disabled")
	PowerGraph.set_node_enabled(s3, true)
	_run_power_systems()
	stored = ent3.get_component(_C_POWER_NODE)
	assert_true(stored.get("is_enabled"), "node3 enabled")
	assert_true(PowerGraph.is_edge_enabled(s2, s3), "edge s2-s3 enabled")
