class_name C_MovementSwarm
extends Component
## Saboteur, Commander - dive in, orbit, circle out, repeat.

@export var max_acceleration: float = 10.0
@export var drag: float = 2.0
@export var orbit_distance: float = 10.0
@export var orbit_error_radius: float = 2.5
@export var swarm_orbit_duration: float = 2.5
@export var swarm_circle_out_duration: float = 1.2
@export var swarm_circle_out_speed_mult: float = 1.15
@export var swarm_enabled: bool = true
## Runtime - systems mutate
@export var current_speed: float = 0.0
@export var orbit_direction: int = 0
## 0=DIVE_IN, 1=ORBIT, 2=CIRCLE_OUT
@export var swarm_phase: int = 0
@export var swarm_timer: float = 0.0
