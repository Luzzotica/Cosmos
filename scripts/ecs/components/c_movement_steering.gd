class_name C_MovementSteering
extends Component
## Shared steering params for all movement types. Config only, no logic.

@export var max_turn_rate_deg: float = 110.0
@export var avoidance_range: float = 18.0
@export var avoidance_force: float = 22.0
@export var avoidance_scan_range: float = 25.0
@export var avoidance_cone_deg: float = 32.0
@export var separation_radius: float = 6.0
@export var separation_force: float = 35.0
