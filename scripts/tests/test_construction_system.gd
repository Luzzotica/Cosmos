extends GutTest
## Construction system tests.
## Validates build progress, power consumption, instant build, and completion flow.
## Setup mirrors test_power_graph.gd for ECS world + PowerGraph.

# Preloaded resources
const _O_POWER_GRAPH: Script = preload("res://scripts/observers/o_power_graph.gd")
const _O_CONSTRUCTION_BUILT: Script = preload("res://scripts/observers/o_construction_built.gd")
const _O_CONSTRUCTION_POWER_NODE: Script = preload("res://scripts/observers/o_construction_power_node.gd")
const _O_POWER_EDGE_BLOCKED: Script = preload("res://scripts/observers/o_power_edge_blocked.gd")
const _POWER_GENERATOR_SYSTEM: Script = preload("res://scripts/ecs/systems/power_generator_system.gd")
const _POWER_EDGE_VISUAL_SYSTEM: Script = preload("res://scripts/ecs/systems/power_edge_visual_system.gd")
const _CONSTRUCTION_POWER_PREVIEW_SYSTEM: Script = preload("res://scripts/ecs/systems/construction_power_preview_system.gd")
const _CONSTRUCTION_SYSTEM: Script = preload("res://scripts/ecs/systems/construction_system.gd")
const _TEST_SCENE: PackedScene = preload("res://addons/gecs/tests/test_scene.tscn")
const _ENTITY: GDScript = preload("res://addons/gecs/ecs/entity.gd")
const _C_STRUCTURE: Script = preload("res://scripts/ecs/components/c_structure.gd")
const _C_POWER_NODE: Script = preload("res://scripts/ecs/components/c_power_node.gd")
const _C_CONSTRUCTION: Script = preload("res://scripts/ecs/components/c_construction.gd")
const _C_CONSTRUCTION_POWER_NODE: Script = preload("res://scripts/ecs/components/c_construction_power_node.gd")
const _C_POWER_SOURCE: Script = preload("res://scripts/ecs/components/c_power_source.gd")
const _C_POWER_USER: Script = preload("res://scripts/ecs/components/c_power_user.gd")
const _C_TRANSFORM3D: Script = preload("res://scripts/ecs/components/c_transform3d.gd")

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
	# Add observers and systems
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


class TestStructure extends Node3D:
	var building_type: String = "power_node"
	func can_accept_more_connections() -> bool:
		return true


class CallbackStructure extends TestStructure:
	var callback_called: bool = false
	func _on_construction_completed() -> void:
		callback_called = true


func _make_test_structure(pos: Vector3, bt: String = "power_node") -> TestStructure:
	var s: TestStructure = TestStructure.new()
	s.building_type = bt
	s.position = pos
	_scene_root.add_child(s)
	return s


## Create a construction entity (under build) with optional overrides.
func _add_construction_entity(
	struct: Node3D,
	opts: Dictionary = {}
) -> Node:
	var entity: Node = _ENTITY.new()
	var c_struct: Resource = _C_STRUCTURE.new() as Resource
	c_struct.set("structure_node", struct)
	c_struct.set("building_type", struct.get("building_type") if struct.get("building_type") else "power_node")

	var c_construction: Resource = _C_CONSTRUCTION.new() as Resource
	c_construction.set("is_built", opts.get("is_built", false))
	c_construction.set("build_progress", opts.get("build_progress", 0.0))
	c_construction.set("requires_power", opts.get("requires_power", true))
	c_construction.set("build_power_cost", opts.get("build_power_cost", 10.0))
	c_construction.set("construction_time", opts.get("construction_time", 3.0))
	c_construction.set("instant_build", opts.get("instant_build", false))

	var c_build_node: Resource = _C_CONSTRUCTION_POWER_NODE.new() as Resource
	c_build_node.set("structure_node", struct)
	c_build_node.set("max_connection_distance", opts.get("max_connection_distance", 100.0))

	var c_power_node: Resource = _C_POWER_NODE.new() as Resource
	c_power_node.set("structure_node", struct)
	c_power_node.set("max_connection_distance", opts.get("max_connection_distance", 100.0))
	c_power_node.set("max_connections", 1)  # Leaf during construction (mirrors StructureEntity _apply_construction_mode)
	c_power_node.set("is_enabled", true)  # Enabled so graph routes power during construction

	var c_transform: Resource = _C_TRANSFORM3D.new() as Resource
	c_transform.set("position", struct.position)

	# C_PowerUser required for PowerGraph.draw_power_for_user_entity
	var c_user: Resource = _C_POWER_USER.new() as Resource
	c_user.set("structure_node", struct)
	c_user.set("is_construction_user", true)
	c_user.set("use_power_cost", opts.get("build_power_cost", 10.0))
	c_user.set("buffer_capacity", opts.get("buffer_capacity", 15.0))

	var comps: Array = [c_struct, c_construction, c_build_node, c_power_node, c_transform, c_user]
	_world.add_entity(entity, comps, false)

	# Re-set structure_node after add (GECS may clear refs)
	for comp_script in [_C_STRUCTURE, _C_CONSTRUCTION_POWER_NODE, _C_POWER_NODE, _C_POWER_USER]:
		var c: Resource = entity.get_component(comp_script as Script)
		if c:
			c.set("structure_node", struct)

	return entity


## Create a built power source entity (for feeding construction power).
func _add_power_source_entity(struct: Node3D, storage: float = 100.0, current: float = 100.0) -> Node:
	var entity: Node = _ENTITY.new()
	var c_struct: Resource = _C_STRUCTURE.new() as Resource
	c_struct.set("structure_node", struct)
	c_struct.set("building_type", struct.get("building_type") if struct.get("building_type") else "power_node")

	var c_power_node: Resource = _C_POWER_NODE.new() as Resource
	c_power_node.set("structure_node", struct)
	c_power_node.set("max_connection_distance", 100.0)
	c_power_node.set("max_connections", 4)
	c_power_node.set("is_enabled", true)

	var c_construction: Resource = _C_CONSTRUCTION.new() as Resource
	c_construction.set("is_built", true)
	c_construction.set("build_progress", 1.0)

	var c_src: Resource = _C_POWER_SOURCE.new() as Resource
	c_src.set("max_storage", storage)
	c_src.set("current_storage", current)

	var c_transform: Resource = _C_TRANSFORM3D.new() as Resource
	c_transform.set("position", struct.position)

	var comps: Array = [c_struct, c_power_node, c_construction, c_src, c_transform]
	_world.add_entity(entity, comps, false)

	for comp_script in [_C_STRUCTURE, _C_POWER_NODE]:
		var c: Resource = entity.get_component(comp_script as Script)
		if c:
			c.set("structure_node", struct)

	return entity


func _run_systems(delta: float = 0.016) -> void:
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


## Connect construction entity's C_PowerNode to another entity (e.g. power source).
## Construction uses C_PowerNode.connected_entity_ids for power check (max_connections=1 during build).
func _connect_build_node_to(build_entity: Node, other_entity: Node) -> void:
	var c_build_power: Resource = build_entity.get_component(_C_POWER_NODE)
	var c_other_node: Resource = other_entity.get_component(_C_POWER_NODE)
	if c_build_power == null or c_other_node == null:
		return
	var other_id: int = other_entity.get_instance_id()
	var build_id: int = build_entity.get_instance_id()
	var conns: Array = c_build_power.get("connected_entity_ids")
	if conns == null:
		conns = []
	if other_id not in conns:
		conns.append(other_id)
		c_build_power.set("connected_entity_ids", conns)
	# Bidirectional: other entity's C_PowerNode should reference us
	var other_conns: Array = c_other_node.get("connected_entity_ids")
	if other_conns == null:
		other_conns = []
	if build_id not in other_conns:
		other_conns.append(build_id)
		c_other_node.set("connected_entity_ids", other_conns)


# ---- Instant build ----

func test_instant_build_completes_immediately() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {"instant_build": true})

	assert_not_null(ent.get_component(_C_CONSTRUCTION), "C_Construction should exist")
	assert_not_null(ent.get_component(_C_CONSTRUCTION_POWER_NODE), "C_ConstructionPowerNode should exist")

	var c_power_node: Resource = ent.get_component(_C_POWER_NODE)	
	assert_not_null(c_power_node, "C_PowerNode should exist")
	assert_true(c_power_node.get("is_enabled"), "C_PowerNode should be enabled during construction for power routing")

	_run_systems()

	assert_null(ent.get_component(_C_CONSTRUCTION), "C_Construction should be removed after completion")
	assert_null(ent.get_component(_C_CONSTRUCTION_POWER_NODE), "C_ConstructionPowerNode should be removed")
	# C_PowerNode remains (entity keeps it) - but we removed C_Construction, so entity no longer matches construction query
	# After completion, entity has C_PowerNode with is_enabled=true
	assert_true(c_power_node.get("is_enabled"), "C_PowerNode should be enabled after build")


func test_instant_build_removes_construction_components() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {"instant_build": true})
	_run_systems()

	assert_false(ent.get_component(_C_CONSTRUCTION) != null, "Entity should not have C_Construction")
	assert_false(ent.get_component(_C_CONSTRUCTION_POWER_NODE) != null, "Entity should not have C_ConstructionPowerNode")
	assert_true(ent.get_component(_C_POWER_NODE).get("is_enabled"), "C_PowerNode should be enabled after build")


# ---- Build progress (power-paid path) ----

func test_build_progress_increases_when_power_paid() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {"construction_time": 2.0})
	var c_construction: Resource = ent.get_component(_C_CONSTRUCTION)
	c_construction.set("build_power_paid", true)  # Simulate power already paid

	_run_systems(1.0)  # 1 second delta

	var progress: float = c_construction.get("build_progress")
	assert_gt(progress, 0.0, "Build progress should increase when power is paid")
	assert_lte(progress, 1.0, "Build progress should not exceed 1.0")


func test_build_completes_when_progress_reaches_one() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {"construction_time": 1.0})
	var c_construction: Resource = ent.get_component(_C_CONSTRUCTION)
	c_construction.set("build_progress", 0.9)
	c_construction.set("build_power_paid", true)

	_run_systems(0.5)  # Should push progress past 1.0 and complete

	assert_null(ent.get_component(_C_CONSTRUCTION), "Construction should be complete (component removed)")
	assert_null(ent.get_component(_C_CONSTRUCTION_POWER_NODE), "ConstructionPowerNode should be removed")
	assert_true(ent.get_component(_C_POWER_NODE).get("is_enabled"), "C_PowerNode should be enabled after build completes")


# ---- Power requirement ----

func test_does_not_progress_without_power_connection() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {"requires_power": true})
	# No connection to power source - connected_entity_ids stays empty
	_run_systems(1.0)

	var c_construction: Resource = ent.get_component(_C_CONSTRUCTION)
	assert_not_null(c_construction, "Construction should still be in progress")
	assert_eq(c_construction.get("build_power_paid"), false, "Power should not be paid without connection")
	assert_eq(c_construction.get("build_progress"), 0.0, "Progress should remain 0")


func test_pays_power_and_progresses_when_connected_to_source() -> void:
	var s_src: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s_build: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	var ent_src: Node = _add_power_source_entity(s_src, 100.0, 50.0)
	var ent_build: Node = _add_construction_entity(s_build, {"build_power_cost": 10.0, "construction_time": 2.0})

	_connect_build_node_to(ent_build, ent_src)
	await get_tree().process_frame  # Flush deferred from previous tests
	_run_systems()  # First frame: should draw power and set build_power_paid

	var c_construction: Resource = ent_build.get_component(_C_CONSTRUCTION)
	assert_not_null(c_construction, "Construction component should exist")
	assert_true(c_construction.get("build_power_paid"), "Power should be paid when connected and enough available")
	var c_power_source: Resource = ent_src.get_component(_C_POWER_SOURCE)
	assert_eq(c_power_source.get("current_storage"), 40.0, "Power source should have less power after drawing")

	# Run more to progress build
	_run_systems(1.0)
	var progress: float = c_construction.get("build_progress")
	assert_gt(progress, 0.0, "Build should progress after power paid")


func test_does_not_pay_power_when_insufficient() -> void:
	var s_src: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var s_build: TestStructure = _make_test_structure(Vector3(5, 0, 0))
	# Source has only 5, build needs 10
	var ent_src: Node = _add_power_source_entity(s_src, 100.0, 5.0)
	var ent_build: Node = _add_construction_entity(s_build, {"build_power_cost": 10.0})

	var c_power_source: Resource = ent_src.get_component(_C_POWER_SOURCE)
	assert_true(c_power_source.get("current_storage") == 5.0, "Power source should have the same power after drawing")

	_connect_build_node_to(ent_build, ent_src)
	_run_systems()

	var c_construction: Resource = ent_build.get_component(_C_CONSTRUCTION)
	assert_eq(c_construction.get("build_power_paid"), false, "Power should not be paid when insufficient")


# ---- requires_power = false ----

func test_requires_power_false_should_progress_without_connection() -> void:
	# When requires_power is false, structure should build without drawing power.
	# BUG: Construction system has no branch for requires_power=false - it never sets
	# build_power_paid when there are no connections, so construction stalls.
	# This test documents expected behavior: progress should advance when requires_power=false.
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {"requires_power": false, "construction_time": 2.0})
	_run_systems(1.0)

	var c_construction: Resource = ent.get_component(_C_CONSTRUCTION)
	assert_not_null(c_construction, "Construction component should exist")
	# Expected: with requires_power=false, build should progress without power connection
	assert_true(
		c_construction.get("build_power_paid") or c_construction.get("build_progress") > 0.0,
		"When requires_power=false, construction should progress without power (build_power_paid or build_progress > 0)"
	)


# ---- Completion callback ----

func test_on_construction_completed_called_when_structure_has_method() -> void:
	var struct: CallbackStructure = CallbackStructure.new()
	struct.building_type = "power_node"
	struct.position = Vector3(0, 0, 0)
	_scene_root.add_child(struct)

	var ent: Node = _add_construction_entity(struct, {})
	var c_construction: Resource = ent.get_component(_C_CONSTRUCTION)
	c_construction.set("build_progress", 0.99)
	c_construction.set("build_power_paid", true)
	c_construction.set("construction_time", 1.0)

	var c_struct: Resource = ent.get_component(_C_STRUCTURE)
	c_struct.set("structure_node", struct)

	_run_systems(0.1)

	assert_true(struct.callback_called, "_on_construction_completed should be called on structure node")


# ---- Edge cases ----

func test_skips_already_built_entities() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {"is_built": true, "build_progress": 1.0})
	# Entity with is_built=true shouldn't match construction query (no C_Construction with is_built=false)
	# Actually - we still have C_Construction, it's just is_built=true. The system returns early when is_built.
	_run_systems(1.0)

	# Should still have C_Construction (system returns early, doesn't remove)
	var c_construction: Resource = ent.get_component(_C_CONSTRUCTION)
	assert_not_null(c_construction, "Built entity keeps C_Construction (query still matches)")
	# But system does nothing because is_built is true - so no removal. Actually completion removes it.
	# So if is_built is true from the start, we return early and never call _complete_construction.
	# So C_Construction and C_ConstructionPowerNode would remain. That might be wrong - pre_built
	# structures might not have C_ConstructionPowerNode at all (structure_entity doesn't add it when pre_built).
	# For this test we're creating manually. With is_built=true, the system returns early. Good.
	pass_test("Already built entities are skipped")


func test_construction_time_zero_does_not_divide_by_zero() -> void:
	var struct: TestStructure = _make_test_structure(Vector3(0, 0, 0))
	var ent: Node = _add_construction_entity(struct, {})
	var c_construction: Resource = ent.get_component(_C_CONSTRUCTION)
	c_construction.set("build_power_paid", true)
	c_construction.set("construction_time", 0.0)  # Could cause divide by zero

	# Should not crash; implementation uses maxf(construction_time, 0.001)
	_run_systems(0.016)
	pass_test("No crash with construction_time=0")
