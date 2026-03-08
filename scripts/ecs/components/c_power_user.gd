class_name C_PowerUser
extends Component
## ECS data component for power consumption.
## Replaces PowerUser node-based component.

@export var use_power_cost: float = 5.0
@export var buffer_capacity: float = 15.0
@export var is_construction_user: bool = false

var power_buffer: float = 0.0
var power_consumption: float = 0.0  # For tracking

var structure_node: Node3D = null


func has_power() -> bool:
	return power_buffer >= use_power_cost


func get_buffer_percentage() -> float:
	if buffer_capacity <= 0:
		return 0.0
	return power_buffer / buffer_capacity
