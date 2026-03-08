class_name C_PowerGenerator
extends Component
## ECS data component for power generation.
## Replaces PowerGenerator node-based component.

@export var power_output: float = 10.0
@export var is_active: bool = true

var current_output: float = 0.0
var structure_node: Node3D = null
