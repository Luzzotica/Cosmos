extends GutTest
## BuildManager placement tests.
## Verifies start_building, placement validity, confirm_placement flow.
## Uses editor mode to skip resource checks.

var _main: Node3D = null
var _structures_parent: Node3D = null


func before_each() -> void:
	_main = Node3D.new()
	_main.name = "Main"
	_structures_parent = Node3D.new()
	_structures_parent.name = "Structures"
	_main.add_child(_structures_parent)
	get_tree().root.add_child(_main)


func after_each() -> void:
	if BuildManager and BuildManager.is_building():
		BuildManager.cancel_placement()
	if _main and is_instance_valid(_main):
		_main.queue_free()


func _valid_position() -> Vector3:
	return Vector3(10, 0, 10)


# ---- Placement flow (editor mode) ----

func test_start_building_editor_enters_drag_state() -> void:
	BuildManager.start_building_editor("solar_panel")
	assert_true(BuildManager.is_building(), "Should be in build state after start_building_editor")
	BuildManager.cancel_placement()


func test_place_building_editor_at_adds_structure_to_main_structures() -> void:
	var initial_count: int = _structures_parent.get_child_count()
	# Pass custom_parent to avoid Main/Structures lookup (tests may run without full game tree)
	BuildManager.place_building_editor_at("solar_panel", _valid_position(), _structures_parent)

	assert_eq(_structures_parent.get_child_count(), initial_count + 1, "Structure should be added to structures parent")
	var placed: Node = _structures_parent.get_child(_structures_parent.get_child_count() - 1)
	assert_eq(placed.global_position, _valid_position(), "Structure should be at placement position")


func test_place_building_editor_at_sets_spawned_structure() -> void:
	BuildManager.place_building_editor_at("power_node", _valid_position(), _structures_parent)

	assert_gte(_structures_parent.get_child_count(), 1, "At least one structure should be placed")
	var placed: Node = _structures_parent.get_child(_structures_parent.get_child_count() - 1)
	if placed.get("spawned_structure") != null:
		assert_true(placed.get("spawned_structure"), "Editor placement should set spawned_structure for instant build")


func test_cancel_placement_clears_build_state() -> void:
	BuildManager.start_building_editor("mining_station")
	assert_true(BuildManager.is_building())
	BuildManager.cancel_placement()
	assert_false(BuildManager.is_building())


# ---- Building data ----

func test_get_building_data_returns_data_for_valid_types() -> void:
	var data: Resource = BuildManager.get_building_data("solar_panel")
	assert_not_null(data, "solar_panel should have building data")
	if data:
		assert_not_null(data.get("scene"), "solar_panel should have scene")
	data = BuildManager.get_building_data("power_node")
	assert_not_null(data, "power_node should have building data")


func test_can_place_building_checks_minerals() -> void:
	if GameState:
		var had: int = GameState.minerals
		GameState.minerals = 0
		var can: bool = BuildManager.can_place_building("solar_panel")
		GameState.minerals = had
		assert_false(can, "Cannot place when minerals = 0")
