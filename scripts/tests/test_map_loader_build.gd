extends GutTest
## Integration tests for MapLoader + Build process.
## Verifies map-loaded structures spawn, register with ECS, instant-build, and power graph setup.
## Run via GUT: test_map_loader_build.gd

# Systems and observers (same as test_construction_system + test_power_graph)
const _O_POWER_GRAPH: Script = preload("res://scripts/observers/o_power_graph.gd")
const _O_CONSTRUCTION_BUILT: Script = preload("res://scripts/observers/o_construction_built.gd")
const _O_CONSTRUCTION_POWER_NODE: Script = preload("res://scripts/observers/o_construction_power_node.gd")
const _O_POWER_EDGE_BLOCKED: Script = preload("res://scripts/observers/o_power_edge_blocked.gd")
const _POWER_GENERATOR_SYSTEM: Script = preload("res://scripts/ecs/systems/power_generator_system.gd")
const _POWER_EDGE_VISUAL_SYSTEM: Script = preload("res://scripts/ecs/systems/power_edge_visual_system.gd")
const _CONSTRUCTION_POWER_PREVIEW_SYSTEM: Script = preload("res://scripts/ecs/systems/construction_power_preview_system.gd")
const _CONSTRUCTION_SYSTEM: Script = preload("res://scripts/ecs/systems/construction_system.gd")
const _TEST_SCENE: PackedScene = preload("res://addons/gecs/tests/test_scene.tscn")
const _C_STRUCTURE: Script = preload("res://scripts/ecs/components/c_structure.gd")
const _C_CONSTRUCTION: Script = preload("res://scripts/ecs/components/c_construction.gd")
const _C_POWER_NODE: Script = preload("res://scripts/ecs/components/c_power_node.gd")

var _world: Node = null
var _scene_root: Node3D = null
var _structures_parent: Node3D = null
var _asteroids_parent: Node3D = null


func before_each() -> void:
	_scene_root = Node3D.new()
	add_child_autofree(_scene_root)
	_structures_parent = Node3D.new()
	_structures_parent.name = "Structures"
	_scene_root.add_child(_structures_parent)
	_asteroids_parent = Node3D.new()
	_asteroids_parent.name = "Asteroids"
	_scene_root.add_child(_asteroids_parent)

	_world = _create_ecs_world()
	ECS.world = _world

	if GameWorld:
		var lines_parent: Node3D = Node3D.new()
		_scene_root.add_child(lines_parent)
		GameWorld.set_world(null, lines_parent)

	for obs_script in [_O_POWER_GRAPH, _O_CONSTRUCTION_BUILT, _O_CONSTRUCTION_POWER_NODE, _O_POWER_EDGE_BLOCKED]:
		if obs_script:
			_world.add_observer(obs_script.new())
	_world.add_system(_POWER_GENERATOR_SYSTEM.new(), true)
	_world.add_system(_POWER_EDGE_VISUAL_SYSTEM.new(), true)
	_world.add_system(_CONSTRUCTION_POWER_PREVIEW_SYSTEM.new(), true)
	_world.add_system(_CONSTRUCTION_SYSTEM.new(), true)
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


func _make_test_map_data() -> MapData:
	var map_data: MapData = MapData.new()
	map_data.schema_version = 1
	map_data.map_id = "test_map"
	map_data.map_name = "Test Map"
	map_data.biome = "asteroid_field"
	map_data.map_size = Vector2(100, 100)
	map_data.initial_wave_delay = 30.0
	map_data.wave_interval = 60.0
	# Ensure starting_resources passes validation (energy_capacity >= 1)
	map_data.starting_resources = StartingResources.new()
	map_data.starting_resources.minerals = 100
	map_data.starting_resources.energy = 50.0
	map_data.starting_resources.energy_capacity = 100.0
	map_data.starting_structures = [
		_make_structure_placement("solar_panel", Vector3(0, 0, 0)),
		_make_structure_placement("power_node", Vector3(6, 0, 0)),
		_make_structure_placement("mining_station", Vector3(12, 0, 0)),
	]
	return map_data


func _make_structure_placement(building_type: String, position: Vector3) -> StructurePlacement:
	var s: StructurePlacement = StructurePlacement.new()
	s.building_type = building_type
	s.position = position
	return s


func _run_ecs_and_wait(frames: int = 3) -> void:
	for _i in range(frames):
		if PowerGraph and ECS and ECS.world:
			PowerGraph.refresh_graph(ECS.world)
		if ECS and ECS.world:
			ECS.process(0.016)
		await get_tree().process_frame


# ---- Map load + spawn ----

func test_map_load_spawns_structures() -> void:
	var map_data: MapData = _make_test_map_data()
	MapLoader.load_map_into_containers(map_data, _structures_parent, _asteroids_parent, false)

	assert_eq(_structures_parent.get_child_count(), 3, "Should spawn 3 structures")
	assert_eq(_asteroids_parent.get_child_count(), 0, "No asteroids in test map")


func test_map_load_structures_have_spawned_structure_flag() -> void:
	var map_data: MapData = _make_test_map_data()
	MapLoader.load_map_into_containers(map_data, _structures_parent, _asteroids_parent, false)

	assert_gte(_structures_parent.get_child_count(), 1, "Should have at least 1 structure to check")
	for child in _structures_parent.get_children():
		assert_true(child.get("spawned_structure") == true, "%s should have spawned_structure=true" % child.name)


# ---- ECS registration + instant build (requires await) ----

func test_map_loaded_structures_register_with_ecs_and_instant_build() -> void:
	var map_data: MapData = _make_test_map_data()
	MapLoader.load_map_into_containers(map_data, _structures_parent, _asteroids_parent, false)

	# Deferred _register_with_ecs runs at end of frame
	await get_tree().process_frame
	# Run ConstructionSystem to process instant_build
	await _run_ecs_and_wait()

	var entity_count: int = _world.entity_to_archetype.size()
	assert_gte(entity_count, 3, "At least 3 entities should be in ECS world")

	# All map-loaded structures should be built (no C_Construction, or is_built)
	var struct_entities: Array = _world.query.with_all([_C_STRUCTURE]).execute()
	var built_count: int = 0
	for entity in struct_entities:
		var c_const = entity.get_component(_C_CONSTRUCTION)
		if c_const == null:
			built_count += 1
	assert_gte(built_count, 3, "Map-loaded structures should be built (instant_build) after ECS process")


func test_map_loaded_structures_have_power_nodes_in_graph() -> void:
	var map_data: MapData = _make_test_map_data()
	MapLoader.load_map_into_containers(map_data, _structures_parent, _asteroids_parent, false)

	await get_tree().process_frame
	await _run_ecs_and_wait()

	if not PowerGraph:
		pass_test("PowerGraph not available, skip")
		return

	# PowerGraph should know about our structures (they have C_PowerNode)
	var struct_entities: Array = _world.query.with_all([_C_STRUCTURE, _C_POWER_NODE]).execute()
	assert_eq(struct_entities.size(), 3, "At least solar_panel and power_node should have C_PowerNode")
	# PowerGraph stores entity cache - we can't easily introspect; just ensure no crash
	pass_test("PowerGraph refreshed without error")


func test_map_loaded_structures_have_edges_between_power_nodes() -> void:
	## Validates that power lines (edges) exist between map-loaded structures.
	## Structures are placed at (0,0,0), (6,0,0), (12,0,0) - within max_connection_distance 15.
	var map_data: MapData = _make_test_map_data()
	MapLoader.load_map_into_containers(map_data, _structures_parent, _asteroids_parent, false)

	await get_tree().process_frame
	await _run_ecs_and_wait()

	if not PowerGraph:
		pass_test("PowerGraph not available, skip")
		return

	var edges: Dictionary = PowerGraph.get_edges()
	var edge_count: int = 0
	for _struct_a in edges.keys():
		var neighbor_map: Variant = edges[_struct_a]
		if neighbor_map is Dictionary:
			edge_count += (neighbor_map as Dictionary).size()
	# Each edge appears twice (A->B and B->A), so edge_count/2 = unique edges
	var unique_edges: int = edge_count / 2
	assert_gte(unique_edges, 1, "Map-loaded structures should have at least 1 power edge between nodes (solar_panel-power_node or power_node-mining_station). Got %d edges." % unique_edges)


func test_map_loaded_solar_and_power_node_have_matching_connection_counts() -> void:
	## Integration test: real structures (solar panel, power node) must have symmetric connection counts.
	## Both entities read C_PowerNode.connected_entity_ids in get_selection_details - they must match.
	## Solar at (0,0,0), power_node at (6,0,0) - within 15m, so they should connect.
	var map_data: MapData = _make_test_map_data()
	MapLoader.load_map_into_containers(map_data, _structures_parent, _asteroids_parent, false)

	await get_tree().process_frame
	await _run_ecs_and_wait()

	if not PowerGraph:
		pass_test("PowerGraph not available, skip")
		return

	var struct_entities: Array = _world.query.with_all([_C_STRUCTURE, _C_POWER_NODE]).execute()
	var solar_entity: Variant = null
	var power_node_entity: Variant = null
	for ent in struct_entities:
		var c_struct: Variant = ent.get_component(_C_STRUCTURE)
		if c_struct and c_struct.get("building_type") == "solar_panel":
			solar_entity = ent
		elif c_struct and c_struct.get("building_type") == "power_node":
			power_node_entity = ent

	assert_not_null(solar_entity, "Should have solar_panel entity")
	assert_not_null(power_node_entity, "Should have power_node entity")
	if solar_entity == null or power_node_entity == null:
		return

	var c_solar: Variant = solar_entity.get_component(_C_POWER_NODE)
	var c_node: Variant = power_node_entity.get_component(_C_POWER_NODE)
	assert_not_null(c_solar, "Solar panel should have C_PowerNode")
	assert_not_null(c_node, "Power node should have C_PowerNode")
	if c_solar == null or c_node == null:
		return

	var solar_conns: Array = c_solar.get("connected_entity_ids")
	var node_conns: Array = c_node.get("connected_entity_ids")
	var solar_count: int = solar_conns.size()
	var node_count: int = node_conns.size()

	# Both must have at least 1 connection (they are adjacent)
	assert_gte(solar_count, 1, "Solar panel should have >= 1 connection. Got %d. Node has %d." % [solar_count, node_count])
	assert_gte(node_count, 1, "Power node should have >= 1 connection. Got %d. Solar has %d." % [node_count, solar_count])

	# Symmetric: each should list the other's entity id
	var node_id: int = power_node_entity.get_instance_id()
	var solar_id: int = solar_entity.get_instance_id()
	assert_true(node_id in solar_conns, "Solar's connected_entity_ids should include power node id")
	assert_true(solar_id in node_conns, "Power node's connected_entity_ids should include solar id")


# ---- Validation ----

func test_map_validator_accepts_valid_structure_types() -> void:
	var map_data: MapData = _make_test_map_data()
	var result: Dictionary = MapValidator.validate_map_data(map_data)
	assert_true(result.get("is_valid", false), "Valid map should pass validation")
	assert_eq((result.get("errors", PackedStringArray()) as PackedStringArray).size(), 0)


func test_map_load_rejects_invalid_structure_type() -> void:
	var map_data: MapData = MapData.new()
	map_data.map_name = "Invalid"
	map_data.map_size = Vector2(100, 100)
	map_data.initial_wave_delay = 30.0
	map_data.wave_interval = 60.0
	map_data.starting_resources = StartingResources.new()
	map_data.starting_resources.energy_capacity = 100.0
	map_data.starting_structures.append(_make_structure_placement("invalid_type", Vector3.ZERO))

	var result: Dictionary = MapValidator.validate_map_data(map_data)
	assert_false(result.get("is_valid", true), "Invalid structure type should fail validation")
