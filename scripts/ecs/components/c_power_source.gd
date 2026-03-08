class_name C_PowerSource
extends Component
## ECS data component for power storage.
## Replaces PowerSource node-based component.

@export var max_storage: float = 100.0
@export var current_storage: float = 0.0

var structure_node: Node3D = null


func has_power() -> bool:
	return current_storage > 0


## For PowerGraphManager compatibility (draw_power_for_user, handle_generator_excess)
func store_power(amount: float) -> void:
	current_storage = minf(current_storage + amount, max_storage)


## For PowerGraphManager compatibility
func draw_power(amount: float) -> void:
	current_storage = maxf(0.0, current_storage - amount)


func get_storage_percentage() -> float:
	if max_storage <= 0:
		return 0.0
	return current_storage / max_storage
