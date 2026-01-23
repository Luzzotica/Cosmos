@tool
extends Node3D
class_name PowerSource
## Component that stores power

signal storage_changed(current: float, maximum: float)

@export var max_storage: float = 100.0:
	set(value):
		max_storage = value
		current_storage = minf(current_storage, max_storage)
		storage_changed.emit(current_storage, max_storage)

@export var current_storage: float = 0.0:
	set(value):
		current_storage = clampf(value, 0.0, max_storage)
		storage_changed.emit(current_storage, max_storage)


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		call_deferred("_register_with_power_graph")


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_unregister_from_power_graph()


func _register_with_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.add_source(self)


func _unregister_from_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.remove_source(self)


## Store power in this source
func store_power(amount: float) -> float:
	var available_space: float = max_storage - current_storage
	var amount_to_store: float = minf(amount, available_space)
	current_storage += amount_to_store
	return amount_to_store


## Draw power from this source
func draw_power(amount: float) -> float:
	var amount_to_draw: float = minf(amount, current_storage)
	current_storage -= amount_to_draw
	return amount_to_draw


## Get storage percentage (0.0 to 1.0)
func get_storage_percentage() -> float:
	if max_storage <= 0:
		return 0.0
	return current_storage / max_storage


## Check if source has any power
func has_power() -> bool:
	return current_storage > 0
