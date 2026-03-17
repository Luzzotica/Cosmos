class_name C_MonolithCharge
extends Component
## ECS component for monolith charge state (win condition).
## Tracks absorption toward power_required.

@export var power_required: float = 500.0
@export var current_charge: float = 0.0
@export var base_absorption_rate: float = 15.0
@export var curve_exponent: float = 3.0
