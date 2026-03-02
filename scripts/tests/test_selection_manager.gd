extends GutTest

const SelectionManagerScript = preload("res://scripts/autoload/selection_manager.gd")
const SelectableComponentScript = preload("res://scripts/components/selectable_component.gd")

class TestSelectionManager:
	extends "res://scripts/autoload/selection_manager.gd"

	var stub_selectable: Node = null
	var stub_collider: Node = null

	func _raycast_selectable_at_mouse(_mouse_pos: Vector2) -> Node:
		return stub_selectable

	func _raycast_collider_at_mouse(_mouse_pos: Vector2) -> Node:
		return stub_collider


var _manager: TestSelectionManager = null


func before_each() -> void:
	_manager = TestSelectionManager.new()
	add_child_autofree(_manager)
	BuildManager.current_state = BuildManager.BuildState.IDLE
	BuildManager._placement_cooldown = 0.0


func _left_click_event() -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(100, 100)
	return ev


func _make_selectable(kind: String = "structure") -> Node:
	var entity_node: Node3D = Node3D.new()
	entity_node.name = "FakeEntity"
	var selectable: Node = SelectableComponentScript.new()
	selectable.selection_kind = kind
	entity_node.add_child(selectable)
	add_child_autofree(entity_node)
	return selectable


func test_clicking_selectable_selects_it() -> void:
	var selectable: Node = _make_selectable("structure")
	_manager.stub_selectable = selectable

	_manager._input(_left_click_event())

	assert_eq(_manager.selected_selectable, selectable, "Left click on selectable should select it")
	assert_true(selectable.is_selected(), "Selectable should receive selected=true")


func test_hover_updates_from_raycast_target() -> void:
	var selectable: Node = _make_selectable("structure")
	_manager.stub_selectable = selectable

	_manager._process(0.016)
	assert_true(selectable.is_hovered(), "Hover should be true when raycast hits selectable")

	_manager.stub_selectable = null
	_manager._process(0.016)
	assert_false(selectable.is_hovered(), "Hover should be cleared when raycast no longer hits selectable")


func test_clicking_empty_world_clears_selection() -> void:
	var selectable: Node = _make_selectable("structure")
	_manager.select_selectable(selectable)
	assert_not_null(_manager.selected_selectable, "Precondition: selection should be active")

	_manager.stub_selectable = null
	_manager.stub_collider = null
	_manager._input(_left_click_event())

	assert_null(_manager.selected_selectable, "Empty click should clear active selection")
