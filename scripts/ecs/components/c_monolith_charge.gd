class_name C_MonolithCharge
extends Component
## ECS data component for monolith power absorption with diminishing returns.
## Replaces MonolithCharge node-based component.

@export var power_required: float = 500.0
@export var base_absorption_rate: float = 15.0
@export var curve_exponent: float = 3.0

var absorbed: float = 0.0
var structure_node: Node3D = null


## For power balance - reports current draw rate
func get_power_consumption() -> float:
	if power_required <= 0 or absorbed >= power_required:
		return 0.0
	var fill_ratio: float = absorbed / power_required
	var efficiency: float = pow(1.0 - fill_ratio, curve_exponent)
	return base_absorption_rate * efficiency


func get_charge_percentage() -> float:
	if power_required <= 0:
		return 0.0
	return clampf(100.0 * absorbed / power_required, 0.0, 100.0)


func is_fully_charged() -> bool:
	return absorbed >= power_required
