extends Node
class_name SelectableComponent
## Reusable RTS-style selection input/state component.

signal selection_requested(selectable: SelectableComponent)
signal selected_changed(is_selected: bool)
signal hover_changed(is_hovered: bool)
signal details_changed
signal selectable_destroyed

@export var selection_kind: String = "entity"
@export var display_name_override: String = ""
@export var faction_override: String = ""
@export var is_selectable: bool = true
@export var auto_connect_area: bool = true
@export var area_path: NodePath = NodePath("../Area3D")

var owner_entity: Node3D = null
var _area: Area3D = null
var _is_selected: bool = false
var _is_hovered: bool = false


func _ready() -> void:
	owner_entity = get_parent() as Node3D
	if auto_connect_area:
		_try_connect_area_signals()
	tree_exiting.connect(_on_tree_exiting)


func _try_connect_area_signals() -> void:
	var node: Node = get_node_or_null(area_path)
	if node is Area3D:
		_area = node as Area3D
	else:
		return

	if not _area.is_connected("input_event", _on_area_input_event):
		_area.input_event.connect(_on_area_input_event)
	if not _area.is_connected("mouse_entered", _on_area_mouse_entered):
		_area.mouse_entered.connect(_on_area_mouse_entered)
	if not _area.is_connected("mouse_exited", _on_area_mouse_exited):
		_area.mouse_exited.connect(_on_area_mouse_exited)


func request_selection() -> void:
	if not is_selectable:
		return
	SelectionManager.select_selectable(self)
	selection_requested.emit(self)


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return
	_is_selected = value
	selected_changed.emit(_is_selected)


func set_hovered(value: bool) -> void:
	if _is_hovered == value:
		return
	_is_hovered = value
	hover_changed.emit(_is_hovered)


func is_selected() -> bool:
	return _is_selected


func is_hovered() -> bool:
	return _is_hovered


func get_display_name() -> String:
	if not display_name_override.is_empty():
		return display_name_override
	if owner_entity and owner_entity.has_method("get_selection_name"):
		return owner_entity.call("get_selection_name")
	if owner_entity:
		return owner_entity.name.replace("_", " ").capitalize()
	return "Unknown"


func get_faction() -> String:
	if not faction_override.is_empty():
		return faction_override
	if owner_entity and owner_entity.has_method("get_team"):
		return owner_entity.call("get_team")
	if owner_entity:
		for child in owner_entity.get_children():
			if child is TeamComponent:
				return (child as TeamComponent).get_team_string()
	return "neutral"


func get_selection_details() -> Dictionary:
	if owner_entity and owner_entity.has_method("get_selection_details"):
		var details: Variant = owner_entity.call("get_selection_details")
		if details is Dictionary:
			return details
	return {
		"name": get_display_name(),
		"category": selection_kind,
		"faction": get_faction(),
		"stats": []
	}


func notify_details_changed() -> void:
	details_changed.emit()


func _on_area_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not is_selectable:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var blocked: bool = BuildManager.is_selection_blocked()
			if blocked:
				return
			request_selection()


func _on_area_mouse_entered() -> void:
	var blocked: bool = BuildManager.is_hover_blocked()
	if blocked:
		return
	set_hovered(true)


func _on_area_mouse_exited() -> void:
	set_hovered(false)


func _on_tree_exiting() -> void:
	selectable_destroyed.emit()
