extends Area3D
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

var owner_entity: Node3D = null
var _is_selected: bool = false
var _is_hovered: bool = false
var _last_details_hash: int = 0
var _has_cached_details: bool = false


func _ready() -> void:
	owner_entity = get_parent() as Node3D
	input_ray_pickable = true
	monitorable = true  # Required for enemy collision/impact detection (intersect_shape)
	collision_layer = 1 << 1
	collision_mask = 0
	SelectionManager.register_selectable(self)
	tree_exiting.connect(_on_tree_exiting)


func request_selection() -> void:
	if not is_selectable:
		return
	selection_requested.emit(self)


func _process(_delta: float) -> void:
	if not _is_selected:
		return
	_refresh_details_if_changed()


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return
	_is_selected = value
	if _is_selected:
		# Force one refresh when selected to initialize HUD values.
		_has_cached_details = false
		_refresh_details_if_changed()
	else:
		_has_cached_details = false
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
	# ECS enemies: owner is body, parent is entity - get team from selection details
	if owner_entity and owner_entity.has_method("get_selection_details"):
		var details: Dictionary = owner_entity.call("get_selection_details")
		if details.has("faction"):
			return details.faction
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
	_has_cached_details = false
	_refresh_details_if_changed()


func _refresh_details_if_changed() -> void:
	var details: Dictionary = get_selection_details()
	var details_hash: int = details.hash()
	if _has_cached_details and details_hash == _last_details_hash:
		return
	_last_details_hash = details_hash
	_has_cached_details = true
	details_changed.emit()


func handle_mouse_entered() -> void:
	var blocked: bool = BuildManager.is_hover_blocked()
	if blocked:
		return
	set_hovered(true)


func handle_mouse_exited() -> void:
	set_hovered(false)


func _on_tree_exiting() -> void:
	selectable_destroyed.emit()
